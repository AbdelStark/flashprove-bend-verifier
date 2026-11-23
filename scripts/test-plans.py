#!/usr/bin/env python3
"""Check the installed standalone plan inspector against the canonical bytes."""
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "build/inspect-plans"
PROFILES = ROOT / "profiles"
PLANS = ROOT / "build/plans"
EXAMPLES = ROOT / ".upstream/FlashProve/examples"


def check(directory, config, code, last=None):
    proc = subprocess.run([EXE, directory, config], text=True, capture_output=True, timeout=120)
    if proc.returncode != code or (last and (proc.stdout + proc.stderr).splitlines()[-1:] != [last]):
        raise RuntimeError(f"unexpected status {proc.returncode}\n{proc.stdout}\n{proc.stderr}")
    return proc.stdout.splitlines()


def main():
    for archive in sorted(PROFILES.glob("*.zip")):
        expected = []
        with zipfile.ZipFile(archive) as src:
            for info in src.infolist():
                raw = src.read(info)
                header = struct.unpack_from("<Q", raw)[0] + 24
                rounds, = struct.unpack_from("<Q", raw, header + 7*8)
                digest = hashlib.blake2b(struct.pack("<QQ", 169, 1) + raw, digest_size=32).hexdigest()
                expected.append(f"{Path(info.filename).stem} {rounds} {digest}")
        lines = check(PLANS, EXAMPLES / archive.stem / "config", 0)
        if lines != expected:
            raise RuntimeError(f"{archive.name}: {lines} differs from {expected}")
        print(f"{archive.stem}: seven authenticated schedules match")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        name = "accepted-proof"
        dest = root / name
        dest.mkdir()
        config = EXAMPLES / name / "config"
        for file in (PLANS / name).iterdir():
            os.symlink(file, dest / file.name)
        key = dest / "key.one-time.parameters"
        data = key.read_bytes()
        key.unlink()
        # Change a canonical round's work from 0 to 1, preserving size, shape and config hash.
        damaged = bytearray(data)
        schedule = 44 + 8*8
        first_name_len, = struct.unpack_from("<Q", data, schedule)
        work = schedule + 8 + first_name_len + 8
        damaged[work] ^= 1
        key.write_bytes(damaged)
        check(root, config, 1, "NO: plan-digest")
        key.write_bytes(data[:-1])
        check(root, config, 1, "NO: truncated-file")
        key.write_bytes(data + b"x")
        check(root, config, 1, "NO: trailing-data")
        wrong = root / "changed-config"
        wrong.mkdir()
        for file in config.iterdir():
            (wrong / file.name).write_bytes(file.read_bytes() + (b"x" if file.name == "layout.txt" else b""))
        check(root, wrong, 1, "NO: unsupported-configuration")
    print("changed round, truncation, extra byte, and configuration substitution rejected")


if __name__ == "__main__":
    main()
