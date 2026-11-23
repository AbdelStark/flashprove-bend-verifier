#!/usr/bin/env python3
"""Package, reproduce, or extract H821's configuration-only chain parameters."""
import argparse
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UP = ROOT / ".upstream/FlashProve"
ASSETS = ROOT / "profiles"
CATALOG = ROOT / "src/plan_catalog.bend"
REV = dict(line.split("=", 1) for line in (ROOT / "upstream.lock").read_text().splitlines()
           if line.startswith("FLASHPROVE_COMMIT="))["FLASHPROVE_COMMIT"]
PROFILES = {"accepted-proof": "SmallExact", "accepted-proof-clipped-gap": "SmallClipped",
            "full-size": "FullExact", "full-size-clipped-gap": "FullClipped"}
CHAINS = {"key.one-time": "KeyOnce", "key.shared": "KeyShared", "key.second": "KeySecond",
          "entry": "Entry", "proof.first": "RequestFirst", "proof.shared": "RequestShared",
          "proof.second": "RequestSecond"}
VERSION = struct.pack("<Q", 20) + b"the format's version" + struct.pack("<Q", 8) + b"H821\0\0\0\0"


def digest(index, data):
    return hashlib.blake2b(struct.pack("<QQ", 169, index) + data, digest_size=32).hexdigest()


def configuration(folder):
    data = bytearray(struct.pack("<Q", 3))
    for name in ("policy.txt", "layout.txt", "KL.bin"):
        value = (folder / name).read_bytes()
        data += struct.pack("<Q", len(value)) + value
    return digest(2, data)


def inspect(blob, rounds, config):
    """Compare the serialized round schedule to the planner's human-readable export."""
    if not blob.startswith(VERSION):
        raise ValueError("bad parameters version")
    field, fmt, salt, nonce, position, samples, saved, count = struct.unpack_from("<8Q", blob, len(VERSION))
    if (field, fmt, nonce) != (2, 1, 8) or not 40 <= salt <= 64 or not 0 < count <= 100000:
        raise ValueError("unsupported round settings")
    offset = len(VERSION) + 64
    rows = rounds.read_text().splitlines()
    if len(rows) != count:
        raise ValueError(f"round count differs in {rounds}")
    for row in rows:
        length, = struct.unpack_from("<Q", blob, offset)
        offset += 8
        name = blob[offset:offset + length].decode("ascii")
        offset += length
        words = struct.unpack_from("<11Q", blob, offset)
        offset += 88
        fields = row.split("\t")
        if fields[0] != name or words != tuple(map(int, fields[3:14])):
            raise ValueError(f"serialized round disagrees with {row}")
    items = {}
    while offset < len(blob):
        length, = struct.unpack_from("<Q", blob, offset)
        name = blob[offset+8:offset+8+length].decode("ascii")
        offset += 8 + length
        length, = struct.unpack_from("<Q", blob, offset)
        offset += 8
        if name in items or offset + length > len(blob):
            raise ValueError("invalid parameter item")
        items[name] = blob[offset:offset+length]
        offset += length
    if next(iter(items), "") != "configuration" or items["configuration"].hex() != config:
        raise ValueError("wrong configuration inside parameters")
    return len(blob), count, digest(1, blob)


def bend_words(hex_digest):
    return "[" + ", ".join(map(str, struct.unpack("<8I", bytes.fromhex(hex_digest)))) + "]"


