#!/usr/bin/env python3
"""Exercise the public Bend CLI against pinned inputs and caller-selected claims."""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
from e2e import build_digests, honest

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / ".upstream" / "FlashProve" / "examples"


def call(argv, expected_code, expected_text):
    run = subprocess.run(argv, capture_output=True, text=True, timeout=600)
    output = (run.stdout + run.stderr).rstrip()
    if run.returncode != expected_code or not output.endswith(expected_text):
        raise RuntimeError(f"{argv[0]} exited {run.returncode}\n{output[-2000:]}")
    return run.stdout


def example_args(binary, example):
    # The checked-in fixture expectations stand in for the caller's trusted inputs.
    model_id = (example / "ID.txt").read_text().strip()
    args = [binary, example / "config", example / "ivk", example / "example.req",
            example / "example.y", example / "example.proof", "-id", model_id]
    policy = re.search(r" -policy (clipped-gap,[0-9,]+)", (example / "README.md").read_text())
    if policy:
        args.extend(["-policy", policy[1]])
    return args


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full-size", action="store_true")
    options = parser.parse_args()
    fixtures = ["accepted-proof", "accepted-proof-clipped-gap"]
    if options.full_size:
        fixtures = ["full-size-clipped-gap", "full-size", *fixtures]
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        # Resolution uses the installed binary, even when called via this symlink.
        verify = work / "verifier with spaces"
        verify.symlink_to(ROOT / "build" / "verify")
        worker_digest = build_digests(False)["bend_verify"]
        for name in fixtures:
            honest(verify, EXAMPLES / name, worker_digest)
        clipped = example_args(verify, EXAMPLES / "accepted-proof-clipped-gap")
        call(clipped[:-2], 1, "NO: policy")
        call(clipped[:-1] + ["clipped-gap,9244130,323343,0,16,8"], 1, "NO: policy")
        args = example_args(verify, EXAMPLES / "accepted-proof")
        call([*args[:6], "-q", "-j", "1", "-id", "0" * 64], 1, "NO: model-statement")
        config = work / "invalid config"
        config.mkdir()
        original = (args[1] / "policy.txt").read_text()
        for old, new, rejection in [
            ("lt 6", "lt 3", "NO: shape-words"),
            ("lt 6", "lt 17", "NO: shape-words"),
            ("V 512", "V 1", "NO: shape-V"),
            ("V 512", "V 16777217", "NO: shape-V"),
            ("table 8 23", "table 21 23", "NO: parameter-table-shape"),
            ("524288 65535 0 11", "8388607 1 0 11", "NO: parameter-table-shape"),
            ("65535 0 11", "65535 1 11", "NO: parameter-table-shape"),
            ("65535 0 11", "65535 0 7", "NO: parameter-table-shape"),
        ]:
            if original.count(old) != 1:
                raise RuntimeError(f"fixture does not contain a unique {old!r}")
            (config / "policy.txt").write_text(original.replace(old, new))
            call([verify, config, *args[2:]], 1, rejection)
        bad_request = work / "truncated request"
        bad_request.write_bytes(args[3].read_bytes()[:-1])
        call([*args[:3], bad_request, *args[4:]], 1, "NO: statement-range")
        proof = work / "proof with trailing data"
        proof.write_bytes(args[5].read_bytes() + b"\0")
        run = subprocess.run([*args[:5], proof, *args[6:]], capture_output=True, text=True, timeout=600)
        if run.returncode != 1 or not run.stdout.splitlines()[-1].startswith("NO:"):
            raise RuntimeError(f"altered proof returned {run.returncode}\n{run.stdout[-1000:]}")
        call([*args[:-2], "+RTS", "--help"], 2, "usage: verify CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-j N] [-q]")
        call(args[:-2], 2, "usage: verify CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-j N] [-q]")
        print("verify rejected wrong ID, malformed shapes, truncated request, altered proof, missing ID and omitted/mismatched clipped-gap policy")


if __name__ == "__main__":
    main()
