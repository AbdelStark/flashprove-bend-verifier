#!/usr/bin/env python3
"""Run the freestanding native binary with only public parameters and caller inputs."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / ".upstream/FlashProve/examples"


def run(binary, directory, args, status, expected):
    env = {"PATH": str(directory / "empty-path"), "BEND_THREADS": "1"}
    result = subprocess.run([binary, *args], cwd=directory, env=env, capture_output=True,
                            text=True, timeout=600)
    lines = (result.stdout + result.stderr).strip().splitlines()
    if result.returncode != status or lines[-1:] != [expected]:
        raise RuntimeError(f"expected {status} {expected!r}, got {result.returncode} {lines[-4:]!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full-size", action="store_true")
    args = parser.parse_args()
    fixtures = ["accepted-proof", "accepted-proof-clipped-gap"]
    if args.full_size:
        fixtures += ["full-size", "full-size-clipped-gap"]
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as tmp:
        work = Path(tmp)
        binary = Path(shutil.copy2(ROOT / "build/verify-bend", work))
        for name in ("plans", "tables"):
            shutil.copytree(ROOT / "build" / name, work / "data" / name)
        for name in fixtures:
            case = EXAMPLES / name
            expected_id = (case / "ID.txt").read_text().strip()
            policy = re.search(r" -policy (clipped-gap,[0-9,]+)", (case / "README.md").read_text())
            call = [case / p for p in ("config", "ivk", "example.req", "example.y", "example.proof")]
            options = ["-data", "data", *(["-policy", policy[1]] if policy else [])]
            run(binary, work, [*call, "-id", expected_id, *options], 3,
                "STAGES CHECKED: request equations incomplete")
            if name == fixtures[0]:
                run(binary, work, [*call, "-id", "0" * 64, *options], 1, "NO: model-statement")
            print(f"{name}: independently checked key, leaf, public statement and request stages", flush=True)


if __name__ == "__main__":
    main()
