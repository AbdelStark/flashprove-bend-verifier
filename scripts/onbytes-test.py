#!/usr/bin/env python3
"""Measure native Lean OnBytes whole calls on the same two exact-match inputs as the Bend benchmark."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import resource
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "build" / "verify-on-bytes"
EXAMPLES = ROOT / ".upstream" / "FlashProve" / "examples"


def call(fixture, proof=None):
    doc = (fixture / "README.md").read_text()
    expected = re.search(r"^result-v1 [^\n]+", doc, re.M)[0]
    model = re.search(r" id=([0-9a-f]{64}) ", expected)[1]
    args = [EXE, "verify", fixture / "config", fixture / "ivk", fixture / "example.req",
            fixture / "example.y", proof or fixture / "example.proof", "-id", model, "-q", "-j", "1"]
    meter = ["-l"] if sys.platform == "darwin" else ["-f", "%M peak-kib"]
    start = time.monotonic()
    run = subprocess.run(["/usr/bin/time", *meter, *args], text=True, capture_output=True, timeout=1800,
                         env={**os.environ, "LEAN_ABORT_ON_PANIC": "1"})
    elapsed = time.monotonic() - start
    lines = run.stdout.splitlines()
    if proof is not None:
        if run.returncode != 1 or not lines or not lines[-1].startswith("NO:"):
            raise RuntimeError(f"altered proof returned {run.returncode}: {run.stdout}\n{run.stderr}")
    else:
        record = expected.replace("<64 hex digits>", "lean-verify-on-bytes")
        if run.returncode != 0 or lines[-2:] != [record, "YES"]:
            raise RuntimeError(f"{fixture.name} returned {run.returncode}: {run.stdout}\n{run.stderr}")
    peak = re.search(r"^\s*(\d+)\s+(maximum resident set size|peak-kib)$", run.stderr, re.M)
    if not peak:
        raise RuntimeError(f"peak RSS missing from /usr/bin/time: {run.stderr}")
    mib = int(peak[1]) / (1024 * 1024 if sys.platform == "darwin" else 1024)
    print(f"{fixture.name} {elapsed:.3f}s peak-rss={mib:.1f} MiB exit={run.returncode} {lines[-1]}", flush=True)
    return elapsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=1)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be positive")
    # Match the minimum stack documented in lean/OnBytes/LIMITS.md; affects these children only.
    soft, hard = resource.getrlimit(resource.RLIMIT_STACK)
    if soft != resource.RLIM_INFINITY and soft < 10 * 1024 * 1024:
        resource.setrlimit(resource.RLIMIT_STACK, (10 * 1024 * 1024, hard))
    print(f"verify-on-bytes executable SHA256 {hashlib.sha256(EXE.read_bytes()).hexdigest()}", flush=True)
    for fixture_name in ("accepted-proof", "full-size"):
        fixture = EXAMPLES / fixture_name
        times = [call(fixture) for _ in range(args.samples)]
        print(f"{fixture_name} median {statistics.median(times):.3f}s over {len(times)} whole calls", flush=True)
    small = EXAMPLES / "accepted-proof"
    with tempfile.TemporaryDirectory() as tmp:
        damaged = Path(tmp) / "altered.proof"
        contents = bytearray((small / "example.proof").read_bytes())
        contents[len(contents) // 2] ^= 1
        damaged.write_bytes(contents)
        call(small, damaged)


if __name__ == "__main__":
    main()
