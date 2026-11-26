#!/usr/bin/env python3
"""Run the freestanding native binary with only public parameters and caller inputs."""
import argparse
from pathlib import Path
import re
import shutil
import tempfile

from fixtures import inputs, stated_policy
from worker_parity import run_cli

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / ".upstream/FlashProve/examples"


def run(binary, directory, args, status, expected, workers=None, parity_dir=None, case=None):
    env = {"PATH": str(directory / "empty-path")}
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
        refusals(binary, work)


def refusals(binary, work):
    """Caller inputs the verifier must refuse, each with a `NO:` line naming the check."""
    clipped = EXAMPLES / "accepted-proof-clipped-gap"
    call = [*inputs(clipped), "-id", (clipped / "ID.txt").read_text().strip(), "-data", "data"]
    run(binary, work, call, 1, "NO: policy")
    run(binary, work, [*call, "-policy", "clipped-gap,9244130,323343,0,16,8"], 1, "NO: policy")
    exact = EXAMPLES / "accepted-proof"
    config, ivk, req, y, proof = inputs(exact)
    tail = ["-id", (exact / "ID.txt").read_text().strip(), "-data", "data"]
    changed = work / "changed config"
    shutil.copytree(config, changed)
    original = (config / "policy.txt").read_text()
    for old, new, rejection in [
        ("lt 6", "lt 3", "NO: unsupported public table geometry"),
        ("lt 6", "lt 17", "NO: unsupported public table geometry"),
        ("V 512", "V 1", "NO: shape-V"),
        ("V 512", "V 16777217", "NO: shape-V"),
        ("table 8 23", "table 21 23", "NO: parameter-table-shape"),
        ("524288 65535 0 11", "8388607 1 0 11", "NO: parameter-table-shape"),
        ("65535 0 11", "65535 1 11", "NO: parameter-table-shape"),
        ("65535 0 11", "65535 0 7", "NO: parameter-table-shape"),
    ]:
        if original.count(old) != 1:
            raise RuntimeError(f"fixture does not contain a unique {old!r}")
        (changed / "policy.txt").write_text(original.replace(old, new))
        run(binary, work, [changed, ivk, req, y, proof, *tail], 1, rejection)
    short = work / "truncated request"
    short.write_bytes(req.read_bytes()[:-1])
    run(binary, work, [config, ivk, short, y, proof, *tail], 1, "NO: statement-range")
    print("refused omitted and mismatched policy, malformed shapes and a truncated request", flush=True)


if __name__ == "__main__":
    main()
