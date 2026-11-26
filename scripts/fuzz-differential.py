#!/usr/bin/env python3
"""Differential mutation fuzzing of the standalone Bend verifier against cp_verify.

Each case alters one input file of a genuine proof set (one bit, one byte, a zeroed or
swapped word, a truncation or an extension) and runs both verifiers on the same bytes.
A sound verifier never accepts where the reference refuses. The run fails on such a case,
on any crash, timeout or unexpected exit from either verifier, and when the unchanged set
is not accepted by both. A case is reproducible from its seed and index.

    scripts/fuzz-differential.py [-n N] [--seed S] [-j J] [--out FILE] [FIXTURE ...]

Default fixtures: the two small proof sets. Exit status: 0 if every case passes, 1 otherwise.
"""
import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from e2e import stated_policy
from worker_parity import run_cli

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
EXAMPLES = ROOT / ".upstream/FlashProve/examples"
FILES = ["example.proof", "ivk/key.bin", "ivk/leaf/0.bin", "example.req", "example.y",
         "config/policy.txt", "config/KL.bin", "config/layout.txt"]
WEIGHTS = [60, 12, 12, 4, 2, 4, 3, 3]
KINDS = ["bit", "bit", "bit", "bit", "byte", "byte", "zero8", "swap8", "truncate", "append", "inc_word"]


