#!/usr/bin/env python3
"""Mutate derived G0 equations after parsing the same authentic request in every run."""
import argparse
from pathlib import Path
import subprocess
import tempfile

from compile_bend import native

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
FIXTURE = ROOT / ".upstream/FlashProve/examples/accepted-proof"
CASES = {
    "honest": (0, "checked\n", ""),
    "bat": (1, "", "NO: request-carry-proximity\n"),
    "fold": (1, "", "NO: request-carry-proximity\n"),
    "merge": (1, "", "NO: lin-own-proximity\n"),
    "weight": (1, "", "NO: lin-own-proximity\n"),
    "attention": (1, "", "NO: request-carry-proximity\n"),
    "head": (1, "", "NO: request-carry-proximity\n"),
}


def check(binary):
    for mode, expected in CASES.items():
        result = subprocess.run([binary, mode, FIXTURE, BUILD / "tables", BUILD / "plans"],
                                capture_output=True, text=True, timeout=600)
        observed = result.returncode, result.stdout, result.stderr
        if observed != expected:
            raise SystemExit(f"{mode} expected {expected!r}, got {observed!r}")
        print(f"{mode}: {(result.stdout or result.stderr).strip()}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, help="use a precompiled request_claims probe")
    args = parser.parse_args()
    if args.exe:
        check(args.exe.resolve())
        return
    BUILD.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=BUILD) as temp:
        executable = Path(temp) / "request-claims"
        native(ROOT / ".toolchain/bend/bin/bend", ROOT / "scripts/probes/request_claims.bend", executable)
        check(executable)


if __name__ == "__main__":
    main()
