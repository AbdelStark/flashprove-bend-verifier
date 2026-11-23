#!/usr/bin/env python3
"""Reproduce the known-answer projections of H821 model lookup obligations."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
UP = ROOT / ".upstream/FlashProve"
VECTORS = ROOT / "tests/data/segment-forests.tsv"
NAMES = ("accepted-proof", "accepted-proof-clipped-gap", "full-size", "full-size-clipped-gap")


def project(text):
    output = []
    for digest in re.findall(r"^projected-forest ([0-9a-f]{48})$", text, re.M):
        output.append(b"".join(int(digest[k:k+16],16).to_bytes(8,"little") for k in (0,16,32)).hex())
    return output


def command(binary, name):
    folder = UP / "examples" / name
    readme = (folder / "README.md").read_text()
    args = [binary, folder / "config", folder / "ivk", folder / "example.req", folder / "example.y",
            folder / "example.proof", "-id", re.search(r"\bid=([a-f0-9]{64})\b",readme)[1], "-q", "-j", "1"]
    policy = re.search(r" -policy (clipped-gap,[0-9,]+)",readme)
    return args + (["-policy",policy[1]] if policy else [])


def compile_oracle(tmp):
    rev = re.search(r"^FLASHPROVE_COMMIT=([a-f0-9]{40})$", (ROOT / "upstream.lock").read_text(), re.M)[1]
    source = tmp / "source.tar"
    subprocess.run(["git","-C",UP,"archive","-o",source,rev,"verifier/src","blocks",
                    "prover/attn/plan_rounds.h","prover/head/plan_rounds.h",
                    "prover/prover/plan_rounds.h","prover/hiding/token_plan.h"], check=True)
    subprocess.run(["tar","-xf",source,"-C",tmp], check=True)
    path = tmp / "verifier/src/vf_lookup_argument.h"
    code = path.read_text()
    anchor = "    h.leavesA = h.alpha - eO() - row;\n  }\n"
    if code.count(anchor) != 1:
        raise ValueError("lookup projection hook moved")
    path.write_text(code.replace(anchor,anchor+(ROOT / "scripts/probes/project-forest.inc").read_text()))
    exe = tmp / "projected-oracle"
    subprocess.run(["clang++","-O2","-std=c++17","-pthread","-Iverifier/src","-Iblocks","-Iprover",
                    "-DBLK_FIELD=2","-DDIGEST_WORDS=8","-DSERVING_BUILD=1","-DBLK_COUNT_HASH_CALLS=1",
                    '-DVF_SOURCE_DIGEST="'+"0"*64+'"',"verifier/src/cp_verify.cpp","-o",exe],cwd=tmp,check=True)
    return exe


def lines(records):
    return "".join(name+"\t"+s+"\n" for name, values in records for s in values)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write",action="store_true",help="replace the checked-in vectors")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as tmp:
        oracle = compile_oracle(Path(tmp))
        output = []
        for name in NAMES:
            run = subprocess.run(command(oracle,name),capture_output=True,text=True,check=True,timeout=600)
            gold = project(run.stdout)
            policy = (UP / "examples" / name / "config/policy.txt").read_text()
            layers = int(re.search(r"^L (\d+)$",policy,re.M)[1])
            group_log = int(re.search(r"^ll (\d+)$",policy,re.M)[1])
            if len(gold) != 2 * (2 * (layers >> group_log) + 1):
                raise ValueError(f"{name}: incomplete projections")
            output.append((name,gold))
            print(f"{name}: reproduced {len(gold)} projections",flush=True)
    content = lines(output)
    if args.write:
        VECTORS.write_text(content)
    elif VECTORS.read_text() != content:
        raise SystemExit("forest projections differ")
