#!/usr/bin/env python3
"""REQ-PERF-5: fail when the small exact-match call costs more CPU, relative to C++, than the budget allows.

Runs the paired benchmark on accepted-proof (Bend with one worker, cp_verify with -j 1, one verified
warmup each, then alternating samples) and compares the ratio of median CPU seconds with
scripts/perf-budget.json. Both programs run on the same runner, so the ratio cancels most of the
difference between machines. Lower the budget in the pull request that earns it.
"""
import argparse
import json
from pathlib import Path
from statistics import median
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def ratio(results: dict, key: str) -> tuple[float, float, float]:
    cost = {name: median(r[key] for r in results["samples"] if r["program"] == name)
            for name in ("verify-bend", "cp_verify")}
    return cost["verify-bend"] / cost["cp_verify"], cost["verify-bend"], cost["cp_verify"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--samples", type=int, default=3)
    ap.add_argument("--budget", type=Path, default=ROOT / "scripts/perf-budget.json")
    args = ap.parse_args()
    budget = json.loads(args.budget.read_text())
    limit = budget["ratio"] * (1 + budget["tolerance"])
    out = ROOT / "build" / f"perf-gate-{time.strftime('%Y%m%dT%H%M%S')}"
    subprocess.run([sys.executable, "-B", ROOT / "scripts/benchmark-standalone.py", "--compare", "cpp",
                    "--fixture", "accepted-proof", "--samples", str(args.samples), "--output", out],
                   check=True, stdout=subprocess.DEVNULL)
    results = json.loads((out / "results.json").read_text())
    measured, bend, cpp = ratio(results, "cpu_s")
    wall = ratio(results, "wall_s")
    verdict = "within" if measured <= limit else "OVER"
    print(f"perf-gate: {results['host']['cpu']}: wall {wall[1]:.2f} s / {wall[2]:.2f} s = {wall[0]:.2f}x")
    print(f"perf-gate: Bend {bend:.2f} s / C++ {cpp:.2f} s CPU = {measured:.2f}x, "
          f"{verdict} the budget {budget['ratio']:.2f}x + {budget['tolerance']:.0%} = {limit:.2f}x ({out.name})")
    return 0 if measured <= limit else 1


if __name__ == "__main__":
    sys.exit(main())
