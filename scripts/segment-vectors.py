#!/usr/bin/env python3
"""Reproduce the known-answer projections of H821 model lookup and attention obligations."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

from e2e import inputs, stated_policy

ROOT = Path(__file__).resolve().parents[1]
UP = ROOT / ".upstream/FlashProve"
VECTORS = ROOT / "tests/data/segment-forests.tsv"
NAMES = ("accepted-proof", "accepted-proof-clipped-gap", "full-size", "full-size-clipped-gap")


def little_hex(field):
    return b"".join(int(field[k:k+16],16).to_bytes(8,"little") for k in (0,16,32)).hex()


def attention(text):
    matches = re.findall(r"^attention-project (\d+) ([0-9a-f]{48}) ([0-9a-f]{48})$", text, re.M)
    return [f"{slots} {little_hex(rows)} {little_hex(functions)}" for slots, rows, functions in matches]


def project(text):
    output = []
    for digest in re.findall(r"^projected-forest ([0-9a-f]{48})$", text, re.M):
        output.append(little_hex(digest))
    return output


def command(binary, name):
    folder = UP / "examples" / name
    readme = (folder / "README.md").read_text()
    return [binary, *inputs(folder), "-id", re.search(r"\bid=([a-f0-9]{64})\b",readme)[1], "-q", "-j", "1",
            *stated_policy(folder)]


def instrument(path, anchor, replacement):
    code = path.read_text()
    if code.count(anchor) != 1:
        raise ValueError(f"{path.name}: projection hook moved")
    path.write_text(code.replace(anchor, replacement))


def attention_hooks(source):
    engine = source / "vf_subproof_engine.h"
    stage = source / "vf_attention_check.h"
    probe = ROOT / "scripts/probes"
    instrument(engine,"  string G_;", "  string G_;\n  bool projectAttention = false; Ex projectedAttentionRows = eZ();")
    anchor = "  void lin(const Aff &f) {"
    instrument(engine,anchor,anchor+"\n"+(probe / "project-attention-row.inc").read_text())
    anchor = "    seam.transcript(F, tr, slot);"
    instrument(stage,anchor,"    unsigned attentionOwnSlots = slot;\n"+anchor)
    anchor = "      forestObjects(F, g1);"
    instrument(stage,anchor,"      F.projectAttention = true;\n"+anchor)
    anchor = '      lap("walk WA1-WA8");'
    instrument(stage,anchor,(probe / "project-attention-tables.inc").read_text()+"\n"+anchor)


def head_norm(text):
    matches = re.findall(r"^head-norm ([0-9a-f]{48}) ([0-9a-f]{48}) ([0-9a-f]{48})$", text, re.M)
    return [" ".join(little_hex(field) for field in row) for row in matches]


def compile_oracle(tmp, with_attention=False, with_head_norm=False, with_model_batch=False, extra_hooks=None):
    rev = re.search(r"^FLASHPROVE_COMMIT=([a-f0-9]{40})$", (ROOT / "upstream.lock").read_text(), re.M)[1]
    source = tmp / "source.tar"
    subprocess.run(["git","-C",UP,"archive","-o",source,rev,"verifier/src","blocks",
                    "prover/attn/plan_rounds.h","prover/head/plan_rounds.h",
                    "prover/prover/plan_rounds.h","prover/hiding/token_plan.h"], check=True)
    subprocess.run(["tar","-xf",source,"-C",tmp], check=True)
    path = tmp / "verifier/src/vf_lookup_argument.h"
    anchor = "    h.leavesA = h.alpha - eO() - row;\n  }\n"
    instrument(path,anchor,anchor+(ROOT / "scripts/probes/project-forest.inc").read_text())
    if extra_hooks:
        extra_hooks(path.parent)
    if with_attention:
        attention_hooks(path.parent)
    if with_head_norm:
        anchor = "  void lin(const Aff &f) {"
        instrument(path.parent / "vf_subproof_engine.h", anchor, anchor + "\n" +
                   (ROOT / "scripts/probes/project-head-norm.inc").read_text())
    if with_model_batch:
        anchor = "    row.target = eq.target;"
        instrument(tmp / "blocks/iop/req_rows.h", anchor, anchor + "\n" +
                   (ROOT / "scripts/probes/project-model-batch.inc").read_text())
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
    choice = parser.add_mutually_exclusive_group()
    choice.add_argument("--head-norm", action="store_true", help="project the output head norm and logits equations")
    choice.add_argument("--model-batch", action="store_true", help="project every final G/A/H equation after layout")
    choice.add_argument("--attention", action="store_true", help="project R11.3 equations and U3 functions")
    args = parser.parse_args()
    vectors = ROOT / "tests/data/segment-attention.tsv" if args.attention else VECTORS
    if args.model_batch:
        vectors = ROOT / "tests/data/segment-batches.tsv"
    if args.head_norm:
        vectors = ROOT / "tests/data/head-norm.tsv"
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as tmp:
        oracle = compile_oracle(Path(tmp),args.attention,args.head_norm,args.model_batch)
        output = []
        for name in NAMES:
            run = subprocess.run(command(oracle,name),capture_output=True,text=True,check=True,timeout=600)
            gold = head_norm(run.stdout) if args.head_norm else attention(run.stdout) if args.attention else project(run.stdout)
            if args.model_batch:
                m = re.findall(r"^model-batch ([0-9a-f]{48}) ([0-9a-f]{48}) ([0-9a-f]{48})$", run.stdout, re.M)
                gold = [" ".join(map(little_hex,row)) for row in m]
            policy = (UP / "examples" / name / "config/policy.txt").read_text()
            layers = int(re.search(r"^L (\d+)$",policy,re.M)[1])
            group_log = int(re.search(r"^ll (\d+)$",policy,re.M)[1])
            groups = layers >> group_log
            if len(gold) != (2*groups+1 if args.model_batch else 31 if args.head_norm else groups if args.attention else 2 * (2 * groups + 1)):
                raise ValueError(f"{name}: incomplete projections")
            output.append((name,gold))
            print(f"{name}: reproduced {len(gold)} projections",flush=True)
    content = lines(output)
    if args.write:
        vectors.write_text(content)
    elif vectors.read_text() != content:
        raise SystemExit(f"{vectors.name} projections differ")
