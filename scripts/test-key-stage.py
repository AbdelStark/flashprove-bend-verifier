#!/usr/bin/env python3
"""Compare Bend key transcripts with the pinned format_rules.py on genuine keys.

The reference walk uses the generated public tree schedule for sizes and tree places.
All bytes, commitments, challenges, nonces, binding links and expected seals are decoded
again with the upstream format equations. The Bend stage checks the key equations. Two
in-memory claim changes keep genuine Fiat-Shamir transcripts and openings intact.
"""
import argparse
from io import BytesIO
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
UP = ROOT / ".upstream/FlashProve"
sys.dont_write_bytecode = True
if not __debug__:
    raise SystemExit("run without -O: these checks use assert")
sys.path.insert(0, str(UP / "docs/format"))
import format_rules as ref

STEMS = ["key.one-time", "key.shared", "key.second"]
LABELS = [0x46524D02, 0x4C494E01, 0x4C494E02]
NAMES = ({n: 1 for n in ["LKP", "JOIN", "LINE", "ZERO", "BAT", "BAT-sigma", "PSC round", "PSC Y",
                          "FOLD round", "BASE lambda", "LIN point", "LIN zeta"]} |
         {"PSC epsilon": 2, "FOLD epsilon": 2, "SEND seed": 3, "LOC": 4, "CS": 4, "BASE": 4,
          "SEAL": 6, "SEND answer": 7, "SPLIT": 7, "PSC values": 7})


def geometry(full):
    size = "full" if full else "small"
    body = (ROOT / "src/key_stage_geometry.bend").read_text().split(f"def {size}(")[1].split("    case _:")[0]
    rows = []
    for chunk in body.split("    case P.")[1:]:
        group = []
        for line in chunk.splitlines():
            shapes = re.findall(r"Tree\{(Table\{\}|Local\{\d+n\}),(\d+)n,(\d+)n,(\d+)n\}", line)
            if shapes:
                group.append([(None if p == "Table{}" else int(p[6:-2]), int(d), int(w), int(s))
                              for p, d, w, s in shapes])
        rows.append(group)
    return rows


def u64(stream):
    return struct.unpack("<Q", stream.read(8))[0]


def string(stream):
    return stream.read(u64(stream))


def decode(blob):
    f = BytesIO(blob)
    assert string(f) == b"the format's version" and string(f) == b"H821" + bytes(4)
    field, fmt, salt, nonce, pos, samples, saved, count = struct.unpack("<8Q", f.read(64))
    assert (field, fmt, salt, nonce) == (2, 1, 40, 8)
    rounds = [(string(f).decode(), *struct.unpack("<11Q", f.read(88))) for _ in range(count)]
    items = {}
    while f.tell() < len(blob):
        name = string(f)
        items[name] = string(f)
    return ref.parameters_digest(blob), rounds, items


