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


PUBLIC = "stage: public, files: CONFIG, REQUEST, Y, DIR"


def run(binary, directory, args, status, expected, workers=None, parity_dir=None, case=None, stage=None):
    """Compare the output less the stage lines. A refusal's last stage line must be `stage`."""
    env = {"PATH": str(directory / "empty-path")}
    result = run_cli([binary, *args], cwd=directory, env=env, timeout=3600, parity_dir=parity_dir, case=case)
    if workers is not None:
        stderr = result.stderr.splitlines()
        if not stderr or stderr[0] != f"timing: workers {workers}":
            raise RuntimeError(f"expected {workers} runtime workers, got {stderr[:1]}")
        lines = result.stdout.strip().splitlines()
    else:
        lines = (result.stdout + result.stderr).strip().splitlines()
    stages = [line for line in lines if line.startswith("stage: ")]
    lines = [line for line in lines if not line.startswith("stage: ")]
    if result.returncode != status or lines != expected.splitlines():
        raise RuntimeError(f"expected {status} {expected!r}, got {result.returncode} {lines[-4:]!r}")
    if status == 0 and stages and (stages[0] != PUBLIC or stages[-1] != "stage: request, file: PROOF"):
        raise RuntimeError(f"an accepted call must pass every stage, got {stages!r}")
    if stage and (not stages or stages[-1] != stage):
        raise RuntimeError(f"expected the refusal in {stage!r}, got {stages[-1:]!r}")


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
                        parity_dir=args.parity_dir, case="wrong-id", stage="stage: key, file: IVK/key.bin")
                    run(binary, work, [*call, "+RTS", "--help"], 2,
                        "usage: verify-bend CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-data DIR] [-q] [-j WORKERS] [-timing]",
                        parity_dir=args.parity_dir, case="reserved-argument")
            print(f"{name}: verified independently, {expected.splitlines()[-1]}", flush=True)
        refusals(binary, work)


def refusals(binary, work):
    """Caller inputs the verifier must refuse, each with a `NO:` line naming the check."""
    clipped = EXAMPLES / "accepted-proof-clipped-gap"
    call = [*inputs(clipped), "-id", (clipped / "ID.txt").read_text().strip(), "-data", "data"]
    run(binary, work, call, 1, "NO: policy", stage=PUBLIC)
    run(binary, work, [*call, "-policy", "clipped-gap,9244130,323343,0,16,8"], 1, "NO: policy", stage=PUBLIC)
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
        run(binary, work, [changed, ivk, req, y, proof, *tail], 1, rejection, stage=PUBLIC)
    short = work / "truncated request"
    short.write_bytes(req.read_bytes()[:-1])
    run(binary, work, [config, ivk, short, y, proof, *tail], 1, "NO: statement-range", stage=PUBLIC)
    # A table missing its trailing zero bytes packs to the same words and digest: only its length refuses it.
    trimmed = work / "trimmed"
    shutil.copytree(work / "data", trimmed, symlinks=True)
    table = trimmed / "tables/softmax-12-8.bin"
    data = table.read_bytes()
    if data[-3:] != b"\0\0\0":
        raise RuntimeError(f"{table.name} no longer ends in three zero bytes")
    table.write_bytes(data[:-3])
    run(binary, work, [config, ivk, req, y, proof, *tail[:-1], trimmed], 1, "NO: public-table-length", stage=PUBLIC)
    print("refused omitted and mismatched policy, malformed shapes, a truncated request and a trimmed table",
          flush=True)


if __name__ == "__main__":
    main()
