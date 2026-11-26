#!/usr/bin/env python3
"""Runs Bend expectation tests.

A test is a .bend file whose trailing comment lines starting with `#|` hold the exact
stdout its `main` must print (the convention of Bend's own test suite). Usage:

    scripts/bend-test.py [--native] [-j N] [PATH ...]     (default PATH: tests/)

Default lane is `bend <file>` (check, then run on the JS lane: fast to start). `--native`
builds each test with clang and runs the binary (the lane performance is measured on).
Exit status: 0 if every test passes, 1 otherwise, 2 if no test was found.
"""
import argparse
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BEND = ROOT / ".toolchain" / "bend" / "bin" / "bend"
ENV = {**os.environ, "BEND_NO_TELEMETRY": "1"}


def expected_lines(path: Path) -> list[str] | None:
    lines = [l[2:] for l in path.read_text().splitlines() if l.startswith("#|")]
    return lines or None


def run(path: Path, native: bool, timeout: int) -> tuple[bool, str]:
    want = expected_lines(path)
    try:
        if native:
            with tempfile.TemporaryDirectory() as tmp:
                exe = Path(tmp) / "t"
                build = subprocess.run([BEND, path, "-o", exe], capture_output=True, text=True,
                                       env=ENV, timeout=timeout)
                if build.returncode != 0:
                    return False, "build failed:\n" + build.stdout + build.stderr
                proc = subprocess.run([exe], capture_output=True, text=True, env=ENV, timeout=timeout)
        else:
            proc = subprocess.run([BEND, path], capture_output=True, text=True, env=ENV, timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, f"timed out after {timeout}s"
    got = proc.stdout.splitlines()
    if proc.returncode:
        return False, f"process exited {proc.returncode}:\n" + proc.stdout + proc.stderr
    if got == want:
        return True, ""
    return False, "expected:\n  " + "\n  ".join(want) + "\ngot:\n  " + "\n  ".join(got) + \
        ("\nstderr:\n" + proc.stderr if proc.stderr else "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("paths", nargs="*", default=[str(ROOT / "tests")])
    ap.add_argument("--native", action="store_true", help="build with clang and run the binary")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4, help="tests run at once")
    ap.add_argument("--timeout", type=int, default=300, help="seconds per test")
    args = ap.parse_args()
    if not BEND.exists():
        print(f"bend-test: {BEND} not found; run `make bootstrap`", file=sys.stderr)
        return 2
    files: list[Path] = []
    for p in map(Path, args.paths):
        files += sorted(p.rglob("*.bend")) if p.is_dir() else [p]
    # A test file without expectations would otherwise drop out of the count unnoticed.
    missing = [f for f in files if expected_lines(f) is None]
    if missing or not files:
        for f in missing:
            print(f"bend-test: {f} has no `#|` expectation lines", file=sys.stderr)
        print("bend-test: every .bend file given must be a test with `#|` expectation lines", file=sys.stderr)
        return 2
    tests = files
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        results = list(pool.map(lambda f: run(f, args.native, args.timeout), tests))
    failed = 0
    for f, (ok, detail) in zip(tests, results):
        rel = f.resolve().relative_to(ROOT) if f.resolve().is_relative_to(ROOT) else f
        print(("PASS  " if ok else "FAIL  ") + str(rel))
        if not ok:
            failed += 1
            print("  " + detail.replace("\n", "\n  "))
    print(f"PASS: {len(tests) - failed} / {len(tests)}" + (" (native)" if args.native else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