def accounting_catalog(exports):
    lines = ['# Configuration-only dyadic error bounds from scripts/plan-profiles.py.',
             'import Base', 'import ./plan_types.bend as P', '',
             'type Bound is Data:', '  Bound{work: Nat, denominator_bits: Nat, numerator: List<&2,U32>}', '',
             'type Stage is Data:',
             '  Stage{target: Nat, rounds: Nat, by_work: Nat, third: Nat, theorem: Nat, errors: List<&2,Bound>}', '']
    display = []
    for name, profile in PROFILES.items():
        stages = {}
        bits = []
        for row in (exports / name / 'accounting.tsv').read_text().splitlines():
            kind, *words = row.split()
            values = list(map(int, words))
            if kind == 'bound':
                work, scale, *limbs = values
                bounds.append(f'Bound{{{work}n,{scale}n,{limbs}}}')
                numerator = sum(x << (32*i) for i, x in enumerate(limbs))
                bare = scale * 100 - (numerator**100 - 1).bit_length()
                bits.append((work, bare, bare + 100*work))
            else:
                bounds = []
                stages[kind] = (values, bounds)
        if list(stages) != ['key', 'leaf', 'request']:
            raise ValueError(f'incomplete stage accounting for {name}')
        def hundredths(value):
            return f'{value // 100}.{value % 100:02}'
        work_bits = max(w for w, _, _ in bits)
        by_work = sum(values[2] for values, _ in stages.values())
        assumed = sum(stages[k][0][4] for k in ('key', 'leaf'))
        with_work = hundredths(min(charged for _, _, charged in bits))
        bare = hundredths(min(unworked for _, unworked, _ in bits))
        display.append(f'    case P.{profile}{{}}: Report{{"{work_bits}","{by_work}","{with_work}","{bare}","{assumed}"}}')
        lines += [f'def {profile.lower()}() -> List<&2,Stage>:', '  [' +
                  ',\n   '.join('Stage{' + ','.join(f'{v}n' for v in values) + ',[' +
                             ','.join(bounds) + ']}' for values, bounds in stages.values()) + ']', '']
    lines += ['def stages(profile: P.Profile) -> List<&2,Stage>:', '  match profile:']
    lines += [f'    case P.{p}{{}}: {p.lower()}()' for p in PROFILES.values()]
    lines += ['', 'type Report is Data:',
              '  Report{work: String, rounds: String, least: String, bare: String, theorem: String}', '',
              'def report(profile: P.Profile) -> Report:', '  match profile:', *display]
    return '\n'.join(lines) + '\n'


def pack(exports, configs, out, check):
    catalog = ["# Generated from pinned, configuration-only H821 plans by scripts/plan-profiles.py.",
               "import Base", "import ./plan_types.bend as P", "",
               "def select(hash: List<&2, U32>) -> Maybe<&2, P.Profile>:", "  match hash:"]
    pins = ["def pin(profile: P.Profile, chain: P.Chain) -> P.Pin:", "  match profile chain:"]
    for fixture, profile in PROFILES.items():
        config = configuration(configs / fixture / "config")
        catalog.append(f'    case {bend_words(config)}: Some{{P.{profile}{{}}}}')
        path = ASSETS / (fixture + ".zip")
        with zipfile.ZipFile(path if check else out / path.name, "r" if check else "w") as archive:
            if check and archive.namelist() != [c + ".parameters" for c in CHAINS]:
                raise ValueError(f"unexpected members in {path}")
            for stem, chain in CHAINS.items():
                member = stem + ".parameters"
                blob = (exports / fixture / member).read_bytes()
                size, count, hashed = inspect(blob, exports / fixture / (stem + ".rounds.tsv"), config)
                if check:
                    if archive.read(member) != blob:
                        raise ValueError(f"{path.name}/{member} differs from pinned configuration export")
                else:
                    info = zipfile.ZipInfo(member, (1980, 1, 1, 0, 0, 0))
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, blob, zipfile.ZIP_DEFLATED, compresslevel=9)
                pins.append(f'    case P.{profile}{{}} P.{chain}{{}}: P.Pin{{{size}, {count}, {bend_words(hashed)}}}')
    source = "\n".join([*catalog, "    case _: None{}", "", *pins, ""])
    if check:
        if source != CATALOG.read_text():
            raise ValueError("plan catalog differs from the pinned source")
    else:
        (out / CATALOG.name).write_text(source)
        for fixture in PROFILES:
            (out / (fixture + ".zip")).replace(ASSETS / (fixture + ".zip"))
        (out / CATALOG.name).replace(CATALOG)


