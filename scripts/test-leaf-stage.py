#!/usr/bin/env python3
"""Compare the leaf LINK result and final transcript with the pinned H821 walker."""
import argparse
import contextlib
import io
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
UP = ROOT / ".upstream/FlashProve"
sys.dont_write_bytecode = True
sys.path.insert(0, str(UP / "docs/format"))
import format_rules as ref


def reference(example, params, leaf, directory):
    # The shipped standalone read_entry assumes two config files. The inference
    # interface hashes policy, layout and KL. All subsequent upstream checks run unchanged.
    for src, dest in ((example/"config/policy.txt", "public-file-1.txt"),
                      (example/"config/layout.txt", "public-file-2.txt"),
                      (example/"ivk/key.bin", "key.file"), (leaf, "entry.file"),
                      (params, "entry.parameters")):
        (directory/dest).symlink_to(src)
    extra = (example/"config/KL.bin").read_bytes()
    digest = ref.configuration_digest
    walker = UP / "docs/format/read_entry.py"
    with patch.object(ref, "configuration_digest", lambda inputs: digest([*inputs, extra])), \
         patch.object(sys, "argv", [str(walker), str(directory)]), contextlib.redirect_stdout(io.StringIO()):
        end = runpy.run_path(str(walker), run_name="__main__")
    return end["c"].rho.hex()


def run(args, code, expected):
    result = subprocess.run(args, capture_output=True, text=True, timeout=240)
    observed = (result.stdout + result.stderr).strip()
    if result.returncode != code or observed != expected:
        raise RuntimeError(f"unexpected exit {result.returncode}: {observed}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full-size", action="store_true")
    args = parser.parse_args()
    plans = ROOT/"build/plans"
    exe = ROOT/"build/leaf-checked"
    fixtures = ["accepted-proof", "accepted-proof-clipped-gap"]
    if args.full_size:
        fixtures.extend(["full-size", "full-size-clipped-gap"])
    for name in fixtures:
        example = UP/"examples"/name
        with (example/"example.proof").open("rb") as proof:
            header = proof.read(12)
        if len(header) != 12 or header[:8] != b"CPPFH821":
            raise ValueError("unexpected proof header")
        leaf = example/"ivk/leaf"/f"{int.from_bytes(header[8:], 'little')}.bin"
        inputs = [plans, example/"config", example/"ivk/key.bin"]
        with tempfile.TemporaryDirectory(dir=ROOT/"build") as tmp:
            directory = Path(tmp)
            rho = reference(example, plans/name/"entry.parameters", leaf, directory)
            run([exe, *inputs, leaf], 0, "leaf-link "+rho)
            run([exe, "--changed-batch-target", *inputs, leaf], 1, "NO: link-proximity")
            if name == "accepted-proof":
                original = leaf.read_bytes()
                mutations = [(original + b"\0", "NO: trailing-data"),
                             (original[:40] + b"\xff"*8 + original[48:], "NO: leaf-record"),
                             (original[:-1] + bytes([original[-1] ^ 1]), "NO: opening")]
                for raw, expected in mutations:
                    bad = directory/"changed.bin"
                    bad.write_bytes(raw)
                    run([exe, *inputs, bad], 1, expected)
            print(f"{name} leaf LINK equations passed, changed BAT target rejected, rho={rho}", flush=True)


if __name__ == "__main__":
    main()
