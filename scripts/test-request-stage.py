#!/usr/bin/env python3
"""Compare independent Bend request transcripts with the pinned upstream Python walker."""
import argparse
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile
from compile_bend import native

ROOT = Path(__file__).resolve().parents[1]
UP = ROOT / ".upstream/FlashProve"
BUILD = ROOT / "build"
MODEL = runpy.run_path(str(ROOT / "scripts/model-projections.py"))


def run(args, expected=0, diagnostic=None):
    result = subprocess.run(args, capture_output=True, text=True, timeout=600)
    text = (result.stdout + result.stderr).strip()
    if result.returncode != expected or (diagnostic is not None and diagnostic != text):
        raise RuntimeError(f"unexpected exit {result.returncode} from {args[0]}\n{text[-2500:]}")
    return text


def oracle(folder, datasets, example, name, copy):
    """Use read_proof.py unmodified. It independently computes the slot and binding root."""
    batch = folder / "batch"
    batch.mkdir(parents=True)
    for filename in ("policy.txt", "layout.txt", "KL.bin"):
        (folder / filename).symlink_to(example / "config" / filename)
    (folder / "key.file").symlink_to(example / "ivk/key.bin")
    (folder / "entry.file").symlink_to(example / f"ivk/leaf/{copy}.bin")
    (batch / "0.request").symlink_to(example / "example.req")
    (batch / "0.proof").symlink_to(example / "example.proof")
    for src, dest in (("proof.first","0.first"), ("proof.shared","shared"), ("proof.second","second")):
        (batch / (dest+".parameters")).symlink_to(datasets / name / (src+".parameters"))
    output = run([sys.executable, UP / "docs/format/read_proof.py", folder, "batch", "0",
                  "--public=policy.txt,layout.txt,KL.bin", "--table=entry.file", "--statement=policy.txt,KL.bin"])
    root = re.search(r"^slot (\d+) of 2\^\d+; the binding tree's root ([0-9a-f]{64})$", output, re.M)
    if not root or "the whole file is read:" not in output:
        raise ValueError("Python walker did not finish")
    return root.groups(), output


def mutate(tmp, cmd, proof, y, transcript):
    data = proof.read_bytes()
    replacement = tmp / "altered.proof"
    altered = list(cmd)
    altered[2] = replacement
    opened = [int(x) for x in re.findall(r"round \d+ LOC:.*?bytes (\d+) to",transcript)]
    if not opened:
        raise RuntimeError("no authenticated LOC example")
    replacement.write_bytes(data + b"!")
    run(altered, 1, "NO: trailing-data")
    for offset in (opened[0],len(data)-1):
        replacement.write_bytes(data[:offset] + bytes([data[offset] ^ 1]) + data[offset+1:])
        run(altered, 1, "NO: key-opening")
    # The output token has one occurrence in the small real proof as a field
    # element. Change an otherwise canonical upper extension coordinate.
    token = y.read_bytes() + bytes(20)
    if data.count(token) != 1:
        raise RuntimeError("ambiguous REPLY sample")
    at = data.index(token)+8
    replacement.write_bytes(data[:at] + b"\x01" + data[at+1:])
    run(altered, 1, "NO: header-y")
    wrong_y = tmp / "wrong.y"
    wrong_y.write_bytes((int.from_bytes(y.read_bytes(),"little")+1).to_bytes(4,"little"))
    altered = list(cmd)
    altered[4] = wrong_y
    run(altered, 1, "NO: reply-differs")
    print("Rejected altered LOC, BASE, REPLY, caller y and trailing data.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full-size", action="store_true")
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    run([sys.executable,ROOT / "scripts/plan-profiles.py","install"])
    with tempfile.TemporaryDirectory(dir=BUILD) as temp:
        tmp = Path(temp)
        binary = tmp / "request-stage"
        plans = BUILD / "plans"
        tables = tmp / "tables"
        native(ROOT / ".toolchain/bend/bin/bend",ROOT / "scripts/probes/request_stage.bend",binary)
        run([sys.executable,ROOT / "scripts/generate-tables.py","--output",tables])
        names = ["accepted-proof", "accepted-proof-clipped-gap"]
        if args.full_size:
            names.extend(("full-size","full-size-clipped-gap"))
        for name in names:
            example = UP / "examples" / name
            proof = example / "example.proof"
            y = example / "example.y"
            with proof.open("rb") as stream:
                copy = int.from_bytes(stream.read(12)[8:],"little")
            expected, walk = oracle(tmp / name,plans,example,name,copy)
            cmd = [binary,example,proof,example / "example.req",y,tables,plans]
            if name.endswith("-clipped-gap"):
                cmd.append(re.search(r" -policy (clipped-gap,[0-9,]+)", (example / "README.md").read_text())[1])
            output = run(cmd).splitlines()
            projections = [line.removeprefix("forest ") for line in output[:-1] if line.startswith("forest ")]
            attention = [line.removeprefix("attention ") for line in output[:-1] if line.startswith("attention ")]
            known_attention = [row.split("\t")[1] for row in (ROOT / "tests/data/segment-attention.tsv").read_text().splitlines()
                               if row.split("\t")[0] == name]
            if not known_attention or attention != known_attention:
                raise ValueError(f"{name}: R11.3 row or evaluation-table projection mismatch")
            batches = [line.removeprefix("model-batch ") for line in output[:-1] if line.startswith("model-batch ")]
            all_batches = [row.split("\t")[1] for row in (ROOT / "tests/data/segment-batches.tsv").read_text().splitlines()
                           if row.split("\t")[0] == name]
            if batches != all_batches:
                raise ValueError(f"{name}: placed model coefficient, target or mask differs")
            expected_model = dict(line.split() for line in MODEL["VECTORS"].read_text().splitlines())
            if MODEL["comparison"]("\n".join(output), name) != expected_model[name]:
                raise ValueError(f"{name}: layer lookup join or output-head equation differs")
            known = [row.split("\t")[1] for row in (ROOT / "tests/data/segment-forests.tsv").read_text().splitlines()
                     if row.split("\t")[0] == name]
            if not known or projections != known:
                first_bad = next((i for i, pair in enumerate(zip(projections,known)) if pair[0] != pair[1]), len(projections))
                raise ValueError(f"{name}: forest {first_bad} differs: {projections[first_bad:first_bad+1]} vs {known[first_bad:first_bad+1]}")
            slot, root, first, shared, rho = output[-1].split()
            if (slot,root) != expected or not all(re.fullmatch(r"[0-9a-f]{64}",x) for x in (first,shared,rho)):
                raise ValueError(f"{name}: transcript disagrees with the pinned Python walker")
            print(f"{name}: {len(known)} forest and {len(attention)} attention projections, {len(batches)} placed G/A/H batch equations, reached EOF, slot {slot}, binding root {root}",flush=True)
            if name == "accepted-proof":
                mutate(tmp,cmd,proof,y,walk)


if __name__ == "__main__":
    main()
