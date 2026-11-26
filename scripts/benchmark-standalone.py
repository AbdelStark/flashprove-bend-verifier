#!/usr/bin/env python3
"""Measure complete native verification calls, checking the fixture's four published closing lines.

For paired revisions, build both binaries and supply --compare bend --before OLD --after NEW
--workers N. Both executables must support -j and -timing and have adjacent .digest files.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import resource
import shutil
from statistics import median
import subprocess
import tempfile
import time

from e2e import BUILD, EXAMPLES, ROOT, SHA, build_digests, inputs


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def check_inputs(case):
    hashes = {}
    for line in (case / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        name = name.removeprefix("*")
        if sha256(case / name) != digest:
            raise ValueError(f"{case.name}/{name}: fixture SHA-256 mismatch")
        hashes[name] = digest
    return {"proof_bytes": (case / "example.proof").stat().st_size, "proof_sha256": hashes["example.proof"],
            "manifest_sha256": sha256(case / "SHA256SUMS")}


def expected(case, digest):
    text = (case / "README.md").read_text()
    record = re.search(r"^commitment: [^\n]+\nproof of work: [^\n]+\nresult-v1 [^\n]+\n[^\n]+", text, re.M)[0]
    return record.replace("<64 hex digits>", digest).splitlines()


def machine():
    cpu = platform.processor() or platform.machine()
    if platform.system() == "Darwin":
        cpu = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    elif Path("/proc/cpuinfo").is_file():
        # Some Linux arm64 kernels report only the CPU implementer and part number.
        model = re.search(r"^model name\s*:\s*(.+)$", Path("/proc/cpuinfo").read_text(), re.M)
        if model:
            cpu = model[1]
    revision = os.environ.get("BENCH_CHECKOUT_REVISION") or subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    return {"os": platform.platform(), "arch": platform.machine(), "cpu": cpu, "git": revision,
            "cpu_affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
            "upstream": (ROOT / "upstream.lock").read_text().strip().splitlines(),
            "toolchain": (ROOT / "toolchain.lock").read_text().strip().splitlines()}


def measure(program, case, digest, sample, work, logs, workers, observe_workers=False):
    stem = f"{case.name}-{program.name}-{sample}"
    timing = logs / f"{stem}.time"
    common = inputs(case)
    cmd = [program]
    lean = program.name == "verify-on-bytes"
    if lean:
        cmd.append("verify")
    cmd.extend([*common, "-id", (case / "ID.txt").read_text().strip(), "-q"])
    if program.name in ("verify-bend", "before"):
        cmd.extend(["-data", "data"])
    if workers is not None:
        cmd.extend(["-j", str(workers)])
    if observe_workers:
        cmd.append("-timing")
    timer = ["/usr/bin/time", "-o", timing]
    if platform.system() == "Darwin":
        timer.append("-l")
    else:
        timer.extend(["-f", "%M peak-kib\n%U user %S sys"])
    env = {**os.environ, "LC_ALL": "C", "LEAN_ABORT_ON_PANIC": "1", "PATH": str(work / "empty-path")}
    start = time.monotonic_ns()
    with (logs / f"{stem}.stdout").open("w") as stdout, (logs / f"{stem}.stderr").open("w") as stderr:
        result = subprocess.run([*timer, *cmd], cwd=work, env=env, stdout=stdout, stderr=stderr)
    seconds = (time.monotonic_ns() - start) / 1e9
    output = (logs / f"{stem}.stdout").read_text().splitlines()
    received = output if program.name in ("before", "verify-bend") else output[-4:]
    record = expected(case, digest)
    if lean:
        record = [line.replace("the bound within a third of the distance", "the proved lemma") for line in record]
    if result.returncode != 0 or received != record or received[-1] != "YES":
        raise RuntimeError(f"{stem}: expected verified closing record and YES, exit {result.returncode}, see {logs}")
    if observe_workers:
        lines = (logs / f"{stem}.stderr").read_text().splitlines()
        if lines[:1] != [f"timing: workers {workers}"]:
            raise RuntimeError(f"{stem}: expected {workers} runtime workers, received {lines[:1]}")
    usage = timing.read_text()
    cpu = re.search(r"([\d.]+) user\s+([\d.]+) sys", usage)
    match = re.search(r"^\s*(\d+)\s+(maximum resident set size|peak-kib)$", usage, re.M)
    if not match or not cpu:
        raise RuntimeError(f"{stem}: cannot read process peak RSS from {timing}")
    rss = int(match[1]) // (1024 if match[2] == "maximum resident set size" else 1)
    print(f"{stem}: {seconds:.3f} s, {rss:,} KiB peak RSS, YES", flush=True)
    row = {"fixture": case.name, "program": program.name, "sample": sample, "wall_s": seconds,
           "rss_kib": rss, "cpu_s": float(cpu[1]) + float(cpu[2]), "exit": result.returncode, "record": received}
    if observe_workers:
        row["workers_observed"] = workers
    return row


def markdown(data):
    host = data["host"]
    lines = ["# Native CPU verification", "",
             f"{host['cpu']} ({host['arch']}), {host['os']}. Checkout `{host['git']}`.", "",
             "Every call ran in a fresh process and matched all four published closing lines. "
             "One verified warmup per program and fixture precedes the measured calls.", "",
             "| Exact fixture | Program | Wall seconds in sample order | Median wall (s) | Median CPU (s) | Peak RSS range (KiB) |",
             "| --- | --- | --- | ---: | ---: | ---: |"]
    for fixture in data["fixtures"]:
        for program in data["binaries"]:
            rows = [r for r in data["samples"] if (r["fixture"], r["program"]) == (fixture, program)]
            times = [r["wall_s"] for r in rows]
            cpu = median(r["cpu_s"] for r in rows)
            rss = [r["rss_kib"] for r in rows]
            wall = ", ".join(f"{t:.3f}" for t in times)
            lines.append(f"| {fixture} | `{program}` | {wall} | {median(times):.3f} | {cpu:.2f} | {min(rss):,}–{max(rss):,} |")

    lines.extend(["", "| Program | Workers requested | Executable SHA-256 | Reported source digest |",
                  "| --- | --- | --- | --- |"])
    for name, ids in data["binaries"].items():
        lines.append(f"| `{name}` | {ids['workers']} | `{ids['sha256']}` | `{ids['source_digest']}` |")
    for fixture in data["fixtures"]:
        medians = {name: median(r["wall_s"] for r in data["samples"] if
                               (r["fixture"], r["program"]) == (fixture, name)) for name in data["binaries"]}
        for name, seconds in medians.items():
            if name != "verify-bend":
                lines.extend(["", f"On {fixture}, Bend took {medians['verify-bend'] / seconds:.3f} times "
                              f"the median wall time of `{name}`."])
    return "\n".join(lines) + "\n"


def bend_digest(program):
    digest = Path(str(program) + ".digest").read_text().strip()
    if not re.fullmatch(SHA, digest):
        raise ValueError(f"Invalid Bend source digest for {program}")
    return digest



def screen_workers(binary, counts, samples, logs):
    """Select workers on the full-size fixture before running the independent Lean pairing."""
    case = EXAMPLES / "full-size"
    digest = bend_digest(binary)
    data = {"host": machine(), "harness_sha256": sha256(Path(__file__)), "binary_sha256": sha256(binary),
            "source_digest": digest, "fixture": check_inputs(case), "warmups": [], "samples": []}
    with tempfile.TemporaryDirectory(dir=BUILD) as temp:
        work = Path(temp)
        program = Path(shutil.copy2(binary, work / "verify-bend"))
        (work / "empty-path").mkdir()
        for name in ("tables", "plans"):
            shutil.copytree(BUILD / name, work / "data" / name)
        # Reverse the order on alternate rounds so high worker counts do not always run last.
        for trial in range(samples + 1):
            for count in (counts if trial % 2 else reversed(counts)):
                directory = logs / ("warmups" if trial == 0 else "samples") / str(count)
                directory.mkdir(parents=True, exist_ok=True)
                row = measure(program, case, digest, trial, work, directory, count, observe_workers=trial == 0)
                row["workers"] = count
                data["warmups" if trial == 0 else "samples"].append(row)
                (logs / "results.json").write_text(json.dumps(data, indent=2) + "\n")
    medians = {n: median(row["wall_s"] for row in data["samples"] if row["workers"] == n) for n in counts}
    winner = min(counts, key=lambda n: (medians[n], n))
    data["selected_workers"] = winner
    (logs / "results.json").write_text(json.dumps(data, indent=2) + "\n")
    for count, seconds in medians.items():
        print(f"{count:>3} workers   {seconds:.3f} s median")
    print(f"Selected {winner} workers for the independent comparison.")

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--output", type=Path, help="new directory for raw process logs and results.json")
    parser.add_argument("--compare", choices=["cpp", "lean", "bend", "workers"], default="cpp")
    parser.add_argument("--before", type=Path, help="prior Bend executable and adjacent .digest (required for --compare bend)")
    parser.add_argument("--after", type=Path, default=BUILD / "verify-bend",
                        help="candidate Bend executable and adjacent .digest (default: build/verify-bend)")
    parser.add_argument("--fixture", choices=["accepted-proof", "full-size"], action="append",
                        help="exact-match fixture to run (default: both)")
    parser.add_argument("--workers", type=int, default=1, help="Bend workers requested, applied to both binaries with --compare bend")
    parser.add_argument("--worker-counts", type=int, nargs="+", help="pool sizes to screen on the full-size fixture")
    args = parser.parse_args()
    if args.compare == "workers":
        if not args.worker_counts or not all(1 <= n <= 128 for n in args.worker_counts):
            parser.error("worker screening requires --worker-counts between 1 and 128")
        if args.before or args.fixture and args.fixture != ["full-size"]:
            parser.error("worker screening runs one Bend binary on the full-size fixture")
    elif args.worker_counts:
        parser.error("--worker-counts requires --compare workers")
    if args.compare == "bend" and args.before is None:
        parser.error("--compare bend requires --before")
    if not 1 <= args.workers <= 128:
        parser.error("--workers must be between 1 and 128")
    if platform.system() == "Darwin" and args.compare == "lean":
        soft, hard = resource.getrlimit(resource.RLIMIT_STACK)
        if soft != resource.RLIM_INFINITY and soft < 10 * 1024**2:
            resource.setrlimit(resource.RLIMIT_STACK, (10 * 1024**2, hard))
    if args.samples < 1:
        parser.error("--samples must be positive")
    logs = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="standalone-results.", dir=BUILD))
    if args.output:
        logs.mkdir(parents=True)
    print(f"Result directory: {logs}", flush=True)
    if args.compare == "workers":
        screen_workers(args.after, sorted(set(args.worker_counts)), args.samples, logs)
        return
    digests = {}
    if args.compare == "cpp":
        digests = build_digests(True)
    elif args.compare == "lean":
        digests = {"verify-on-bytes": "lean-verify-on-bytes"}
    workers = {name: 1 for name in digests}
    if args.before:
        digests["before"] = bend_digest(args.before)
        # Earlier releases lack -j. Keep their historical behavior in three-program comparisons.
        workers["before"] = args.workers if args.compare == "bend" else None
    digests["verify-bend"] = bend_digest(args.after)
    workers["verify-bend"] = args.workers
    if digests["verify-bend"] == digests.get("cp_verify"):
        raise ValueError("standalone and reference source identities must differ")
    data = {"host": machine(), "harness_sha256": sha256(Path(__file__)), "binaries": {}, "fixtures": {},
            "warmups": [], "samples": []}
    warmup_logs = logs / "warmups"
    warmup_logs.mkdir()
    with tempfile.TemporaryDirectory(dir=BUILD) as temp:
        work = Path(temp)
        (work / "empty-path").mkdir()
        for name in ("tables", "plans"):
            shutil.copytree(BUILD / name, work / "data" / name)
        for name, digest in digests.items():
            source = {"before": args.before, "verify-bend": args.after}.get(name, BUILD / name)
            binary = Path(shutil.copy2(source, work / name))
            data["binaries"][name] = {"sha256": sha256(binary), "source_digest": digest,
                                      "workers": workers[name] if workers[name] is not None else "original default"}
        for fixture in dict.fromkeys(args.fixture or ["accepted-proof", "full-size"]):
            case = EXAMPLES / fixture
            data["fixtures"][fixture] = check_inputs(case)
            print(f"Verified warmups on {fixture} (excluded from reported samples)", flush=True)
            for name, digest in digests.items():
                data["warmups"].append(measure(work / name, case, digest, 1, work, warmup_logs, workers[name],
                                              observe_workers=name == "verify-bend" or (args.compare == "bend" and name == "before")))
            for i in range(args.samples):
                order = list(digests) if i % 2 == 0 else list(reversed(digests))
                if len(digests) == 3:
                    # Rotate the launch position of each binary across three measured triples.
                    names = list(digests)
                    pos = i % len(names)
                    order = names[pos:] + names[:pos]
                for name in order:
                    data["samples"].append(measure(work / name, case, digests[name], i+1, work, logs, workers[name]))
                    (logs / "results.json").write_text(json.dumps(data, indent=2) + "\n")
    (logs / "report.md").write_text(markdown(data))
    print(markdown(data))


if __name__ == "__main__":
    main()
