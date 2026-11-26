#!/usr/bin/env python3
"""Checks (types, termination, proofs) every .bend file under the given directories with
`bend <file> --check-only`. Usage: scripts/bend-check.py [-j N] [FILE_OR_DIR ...]

Pure sources must pass the pinned checker. The native CLI's single execv host effect
has one audited diagnostic below. Exit status: 0 if all checks pass, 1 otherwise.
"""
import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BEND = ROOT / ".toolchain" / "bend" / "bin" / "bend"
ENV = {**os.environ, "BEND_NO_TELEMETRY": "1"}


def check(path: Path) -> tuple[bool, str]:
    proc = subprocess.run([BEND, path, "--check-only"], capture_output=True, text=True, env=ENV)
    out = proc.stdout + proc.stderr
    return proc.returncode == 0 and "SOME PROOFS FAIL" not in out, out


def main() -> int:
    if not BEND.exists():
        print(f"bend-check: {BEND} not found; run `make bootstrap`", file=sys.stderr)
        return 1
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-j", type=int, default=min(os.cpu_count() or 1, 4))
    parser.add_argument("paths", nargs="*", type=Path, default=[ROOT / "src"])
    args = parser.parse_args()
    if args.j < 1:
        parser.error("the job count must be positive")
    files = set()
    for path in args.paths:
        if path.is_dir():
            found = list(path.rglob("*.bend"))
        elif path.is_file() and path.suffix == ".bend":
            found = [path]
        else:
            parser.error(f"expected a Bend source file or directory at {path}")
        if not found:
            parser.error(f"no Bend sources at {path}")
        files.update(found)
    files = sorted(files)
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        results = list(pool.map(check, files))
    failed = [(f, out) for f, (ok, out) in zip(files, results) if not ok]
    for f, out in failed:
        print(f"FAIL  {f}\n  " + out.strip().replace("\n", "\n  "))
    print(f"check: {len(files) - len(failed)} / {len(files)} file(s) OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
