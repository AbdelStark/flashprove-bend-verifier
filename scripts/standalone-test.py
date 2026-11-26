#!/usr/bin/env python3
"""Run the freestanding native binary with only public parameters and caller inputs."""
import argparse
from pathlib import Path
import re
import shutil
import tempfile

from e2e import stated_policy
from worker_parity import run_cli

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / ".upstream/FlashProve/examples"


def run(binary, directory, args, status, expected, workers=None, parity_dir=None, case=None):
    env = {"PATH": str(directory / "empty-path"), "BEND_THREADS": "1"}
    result = run_cli([binary, *args], cwd=directory, env=env, timeout=3600, parity_dir=parity_dir, case=case)
    if workers is not None:
        stderr = result.stderr.splitlines()
        if not stderr or stderr[0] != f"timing: workers {workers}":
            raise RuntimeError(f"expected {workers} runtime workers, got {stderr[:1]}")
        lines = result.stdout.strip().splitlines()
    else:
        lines = (result.stdout + result.stderr).strip().splitlines()
    if result.returncode != status or lines != expected.splitlines():
        raise RuntimeError(f"expected {status} {expected!r}, got {result.returncode} {lines[-4:]!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full-size", action="store_true")
    parser.add_argument("--parity-dir", type=Path, help="save and compare calls with 1 and 16 workers")
    args = parser.parse_args()
    fixtures = ["accepted-proof", "accepted-proof-clipped-gap"]
    if args.full_size:
        fixtures += ["full-size", "full-size-clipped-gap"]
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as tmp:
        work = Path(tmp)
        binary = Path(shutil.copy2(ROOT / "build/verify-bend", work))
        digest = (ROOT / "build/verify-bend.digest").read_text().strip()
        for name in ("plans", "tables"):
            shutil.copytree(ROOT / "build" / name, work / "data" / name)
        for name in fixtures:
            case = EXAMPLES / name
            expected_id = (case / "ID.txt").read_text().strip()
            with tempfile.TemporaryDirectory(dir=work) as inputs:
                files = Path(inputs)
                shutil.copytree(case / "config", files / "configuration")
                shutil.copytree(case / "ivk", files / "verification-key")
                for original, dest in (("example.req","tokens"), ("example.y","next"), ("example.proof","payload")):
                    shutil.copyfile(case / original, files / dest)
                call = [files / p for p in ("configuration", "verification-key", "tokens", "next", "payload")]
                options = ["-data", "data", *stated_policy(case)]
                expected = re.search(r"^commitment: [^\n]+\nproof of work: [^\n]+\nresult-v1 [^\n]+\n[^\n]+",
                                     (case / "README.md").read_text(), re.M)[0]
                expected = expected.replace("<64 hex digits>", digest)
                run(binary, work, [*call, "-id", expected_id, *options], 0, expected,
                    parity_dir=args.parity_dir, case=name)
                if name == fixtures[0]:
                    counts = (1, 2, 4, 8, 16) if args.parity_dir else (1, 4)
                    for workers in counts:
                        run(binary, work, [*call, *options, "-id", expected_id, "-j", str(workers),
                                           "-timing"], 0, expected, workers)
                    run(binary, work, [*call, *options, "-j", "--help"], 2,
                        "verify-bend: -j expects a worker count from 1 to 128")
                    run(binary, work, [*call, "-id", "0" * 64, *options], 1, "NO: model-statement",
                        parity_dir=args.parity_dir, case="wrong-id")
                    run(binary, work, [*call, "+RTS", "--help"], 2,
                        "usage: verify-bend CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-data DIR] [-q] [-j WORKERS] [-timing]",
                        parity_dir=args.parity_dir, case="reserved-argument")
            print(f"{name}: verified independently, {expected.splitlines()[-1]}", flush=True)


if __name__ == "__main__":
    main()