def reference(folder, plans):
    key = (folder / "ivk/key.bin").read_bytes()
    wire = BytesIO(key)
    assert wire.read(8) == b"CPIKH821"
    root = wire.read(32)
    conf = ref.configuration_digest([(folder / "config" / f).read_bytes()
                                     for f in ("policy.txt", "layout.txt", "KL.bin")])
    plan = [decode((plans / folder.name / (n + ".parameters")).read_bytes()) for n in STEMS]
    shape = struct.unpack_from("<6Q", plan[0][2][b"the test on the table"])
    count = shape[4] << shape[3]
    table = ref.item("table", ref.string(root) + ref.u64(count) + wire.read(count * 24))
    locations = {}
    records = {}
    schedules = geometry(folder.name.startswith("full-size"))

    def chain(which, st, random, book):
        pd, rounds, items = plan[which]
        assert items[b"configuration"] == conf
        run = ref.run_value(LABELS[which], pd, random)
        transcript = ref.Chain(ref.first_value(LABELS[which], pd, st, run), 2, LABELS[which])
        opens = iter(schedules[which])
        seal = None
        for name, _, work, size, roots, _, _, _, draws, depth, _, _ in rounds:
            if name == "RECORD":
                continue
            msg = wire.read(size)
            for j in range(roots):
                book.append((msg[32*j:32*j+32], len(book), run))
            if work:
                locations.setdefault("nonce", wire.tell())
            nonce = u64(wire) if work else 0
            assert transcript.query(msg, NAMES[name], work, nonce)
            if name == "SEAL":
                seal = transcript.seal_digest()
            if not draws:
                continue
            chosen = [transcript.position(depth) for _ in range(draws)]
            for place, d, width, salt in next(opens):
                digest, number, start = (root, 0, conf) if place is None else book[place]
                xs = sorted({ref.short_position(x, d) for x in chosen})
                leaves = []
                for x in xs:
                    words = list(struct.unpack(f"<{width}Q", wire.read(8 * width)))
                    assert all(w < ref.PRIME[2] for w in words)
                    leaves.append(ref.leaf(174 if place is None else 164, number, d, x, start, words, wire.read(salt)))
                vertices = records.setdefault(digest, {})
                def remember(level, index, value):
                    assert vertices.setdefault((level, index), value) == value
                assert ref.walk(d, conf, xs, leaves, lambda d, i: wire.read(32), remember) == digest
        assert next(opens, None) is None
        return seal, transcript.rho

    a = []
    seal, _ = chain(0, table, wire.read(32), a)
    locations["slot"] = wire.tell()
    assert u64(wire) == 0
    binding = ref.binding_leaf(0, 0, conf, seal, wire.read(40))
    b = []
    shared, _ = chain(1, table + ref.item("the binding tree's root", binding), binding, b)
    statement = b"".join(ref.item("the seal of an earlier chain", s) for s in (seal, shared))
    _, last = chain(2, statement, wire.read(32), a + [b[1]])
    assert wire.tell() == len(key)
    return "key-transcript " + " ".join(x.hex() for x in (seal, shared, last)), locations


def run(exe, plans, folder, key, success, want, *options):
    proc = subprocess.run([exe, *options, plans, folder / "config", key], text=True, capture_output=True, timeout=240)
    out = (proc.stdout + proc.stderr).strip()
    # A refusal must end on its exact reason, so a crash that mentions the reason does not pass.
    if (proc.returncode == 0) != success or (want not in out if success else out.splitlines()[-1:] != ["NO: " + want]):
        raise AssertionError(f"{key}: exit {proc.returncode}, wanted {want!r}, got {out!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", default=ROOT / "build/key-stage", type=Path)
    parser.add_argument("--plans", default=ROOT / "build/plans", type=Path)
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()
    cases = ["accepted-proof", "accepted-proof-clipped-gap"]
    if args.full:
        cases += ["full-size", "full-size-clipped-gap"]
    for case in cases:
        folder = UP / "examples" / case
        expected, loc = reference(folder, args.plans)
        key = folder / "ivk/key.bin"
        run(args.exe, args.plans, folder, key, True, expected)
        print(case, expected, flush=True)
        if case != "accepted-proof":
            continue
        for option, gate in (("--changed-range-target", "key-range-proximity"),
                             ("--changed-dot-weight", "lin-own-proximity")):
            run(args.exe, args.plans, folder, key, False, gate, option)
        print("refused changed range target and changed Dot weight on unchanged key bytes", flush=True)
        original = key.read_bytes()
        changes = {"slot": (loc["slot"], b"\x01", "key-binding-slot"),
                   "nonce": (loc["nonce"], (int.from_bytes(original[loc["nonce"]:loc["nonce"]+8], "little") ^ 1).to_bytes(8, "little"), "chain-round"),
                   "record": (40, bytes([255])*8, "key-record"),
                   "sibling": (len(original)-1, bytes([original[-1] ^ 1]), "opening"),
                   "trailing": (len(original), b"x", "trailing-data")}
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as tmp:
            for name, (start, new, reason) in changes.items():
                changed = Path(tmp) / name
                changed.write_bytes(original[:start] + new + original[start+len(new):])
                run(args.exe, args.plans, folder, changed, False, reason)
        print("refused", ", ".join(changes), flush=True)


if __name__ == "__main__":
    main()