def mutate(data: bytearray, rng: random.Random) -> tuple[bytes, str]:
    """Returns bytes that differ from `data`, with a description of the change."""
    kind = rng.choice(KINDS)
    n = len(data)
    if kind == "byte":
        at = rng.randrange(n)
        data[at] ^= rng.randrange(1, 256)
        return bytes(data), f"byte {at}"
    if kind == "zero8" and n >= 8:
        at = rng.randrange(n - 7)
        data[at:at + 8] = bytes(8) if any(data[at:at + 8]) else b"\x01" + bytes(7)
        return bytes(data), f"zero8 {at}"
    if kind == "swap8" and n >= 16:
        a = rng.randrange(n // 8 - 1) * 8
        if data[a:a + 8] != data[a + 8:a + 16]:
            data[a:a + 8], data[a + 8:a + 16] = data[a + 8:a + 16], data[a:a + 8]
            return bytes(data), f"swap8 {a}"
    if kind == "truncate" and n > 1:
        cut = min(rng.choice([1, 4, 8, 24, 32, rng.randrange(1, min(n, 4096))]), n - 1)
        return bytes(data[:-cut]), f"truncate {cut}"
    if kind == "append":
        extra = rng.randbytes(rng.choice([1, 4, 8, 32]))
        return bytes(data) + extra, f"append {len(extra)}"
    if kind == "inc_word" and n >= 8:
        at = rng.randrange(n // 8) * 8
        word = (int.from_bytes(data[at:at + 8], "little") + rng.choice([1, -1])) % (1 << 64)
        data[at:at + 8] = word.to_bytes(8, "little")
        return bytes(data), f"inc_word {at}"
    at = rng.randrange(n)
    bit = rng.randrange(8)
    data[at] ^= 1 << bit
    return bytes(data), f"bit {at}.{bit}"


def classify(code: int, lines: list[str]) -> str:
    last = lines[-1] if lines else ""
    if code == 0 and (last == "YES" or last.startswith("WITHIN LIMITS")):
        return "accept"
    if code == 1 and last.startswith("NO:"):
        return "reject"
    return f"signal{-code}" if code < 0 else f"exit{code}"


def run_case(example: Path, identity: str, policy: list[str], work: str, seed: str, index: int,
             timeout: int, parity_dir=None) -> dict:
    # A negative index is the control: the genuine set, unchanged.
    rng = random.Random(f"{seed}:{example.name}:{index}")
    name = rng.choices(FILES, WEIGHTS)[0] if index >= 0 else None
    with tempfile.TemporaryDirectory(dir=work) as tmp:
        case = Path(tmp)
        for sub in ("config", "ivk/leaf"):
            (case / sub).mkdir(parents=True)
        for other in FILES:
            if other != name:
                (case / other).symlink_to(example / other)
        if name:
            mutated, what = mutate(bytearray((example / name).read_bytes()), rng)
            (case / name).write_bytes(mutated)
        else:
            what = "none"
        inputs = [case / "config", case / "ivk", case / "example.req", case / "example.y",
                  case / "example.proof", "-id", identity]
        out = {"fixture": example.name, "index": index, "file": name, "mutation": what}
        for label, cmd, env in (
            ("cpp", [BUILD / "cp_verify", *inputs, *policy], {**os.environ}),
            ("bend", [BUILD / "verify-bend", *inputs, "-data", BUILD, *policy],
             {**os.environ, "PATH": "", "BEND_THREADS": "1"}),
        ):
            try:
                run = run_cli(cmd, cwd=case, env=env, timeout=timeout,
                              parity_dir=parity_dir if label == "bend" else None, case=f"{example.name}-{index}")
                lines = (run.stdout + run.stderr).splitlines()
                out[label], out[label + "_last"] = classify(run.returncode, lines), (lines[-1][:120] if lines else "")
            except subprocess.TimeoutExpired:
                out[label], out[label + "_last"] = "timeout", ""
        return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("fixtures", nargs="*", default=["accepted-proof", "accepted-proof-clipped-gap"])
    ap.add_argument("-n", type=int, default=64, help="cases per fixture")
    ap.add_argument("--seed", default="0")
    ap.add_argument("-j", type=int, default=min(os.cpu_count() or 1, 8))
    ap.add_argument("--timeout", type=int, default=1800, help="seconds per verifier call")
    ap.add_argument("--out", type=Path, help="write every case as JSON")
    ap.add_argument("--parity-dir", type=Path, help="save and compare Bend calls with 1 and 16 workers")
    args = ap.parse_args()
    for exe in ("verify-bend", "cp_verify"):
        if not (BUILD / exe).exists():
            ap.error(f"build/{exe} is missing: run `make standalone oracle`")
    results: list[dict] = []
    work = tempfile.mkdtemp(prefix="fuzz-", dir=BUILD)
    try:
        for name in args.fixtures:
            example = EXAMPLES / name
            identity = (example / "ID.txt").read_text().strip()
            policy = stated_policy(example)
            control = run_case(example, identity, policy, work, args.seed, -1, args.timeout)
            if (control["bend"], control["cpp"]) != ("accept", "accept"):
                print(f"{name}: the unchanged set is not accepted by both: {json.dumps(control)}")
                return 1
            with ThreadPoolExecutor(max_workers=args.j) as pool:
                rows = list(pool.map(lambda i: run_case(example, identity, policy, work, args.seed, i,
                                                        args.timeout, args.parity_dir), range(args.n)))
            results += rows
            tally: dict[tuple[str, str], int] = {}
            for r in rows:
                tally[(r["bend"], r["cpp"])] = tally.get((r["bend"], r["cpp"]), 0) + 1
            print(f"{name}: {args.n} cases, seed {args.seed}")
            for (bend, cpp), count in sorted(tally.items(), key=lambda kv: -kv[1]):
                print(f"  bend={bend:8} cpp={cpp:8} {count}", flush=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if args.out:
        args.out.write_text(json.dumps(results, indent=1))
    unsound = [r for r in results if r["bend"] == "accept" and r["cpp"] != "accept"]
    broken = [r for r in results if not {r["bend"], r["cpp"]} <= {"accept", "reject"}]
    other = [r for r in results if r["bend"] != r["cpp"] and r not in unsound and r not in broken]
    for title, rows in (("UNSOUND: Bend accepts, the reference does not", unsound),
                        ("FAILED: a verifier crashed, timed out or exited unexpectedly", broken),
                        ("other disagreements", other)):
        if rows:
            print(f"{title}: {len(rows)}")
            for r in rows[:40]:
                print("  " + json.dumps(r))
    return 1 if unsound or broken else 0


if __name__ == "__main__":
    sys.exit(main())
