#!/usr/bin/env python3
"""REQ-ASSURE-2: disable one refusal at a time and see whether any test notices.

A mutant rewrites one `require(COND, "NO: name")` in src/ as `require(Bool.or(COND, True{}), ...)`:
the condition is still evaluated, so linear values are still consumed, but the check always
passes. Each mutant is built in a private copy of the checkout and run against the suites below,
fastest first, until one fails. A mutant no suite kills is a survivor: it needs a test that the
check alone refuses, or a reason why no input reaches it.

    scripts/mutate-refusals.py --list
    scripts/mutate-refusals.py [-j JOBS] [--sites 0-40] [--out FILE]
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SUITES = [
    ["standalone-test"],
    ["standalone-rejections"],
    ["request-claims-test"],
    ["fuzz", "FUZZ_ARGS=-n 64 --seed mutants"],
    ["standalone-extended"],
    ["stages-test"],
    ["test", "test-native"],
]
CALL = re.compile(r"\brequire\(")


def arguments(text: str, start: int) -> tuple[int, int, int] | None:
    """Span of the first argument of the call whose '(' is at start, if its second is a "NO: " literal."""
    depth, comma, i = 0, None, start
    while i < len(text):
        c = text[i]
        if c == '"':
            i = text.index('"', i + 1)
        elif c in "([{<" and not (c == "<" and text[i + 1:i + 2] in ("-", "=")):
            depth += 1
        elif c in ")]}>" and not (c == ">" and text[i - 1:i] in ("-", "=")):
            depth -= 1
            if depth == 0:
                break
        elif c == "," and depth == 1 and comma is None:
            comma = i
        i += 1
    if comma is None or not text[comma + 1:].lstrip().startswith('"NO: '):
        return None
    return start + 1, comma, i


def sites() -> list[dict]:
    found = []
    for path in sorted((ROOT / "src").glob("*.bend")):
        text = path.read_text()
        for m in CALL.finditer(text):
            if text[:m.start()].rsplit("\n", 1)[-1].lstrip().startswith("def "):
                continue
            span = arguments(text, m.end() - 1)
            if span:
                begin, comma, _ = span
                name = re.match(r'\s*"NO: ([^"]*)"', text[comma + 1:])[1]
                found.append({"file": path.name, "offset": begin, "end": comma,
                              "line": text.count("\n", 0, m.start()) + 1, "name": name})
    return found


def mutate(copy: Path, site: dict) -> None:
    path = copy / "src" / site["file"]
    text = path.read_text()
    cond = text[site["offset"]:site["end"]]
    path.write_text(text[:site["offset"]] + f"Bool.or({cond}, True{{}})" + text[site["end"]:])


def make(copy: Path, goals: list[str], log: Path) -> bool:
    with log.open("a") as out:
        out.write(f"\n$ make {' '.join(goals)}\n")
        out.flush()
        return subprocess.run(["make", *goals], cwd=copy, stdout=out, stderr=subprocess.STDOUT,
                              env={**os.environ, "BEND_NO_TELEMETRY": "1"}).returncode == 0


def run(index: int, site: dict, work: Path, logs: Path) -> dict:
    start = time.monotonic()
    copy = work / f"mutant-{index:03d}"
    shutil.copytree(ROOT, copy, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", "build", ".toolchain", ".upstream"))
    for name in (".toolchain", ".upstream"):
        (copy / name).symlink_to((ROOT / name).resolve())
    (copy / "build").mkdir()
    for name in ("plans", "tables", "cp_verify"):
        source = ROOT / "build" / name
        if source.is_dir():
            shutil.copytree(source, copy / "build" / name)
        elif source.exists():
            shutil.copy2(source, copy / "build" / name)
    mutate(copy, site)
    log = logs / f"mutant-{index:03d}.log"
    log.write_text(f"{site['file']}:{site['line']} NO: {site['name']}\n")
    row = {"index": index, **{k: site[k] for k in ("file", "line", "name")}}
    if not make(copy, ["standalone"], log):
        row["outcome"] = "does not build"
    else:
        row["outcome"] = "survived"
        for goals in SUITES:
            if not make(copy, goals, log):
                row["outcome"], row["killed_by"] = "killed", " ".join(goals)
                break
    row["seconds"] = round(time.monotonic() - start)
    shutil.rmtree(copy, ignore_errors=True)
    print(json.dumps(row), flush=True)
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--list", action="store_true", help="print the mutable refusal sites and stop")
    ap.add_argument("--sites", help="a range such as 0-40 (default: all)")
    ap.add_argument("-j", type=int, default=2, help="mutants in parallel")
    ap.add_argument("--out", type=Path, help="write every mutant's outcome as JSON")
    args = ap.parse_args()
    found = sites()
    if args.list:
        for i, s in enumerate(found):
            print(f"{i:3d} {s['file']}:{s['line']} NO: {s['name']}")
        return 0
    lo, hi = (map(int, args.sites.split("-")) if args.sites else (0, len(found) - 1))
    for needed in ("cp_verify", "plans", "tables"):
        if not (ROOT / "build" / needed).exists():
            ap.error(f"build/{needed} is missing: run `make standalone oracle` first")
    work = Path(tempfile.mkdtemp(prefix="mutants-", dir=ROOT / "build"))
    logs = work / "logs"
    logs.mkdir()
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        rows = list(pool.map(lambda i: run(i, found[i], work, logs), range(lo, hi + 1)))
    if args.out:
        args.out.write_text(json.dumps(rows, indent=1) + "\n")
    survivors = [r for r in rows if r["outcome"] != "killed"]
    print(f"mutants: {len(rows)}, killed: {len(rows) - len(survivors)}, not killed: {len(survivors)} (logs in {logs})")
    for r in survivors:
        print(f"  {r['outcome']}: {r['file']}:{r['line']} NO: {r['name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
