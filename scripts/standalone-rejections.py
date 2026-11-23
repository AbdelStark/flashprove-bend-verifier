#!/usr/bin/env python3
"""Compare standalone rejection of the pinned upstream altered copies with cp_verify."""
import argparse
from importlib.util import module_from_spec, spec_from_file_location
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
EXAMPLES = ROOT / ".upstream/FlashProve/examples"
CASES = EXAMPLES / "rejected-proofs"


def oracle(command, ending):
    result = subprocess.run(command, capture_output=True, text=True, timeout=1800)
    if result.returncode or result.stdout.splitlines()[-1:] != [ending]:
        raise RuntimeError(f"corpus oracle failed\n{result.stdout[-1000:]}\n{result.stderr[-1000:]}")


def reject(example, altered, identity, policy, proof_name="example.proof"):
    def use(name):
        path = altered / name
        return path if path.exists() else example / name

    proof = altered / proof_name
    cmd = [BUILD / "verify-bend", use("config"), use("ivk"), use("example.req"), use("example.y"),
           proof if proof.exists() else example / "example.proof", "-id", identity, "-data", BUILD, *policy]
    env = {**os.environ, "PATH": "", "BEND_THREADS": "1"}
    run = subprocess.run(cmd, cwd=altered, env=env, capture_output=True, text=True, timeout=600)
    lines = (run.stdout + run.stderr).splitlines()
    if run.returncode != 1 or not lines or not lines[-1].startswith("NO: "):
        raise RuntimeError(f"{altered.name}: expected a verifier rejection, got {run.returncode} {lines[-3:]}")


def table(work, name, extended):
    spec = spec_from_file_location("upstream_cases", CASES / "try_altered_copies.py")
    cases = module_from_spec(spec)
    spec.loader.exec_module(cases)
    cases.EXAMPLE = EXAMPLES / name
    data = CASES / ("every_kind_of_item.tsv" if extended else cases.TABLES[name])
    rows = list(cases.cases(BUILD / "cp_verify", data))
    expected = 79 if extended else 10
    if len(rows) != expected:
        raise ValueError(f"expected {expected} cases from {data}")
    oracle([sys.executable, "-I", "-B", cases.__file__, BUILD / "cp_verify", work, data, "--example", name],
           f"{expected} altered sets: all rejected")
    for index, (_, _, identity, _) in enumerate(rows, 1):
        reject(cases.EXAMPLE, work / f"{index:02d}", identity, cases.stated_policy()[0])
    print(f"{name}, {data.name}: both verifiers rejected {expected} cases", flush=True)


def records(work):
    example = EXAMPLES / "accepted-proof"
    runner = EXAMPLES.parent / "verifier/tests/record_altered_sets_test.py"
    identity = (example / "ID.txt").read_text().strip()
    oracle([sys.executable, "-I", "-B", runner, BUILD / "cp_verify",
            *(example / path for path in ("config", "ivk", "example.req", "example.y", "example.proof")),
            identity, work], f"{runner.name}: 7 calls on the honest set and its unaltered copy, 23 altered sets: all as expected")
    samples = sorted(p for p in work.iterdir() if p.is_dir() and p.name.startswith(("whole.", "key.", "leaf.")))
    if len(samples) != 23:
        raise ValueError(f"expected 23 altered record directories, found {len(samples)}")
    for sample in samples:
        reject(example, sample, identity, [], "altered.proof")
    # Substitute an intact but different committed leaf at the caller-selected index.
    cross = work / "cross"
    (cross / "ivk/leaf").mkdir(parents=True)
    (cross / "ivk/key.bin").symlink_to(example / "ivk/key.bin")
    (cross / "ivk/leaf/0.bin").symlink_to(EXAMPLES / "accepted-proof-clipped-gap/ivk/leaf/0.bin")
    reject(example, cross, identity, [])
    print("Standalone rejected all 23 altered record sets and a leaf from another commitment", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extended", action="store_true")
    parser.add_argument("--records-only", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(dir=BUILD) as tmp:
        root = Path(tmp)
        if args.extended or args.records_only:
            records(root / "records")
        if not args.records_only:
            for name in ("accepted-proof", "accepted-proof-clipped-gap"):
                table(root / name, name, False)
            if args.extended:
                table(root / "items", "accepted-proof", True)
