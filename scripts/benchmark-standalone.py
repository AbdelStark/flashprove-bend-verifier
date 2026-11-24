#!/usr/bin/env python3
"""Measure complete native verification calls, checking the fixture's four published closing lines."""
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

from e2e import BUILD, EXAMPLES, ROOT, SHA, build_digests


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
    cpu = platform.processor()
    if platform.system() == "Darwin":
        cpu = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    elif Path("/proc/cpuinfo").is_file():
        cpu = re.search(r"^model name\s*:\s*(.+)$", Path("/proc/cpuinfo").read_text(), re.M)[1]
    revision = os.environ.get("BENCH_CHECKOUT_REVISION") or subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    return {"os": platform.platform(), "arch": platform.machine(), "cpu": cpu, "git": revision,
            "upstream": (ROOT / "upstream.lock").read_text().strip().splitlines(),
            "toolchain": (ROOT / "toolchain.lock").read_text().strip().splitlines()}


def measure(program, case, digest, sample, work, logs, workers):
    stem = f"{case.name}-{program.name}-{sample}"
    timing = logs / f"{stem}.time"
    common = [case / name for name in ("config", "ivk", "example.req", "example.y", "example.proof")]
    cmd = [program]
    lean = program.name == "verify-on-bytes"
    if lean:
        cmd.append("verify")
    cmd.extend([*common, "-id", (case / "ID.txt").read_text().strip(), "-q"])
    if program.name in ("verify-bend", "before"):
        cmd.extend(["-data", "data"])
    if program.name != "before":
        cmd.extend(["-j", str(workers if program.name == "verify-bend" else 1)])
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
    received = (logs / f"{stem}.stdout").read_text().splitlines()[-4:]
    record = expected(case, digest)
    if lean:
        record = [line.replace("the bound within a third of the distance", "the proved lemma") for line in record]
    if result.returncode != 0 or received != record or received[-1] != "YES":
        raise RuntimeError(f"{stem}: expected verified closing record and YES, exit {result.returncode}, see {logs}")
    usage = timing.read_text()
    cpu = re.search(r"([\d.]+) user\s+([\d.]+) sys", usage)
    match = re.search(r"^\s*(\d+)\s+(maximum resident set size|peak-kib)$", usage, re.M)
    if not match or not cpu:
        raise RuntimeError(f"{stem}: cannot read process peak RSS from {timing}")
    rss = int(match[1]) // (1024 if match[2] == "maximum resident set size" else 1)
    print(f"{stem}: {seconds:.3f} s, {rss:,} KiB peak RSS, YES", flush=True)
    return {"fixture": case.name, "program": program.name, "sample": sample, "wall_s": seconds,
            "rss_kib": rss, "cpu_s": float(cpu[1]) + float(cpu[2]), "exit": result.returncode, "record": received}


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--output", type=Path, help="new directory for raw process logs and results.json")
    parser.add_argument("--compare", choices=["cpp", "lean"], default="cpp")
    parser.add_argument("--before", type=Path, help="prior Bend executable with adjacent .digest, run with its default workers")
    parser.add_argument("--fixture", choices=["accepted-proof", "full-size"], action="append",
                        help="exact-match fixture to run (default: both)")
    parser.add_argument("--workers", type=int, default=1, help="CPU workers requested for the current Bend binary")
    args = parser.parse_args()
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
    digests = build_digests(True) if args.compare == "cpp" else {"verify-on-bytes": "lean-verify-on-bytes"}
    if args.before:
        digests["before"] = bend_digest(args.before)
    digests["verify-bend"] = bend_digest(BUILD / "verify-bend")
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
            source = args.before if name == "before" else BUILD / name
            binary = Path(shutil.copy2(source, work / name))
            data["binaries"][name] = {"sha256": sha256(binary), "source_digest": digest,
                                      "workers": "original default" if name == "before" else args.workers if name == "verify-bend" else 1}
        for fixture in dict.fromkeys(args.fixture or ["accepted-proof", "full-size"]):
            case = EXAMPLES / fixture
            data["fixtures"][fixture] = check_inputs(case)
            print(f"Verified warmups on {fixture} (excluded from reported samples)", flush=True)
            for name, digest in digests.items():
                data["warmups"].append(measure(work / name, case, digest, 1, work, warmup_logs, args.workers))
            for i in range(args.samples):
                order = list(digests) if i % 2 == 0 else list(reversed(digests))
                if len(digests) == 3:
                    # Rotate the launch position of each binary across three measured triples.
                    names = list(digests)
                    pos = i % len(names)
                    order = names[pos:] + names[:pos]
                for name in order:
                    data["samples"].append(measure(work / name, case, digests[name], i+1, work, logs, args.workers))
                    (logs / "results.json").write_text(json.dumps(data, indent=2) + "\n")
    (logs / "report.md").write_text(markdown(data))
    print(markdown(data))


if __name__ == "__main__":
    main()