def reproduce(work, check):
    # Archive only committed inputs. This generator never receives an IVK, request or proof.
    paths = ["verifier/src", "blocks", "tools/audit/pubtool.cpp", "prover/attn/plan_rounds.h",
             "prover/head/plan_rounds.h", "prover/prover/plan_rounds.h", "prover/hiding/token_plan.h",
             *("examples/" + f + "/config" for f in PROFILES)]
    source = work / "source.tar"
    subprocess.run(["git", "-C", UP, "archive", "-o", source, REV, *paths], check=True)
    subprocess.run(["tar", "-xf", source, "-C", work], check=True)
    # Instrument the planner's private build copy, where the public padding counts
    # are available before the verifier can open any proof or key.
    segment = work / "verifier/src/vf_segments.inc"
    source_text = segment.read_text()
    anchor = "  const size_t NL = linksH.size();"
    if source_text.count(anchor) != 1:
        raise ValueError("segment geometry export hook changed")
    instrument = "".join((ROOT / "scripts" / hook).read_text() for hook in ("segment-profile.inc", "weight-profile.inc", "head-profile.inc", "ff-profile.inc"))
    source_text = source_text.replace(anchor, instrument + anchor)
    smallness_hook = "  subH.open_rows.assign(NL, 1);"
    if source_text.count(smallness_hook) != 1:
        raise ValueError("smallness layout export hook changed")
    segment.write_text(source_text.replace(smallness_hook, (ROOT / "scripts/smallness-profile.inc").read_text() + smallness_hook))
    public = work / "tools/audit/pubtool.cpp"
    source_text = public.read_text()
    anchor = "    const blk::IndexName none"
    if source_text.count(anchor) != 1:
        raise ValueError("accounting export hook changed")
    public.write_text('#include "numbers/accounting.h"\n' + source_text.replace(
        anchor, (ROOT / "scripts/accounting-profile.inc").read_text() + "\n" + anchor))
    flags = ["clang++", "-std=c++17", "-O1", "-pthread", "-Iverifier/src", "-Iblocks", "-Iprover",
             "-DBLK_FIELD=2", "-DDIGEST_WORDS=8", "-DSERVING_BUILD=1", "-DBLK_COUNT_HASH_CALLS=1"]
    subprocess.run([*flags, "-DCP_VERIFY_AS_A_UNIT", '-DVF_SOURCE_DIGEST="' + "0"*64 + '"',
                    "-c", "verifier/src/cp_verify.cpp", "-o", "config.o"], cwd=work, check=True)
    subprocess.run([*flags, "tools/audit/pubtool.cpp", "config.o", "-o", "pubtool"], cwd=work, check=True)
    exports = work / "exports"
    for fixture in PROFILES:
        dest = exports / fixture
        dest.mkdir(parents=True)
        subprocess.run([work / "pubtool", work / "examples" / fixture / "config", "128", dest],
                       cwd=work, check=True, stdout=subprocess.DEVNULL,
                       env={**os.environ, "FLASHPROVE_SEGMENT_GEOMETRY": str(dest / "forests.tsv"),
                            "FLASHPROVE_SMALLNESS_LAYOUT": str(dest / "smallness.tsv"),
                            "FLASHPROVE_WEIGHT_LAYOUT": str(dest / "weights.tsv"),
                            "FLASHPROVE_HEAD_LAYOUT": str(dest / "head.tsv"),
                            "FLASHPROVE_FF_LAYOUT": str(dest / "ff.tsv")})
    for generator in ("key-geometry.py", "request-geometry.py", "segment-geometry.py", "weight-profile.py", "head-profile.py", "smallness-geometry.py", "ff-profile.py"):
        subprocess.run([sys.executable, ROOT / "scripts" / generator, exports,
                        *(["--check"] if check else [])], check=True)
    account = ROOT / "src/accounting_catalog.bend"
    content = accounting_catalog(exports)
    if check and content != account.read_text():
        raise ValueError("stage accounting differs from the pinned source")
    if not check:
        account.write_text(content)
    pack(exports, work / "examples", work, check)


def install(out):
    # Extract only named files; a consumer authenticates their exact bytes in Bend.
    for fixture in PROFILES:
        dest = out / fixture
        dest.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(ASSETS / (fixture + ".zip")) as archive:
            for stem in CHAINS:
                name = stem + ".parameters"
                with tempfile.NamedTemporaryFile(dir=dest, delete=False) as tmp:
                    try:
                        with archive.open(name) as stream:
                            shutil.copyfileobj(stream, tmp)
                        tmp.close()
                        Path(tmp.name).replace(dest / name)
                    finally:
                        Path(tmp.name).unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "check", "regenerate"])
    parser.add_argument("--output", type=Path, default=ROOT / "build/plans")
    args = parser.parse_args()
    if args.action == "install":
        install(args.output)
    else:
        (ROOT / "build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as tmp:
            reproduce(Path(tmp), args.action == "check")
    print(f"profiles {args.action}: {len(PROFILES)} configurations, {len(CHAINS)} chains each")
