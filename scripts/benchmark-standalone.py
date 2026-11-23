#!/usr/bin/env python3
"""Measure complete native verification calls, checking the fixture's four published closing lines."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
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
    if Path("/proc/cpuinfo").is_file():
        cpu = re.search(r"^model name\s*:\s*(.+)$", Path("/proc/cpuinfo").read_text(), re.M)[1]
    revision = os.environ.get("BENCH_CHECKOUT_REVISION") or subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    return {"os": platform.platform(), "arch": platform.machine(), "cpu": cpu, "git": revision,
            "upstream": (ROOT / "upstream.lock").read_text().strip().splitlines(),
            "toolchain": (ROOT / "toolchain.lock").read_text().strip().splitlines()}


def measure(program, case, digest, sample, work, logs):
    stem = f"{case.name}-{program.name}-{sample}"
    timing = logs / f"{stem}.time"
    # BEND_THREADS=1 selects one native worker; the C++ verifier's equivalent is -j 1.
    common = [case / name for name in ("config", "ivk", "example.req", "example.y", "example.proof")]
    options = ["-data", "data"] if program.name == "verify-bend" else ["-j", "1"]
    cmd = [program, *common, "-id", (case / "ID.txt").read_text().strip(), "-q", *options]
    timer = ["/usr/bin/time", "-o", timing]
    if platform.system() == "Darwin":
        timer.append("-l")
    else:
        timer.extend(["-f", "%M peak-kib"])
    env = {**os.environ, "LC_ALL": "C", "BEND_THREADS": "1", "PATH": str(work / "empty-path")}
    start = time.monotonic_ns()
    with (logs / f"{stem}.stdout").open("w") as stdout, (logs / f"{stem}.stderr").open("w") as stderr:
        result = subprocess.run([*timer, *cmd], cwd=work, env=env, stdout=stdout, stderr=stderr)
    seconds = (time.monotonic_ns() - start) / 1e9
    received = (logs / f"{stem}.stdout").read_text().splitlines()[-4:]
    if result.returncode != 0 or received != expected(case, digest) or received[-1] != "YES":
        raise RuntimeError(f"{stem}: expected verified closing record and YES, exit {result.returncode}, see {logs}")
    match = re.search(r"^\s*(\d+)\s+(maximum resident set size|peak-kib)$", timing.read_text(), re.M)
    if not match:
        raise RuntimeError(f"{stem}: cannot read process peak RSS from {timing}")
    rss = int(match[1]) // (1024 if match[2] == "maximum resident set size" else 1)
    print(f"{stem}: {seconds:.3f} s, {rss:,} KiB peak RSS, YES", flush=True)
    return {"fixture": case.name, "program": program.name, "sample": sample, "wall_s": seconds,
            "rss_kib": rss, "exit": result.returncode, "record": received}


def report(data):
    for name in ("accepted-proof", "full-size"):
        times = {}
        for binary in ("cp_verify", "verify-bend"):
            rows = [r for r in data if (r["program"], r["fixture"]) == (binary, name)]
            values = [r["wall_s"] for r in rows]
            times[binary] = median(values)
            rss = [r["rss_kib"] for r in rows]
            print(f"{name} {binary}: median {median(values):.3f} s, range {min(values):.3f}–{max(values):.3f}, "
                  f"RSS {min(rss):,}–{max(rss):,} KiB")
        print(f"{name} standalone/C++ median ratio {times['verify-bend'] / times['cp_verify']:.3f}")


def markdown(data):
    host = data["host"]
    lines = ["# Native standalone whole calls", "",
             f"{host['os']} on {host['cpu']} ({host['arch']}). Checkout `{host['git']}`.", "",
             "Each binary completed one verified warmup at each size before the measured fresh processes.", "",
             "Each sample matched all four closing lines from the fixture and exited zero.", "",
             "| Exact fixture | Program | Ordered wall times (s) | Median (s) | Peak RSS range (KiB) |",
             "| --- | --- | --- | ---: | ---: |"]
    ratios = []
    for name in ("accepted-proof", "full-size"):
        medians = {}
        for binary in ("cp_verify", "verify-bend"):
            rows = [r for r in data["samples"] if (r["fixture"], r["program"]) == (name, binary)]
            times = [r["wall_s"] for r in rows]
            memory = [r["rss_kib"] for r in rows]
            medians[binary] = median(times)
            wall = ", ".join(f"{v:.3f}" for v in times)
            lines.append(f"| {name} | `{binary}` | {wall} | {median(times):.3f} | {min(memory):,}–{max(memory):,} |")
        ratios.append(f"On {name}, the standalone/C++ median ratio was {medians['verify-bend'] / medians['cp_verify']:.3f}.")
    lines.extend(["", " ".join(ratios), "", "| Program | Executable SHA-256 | Reported source digest |",
                  "| --- | --- | --- |"])
    for name, ids in data["binaries"].items():
        lines.append(f"| `{name}` | `{ids['sha256']}` | `{ids['source_digest']}` |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--output", type=Path, help="new directory for raw process logs and results.json")
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be positive")
    logs = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="standalone-results.", dir=BUILD))
    if args.output:
        logs.mkdir(parents=True)
    print(f"Result directory: {logs}", flush=True)
    digests = build_digests(True)
    digests["verify-bend"] = (BUILD / "verify-bend.digest").read_text().strip()
    if not re.fullmatch(SHA, digests["verify-bend"]) or digests["verify-bend"] == digests["cp_verify"]:
        raise ValueError("unauthenticated standalone source identity")
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
            binary = Path(shutil.copy2(BUILD / name, work))
            data["binaries"][name] = {"sha256": sha256(binary), "source_digest": digest}
        for fixture in ("accepted-proof", "full-size"):
            case = EXAMPLES / fixture
            data["fixtures"][fixture] = check_inputs(case)
            print(f"Verified warmups on {fixture} (excluded from reported samples)", flush=True)
            for name, digest in digests.items():
                data["warmups"].append(measure(work / name, case, digest, 1, work, warmup_logs))
            for i in range(args.samples):
                order = list(digests) if i % 2 == 0 else list(reversed(digests))
                for name in order:
                    data["samples"].append(measure(work / name, case, digests[name], i+1, work, logs))
                    (logs / "results.json").write_text(json.dumps(data, indent=2) + "\n")
    (logs / "report.md").write_text(markdown(data))
    report(data["samples"])


if __name__ == "__main__":
    main()
