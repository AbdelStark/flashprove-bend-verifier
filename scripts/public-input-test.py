#!/usr/bin/env python3
"""Differentially check the Bend public statement and rejection boundaries against pinned H821."""
from pathlib import Path
import hashlib
import struct
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / ".upstream/FlashProve"
sys.dont_write_bytecode = True
sys.path.insert(0, str(UPSTREAM / "docs/format"))
import format_rules


def check_call(args, code, expected):
    result = subprocess.run(args, capture_output=True, text=True, timeout=90)
    actual = (result.stdout + result.stderr).strip()
    if result.returncode != code or actual != expected:
        raise RuntimeError(f"exit {result.returncode} for {args}\n{actual[:2000]}\nexpected {expected[:2000]}")


def main():
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    with TemporaryDirectory(dir=build) as temp:
        work = Path(temp)
        driver = work / "public-statement"
        layout = work / "public-layout"
        tables = work / "tables"
        plans = build / "plans"
        subprocess.run([sys.executable, ROOT / "scripts/plan-profiles.py", "install"], check=True)
        subprocess.run([ROOT / ".toolchain/bend/bin/bend", ROOT / "scripts/probes/public_layout.bend",
                        "-o", layout], check=True)
        subprocess.run([ROOT / ".toolchain/bend/bin/bend", ROOT / "scripts/probes/public_statement.bend",
                        "-o", driver], check=True)
        subprocess.run([sys.executable, ROOT / "scripts/generate-tables.py", "--output", tables], check=True)
        for name in ("accepted-proof", "accepted-proof-clipped-gap", "full-size", "full-size-clipped-gap"):
            example = UPSTREAM / "examples" / name
            config = example / "config"
            req = example / "example.req"
            expected = format_rules.statement_words((config / "policy.txt").read_bytes(),
                                                     (config / "KL.bin").read_bytes(), req.read_bytes())
            args = [driver, config, req, example / "example.y", tables]
            if "clipped-gap" in name:
                claim = re.search(r" -policy (clipped-gap,[0-9,]+)", (example / "README.md").read_text())[1]
                check_call(args, 1, "NO: policy")
                args.append(claim)
            check_call(args, 0, expected.hex())
            config_bytes = struct.pack("<QQQ",169,2,3)
            for filename in ("policy.txt","layout.txt","KL.bin"):
                raw = (config / filename).read_bytes()
                config_bytes += struct.pack("<Q",len(raw)) + raw
            config_digest = hashlib.blake2b(config_bytes,digest_size=32).hexdigest()
            check_call([layout, *args[1:5], plans, *args[5:]], 0, config_digest)
            print(f"{name}: 177/177 words, four LUTs, layout and message shapes match")

        example = UPSTREAM / "examples/accepted-proof"
        config = work / "config"
        shutil.copytree(example / "config", config)
        call = [driver, config, example / "example.req", example / "example.y", tables]
        policy = config / "policy.txt"
        original = policy.read_bytes()
        for old, new, reason in (
            (b"work field 0 0 0", b"work field 0 33 0", "NO: policy-work-most"),
            (b"group link 1 18 17 17 13", b"group link 1 18 18 17 13", "NO: parameter-group-shape"),
            (b"stages link 4 3 ", b"stages link 4 5 ", "NO: parameter-stages-shape"),
            (b"eps1_lo 1", b"eps1_lo 01", "NO: policy-line-form"),
            (b"eps1_lo 1", b"eps1_hi 1", "NO: policy-name-eps1_lo"),
            (b"rcl 1", b"gcl 1\nrcl 1", "NO: policy-name-tsilu0"),
            (b"callH R16a", b"callA R16a!", "NO: policy-call-line"),
            (b"tsig0 1965976300", b"tsig0 1965976301", "NO: table-digest-sigmoid"),
        ):
            if original.count(old) != 1:
                raise RuntimeError(f"missing source line {old!r}")
            policy.write_bytes(original.replace(old, new))
            check_call(call, 1, reason)
        policy.write_bytes(original[:-1])
        check_call(call, 1, "NO: parameter-line-missing")
        policy.write_bytes(original)
        scales = config / "KL.bin"
        raw = scales.read_bytes()
        for index, value, reason in ((0,0,"NO: KL-shift-range"), (7,0,"NO: KL-norm"), (12,2,"NO: KL-rp"),
                                     (11,3,"NO: af-policy-sh")):
            offset = index * 4
            scales.write_bytes(raw[:offset] + value.to_bytes(4,"little") + raw[offset+4:])
            check_call(call, 1, reason)
        scales.write_bytes(raw + b"\0")
        check_call(call, 1, "NO: KL-length")
        scales.write_bytes(raw)
        for filename, reason in (("silu-8-4095.bin","silu"), ("sigmoid-1.bin","sigmoid"),
                                 ("rotary-6-128-12-10000.bin","rotary"), ("softmax-12-8.bin","softmax")):
            table = tables / filename
            contents = table.read_bytes()
            table.write_bytes(bytes([contents[0] ^ 1]) + contents[1:])
            check_call(call, 1, "NO: table-digest-" + reason)
            table.write_bytes(contents)
        # All modified layouts are compared against the original configuration's
        # digest-authenticated plan. Mutating that plan is separately covered by plan-test.
        layout_path = config / "layout.txt"
        layout_bytes = layout_path.read_bytes()
        original_config = example / "config"
        candidate = [layout, "--candidate", original_config, example / "example.req",
                     example / "example.y", tables, plans, config]
        first = b"1 1 1 5 0 11 0 10 r 0 0 5 16 0"
        second = b"1 1 1 5 0 11 1024 9 r 0 65536 5 15 0"
        cases = (
            (b"1 1 1 N 61 0", b"1 1 2 N 61 0", "NO: layout-group-order"),
            (b"1 1 1 N 61 0", b"1 1 1 N 60 0", "NO: layout-placement"),
            (b"1 1 2 B 3 1", b"1 1 2 N 3 0", "NO: layout-placement"),
            (b"1 2 1 W 2 0", b"1 2 1 N 2 0", "NO: layout-placement"),
            (first, first.replace(b"0 11", b"1 11"), "NO: layout-alignment"),
            (first, first.replace(b"5 16 0", b"4 16 0"), "NO: layout-block-size"),
            (second, second.replace(b"0 65536 5 15",b"0 0 5 15"), "NO: layout-overlap"),
            (first+b"\n", b"", "NO: layout-array-cover"),
            (first, first.replace(b" r ",b" c "), "NO: layout-plan-mismatch"),
            (first+b"\n"+second,second+b"\n"+first, "NO: layout-plan-mismatch"),
            (b"1 1 1 N 61 0", b"1 1 1 N 62 0", "NO: layout-shape-mismatch"),
        )
        for before, after, reason in cases:
            if layout_bytes.count(before) != 1:
                raise RuntimeError(f"ambiguous layout source {before!r}")
            layout_path.write_bytes(layout_bytes.replace(before,after))
            check_call(candidate, 1, reason)
        print("Rejected altered frame, policy, scales, table data, layout geometry and plan encodings.")


if __name__ == "__main__":
    main()
