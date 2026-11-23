#!/usr/bin/env python3
"""Reproduce compact independent comparison vectors for the G and H equations, public tables, and deferred weight claims."""
import argparse
import hashlib
from pathlib import Path
import runpy
import subprocess
import tempfile

BASE = Path(__file__).resolve().parents[1]
REFERENCE = runpy.run_path(str(BASE / "scripts/segment-vectors.py"))
PROBES = BASE / "scripts/probes"
VECTORS = BASE / "tests/data/model-equations.tsv"


def instrument(src):
    patch = REFERENCE["instrument"]
    head = src / "vf_output_head_check.inc"
    engine = src / "vf_subproof_engine.h"
    fields = "  string G_;"
    patch(engine, fields, fields + "\n  bool exposeHead = false, projectAttention = false; Ex projectedAttentionRows=eZ();")
    method = "  void lin(const Aff &f) {"
    report = (PROBES / "project-head-norm.inc").read_text().split("  Ex cells", 1)[1]
    patch(engine, method, method + '\nif (exposeHead) {\n  Ex cells' + report.replace('"head-norm"', '"head-row"'))
    patch(engine, method, method + "\n" + (PROBES / "project-attention-row.inc").read_text())
    layers = src / "vf_layers_check.inc"
    anchor = "  tl.transcript(F, tr, slot);"
    patch(layers, anchor, "  unsigned ffUsed=slot;\n" + anchor)
    anchor = "    forestObjects(F, fo);"
    patch(layers, anchor, "    F.projectAttention=true;\n" + anchor)
    anchor = "    tl.objectsF(F, fun);"
    summary = (PROBES / "project-attention-tables.inc").read_text().replace("attention-project","ff-prefix").replace("attentionOwnSlots","ffUsed")
    patch(layers, anchor, summary + "\n" + anchor + "\n    F.projectedAttentionRows=eZ(); F.projectAttention=true;")
    anchor = "    wsForkLin(F, wo);"
    patch(layers, anchor, anchor + "\n" + (PROBES / "project-ff-carried.inc").read_text())
    for anchor, extra, before in [
        ("  tl.transcript(F, tr, slot);", "  unsigned headUsed=slot;", True),
        ("    forestObjects(F, g1);", "    F.exposeHead=true;", True),
        ("    tl.objectsF(F, fun);", "    F.exposeHead=false;\n@\n    F.exposeHead=true;", True),
        ("    wsForkLin(F, wo);", "    F.exposeHead=false;\n"+(PROBES/"project-head.inc").read_text(), False)
    ]:
        text = extra.replace("@", anchor) if "@" in extra else "\n".join((extra,anchor) if before else (anchor,extra))
        patch(head, anchor, text)
    anchor = "    if (hasT) cstart = cstart - affSlot(tT.sCl);"
    patch(src / "vf_layers_check.inc", anchor, (PROBES / "project-ff-lookup.inc").read_text() + anchor)


def comparison(text, name, oracle=False):
    joins = []
    layers = []
    head = []
    for line in text.splitlines():
        if not line.startswith(("ff-join ", "ff-prefix ", "ff-carried ", "head-row ", "head-functions ")):
            continue
        fields = line.split()
        if oracle:
            line = " ".join(REFERENCE["little_hex"](x) if len(x) == 48 else x for x in fields)
        (joins if fields[0] == "ff-join" else layers if fields[0].startswith("ff-") else head).append(line)
    size = (12,24,123) if name.startswith("full-size") else (2,4,115)
    if (len(joins),len(layers),len(head)) != size:
        raise ValueError(f"{name}: expected {size} layer joins, layer proofs and head records, got {(len(joins),len(layers),len(head))}")
    return hashlib.sha256(("\n".join([*joins,*layers,*head])+"\n").encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    out = []
    with tempfile.TemporaryDirectory() as work:
        binary = REFERENCE["compile_oracle"](Path(work), extra_hooks=instrument)
        for name in REFERENCE["NAMES"]:
            run = subprocess.run(REFERENCE["command"](binary,name), capture_output=True, text=True, check=True)
            out.append(name + "\t" + comparison(run.stdout, name, True))
    content = "\n".join(out) + "\n"
    if args.write:
        VECTORS.write_text(content)
    elif VECTORS.read_text() != content:
        raise ValueError("model projection vectors changed")


if __name__ == "__main__":
    main()
