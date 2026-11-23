#!/usr/bin/env python3
"""Compare the closing records of whole verification calls to pinned upstream examples."""
import argparse
import hashlib
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / ".upstream/FlashProve/examples"
BUILD = ROOT / "build"
SHA = r"[0-9a-f]{64}"


def build_digests(reference_only):
    reference = re.search(r"prints `build=(" + SHA + r")`", (EXAMPLES / "README.md").read_text())[1]
    digests = {"cp_verify": reference}
    if not reference_only:
        candidate = (BUILD / "bend_verify.digest").read_text().strip()
        if not re.fullmatch(SHA, candidate) or candidate == reference:
            raise SystemExit(f"Invalid hybrid build digest {candidate!r}")
        digests["bend_verify"] = candidate
    return digests


def honest(binary, example, digest, benchmark=False, threads=1):
    # Test expectations are published alongside each fixture in the pinned repository.
    readme = (example / "README.md").read_text()
    expected = re.search(r"^commitment: [^\n]+\nproof of work: [^\n]+\nresult-v1 [^\n]+\n[^\n]+", readme, re.M)[0]
    model_id = re.search(r"\bid=(" + SHA + r")\b", expected)[1]
    args = [binary, example / "config", example / "ivk", example / "example.req",
            example / "example.y", example / "example.proof", "-id", model_id, "-q", "-j", str(threads)]
    policy = re.search(r" -policy (clipped-gap,[0-9,]+)", readme)
    if policy:
        args.extend(["-policy", policy[1]])

    if benchmark and Path("/usr/bin/time").is_file():
        # Each call gets its own measurement (RUSAGE_CHILDREN in this process is cumulative).
        time_args = ["-l"] if sys.platform == "darwin" else ["-f", "%M peak-kib"]
        args = ["/usr/bin/time", *time_args, *args]
    start = time.monotonic()
    result = subprocess.run(args, capture_output=True, text=True, timeout=600)
    elapsed = time.monotonic() - start
    record = "\n".join(result.stdout.splitlines()[-4:])
    if result.returncode != 0 or record != expected.replace("<64 hex digits>", digest):
        raise SystemExit(f"{binary.name} {example.name} exit {result.returncode}\n{record}\n{result.stderr}")
    rss = re.search(r"^\s*(\d+)\s+(maximum resident set size|peak-kib)$", result.stderr, re.M) if benchmark else None
    memory = ""
    if rss:
        unit = 1024 * 1024 if sys.platform == "darwin" else 1024
        memory = f"  max-rss={int(rss[1]) / unit:.1f} MiB"
    print(f"{binary.name} {example.name} {elapsed:.3f}s{memory}  {record.splitlines()[-1]}", flush=True)
    return re.sub(r" build=" + SHA, "", record), elapsed


def claim_options(binary):
    for fixture, extra, code, verdict in [
        ("accepted-proof", [], 14, "NOT-A-VERIFICATION"),
        ("accepted-proof-clipped-gap", ["-id"], 1, "NO: policy"),
        ("accepted-proof-clipped-gap", ["-id", "-policy", "clipped-gap,9244130,323343,0,16,8"], 1, "NO: policy"),
    ]:
        example = EXAMPLES / fixture
        if "-id" in extra:
            extra.insert(1, (example / "ID.txt").read_text().strip())
        result = subprocess.run(
            [binary, example / "config", example / "ivk", example / "example.req",
             example / "example.y", example / "example.proof", "-q", *extra],
            capture_output=True, text=True, timeout=600,
        )
        if result.returncode != code or result.stdout.splitlines()[-1:] != [verdict]:
            raise SystemExit(f"{binary.name} {fixture} {extra} returned {result.returncode}\n{result.stdout}")
    print(f"{binary.name} withheld ID, omitted policy and mismatched policy: all refused", flush=True)


def mutation_result(command, expected):
    result = subprocess.run(command, text=True, capture_output=True, timeout=1200)
    if result.returncode or result.stdout.splitlines()[-1:] != [expected]:
        raise SystemExit(f"Mutation suite exited {result.returncode}\n{result.stdout}\n{result.stderr}")


def altered(binary, fixture, table=None):
    folder = EXAMPLES / "rejected-proofs"
    count = 79 if table is not None else 10
    expected = f"{count} altered sets: all rejected"
    with tempfile.TemporaryDirectory() as work:
        command = [sys.executable, "-I", "-B", folder / "try_altered_copies.py", binary, Path(work) / "copies"]
        if table is not None:
            command.append(folder / table)
        mutation_result([*command, "--example", fixture], expected)
    print(f"{binary.name} {table or fixture}  {expected}", flush=True)


def extended(binary):
    example = EXAMPLES / "accepted-proof"
    altered(binary, example.name, "every_kind_of_item.tsv")
    runner = EXAMPLES.parent / "verifier/tests/record_altered_sets_test.py"
    model_id = (example / "ID.txt").read_text().strip()
    expected = f"{runner.name}: 7 calls on the honest set and its unaltered copy, 23 altered sets: all as expected"
    with tempfile.TemporaryDirectory() as work:
        mutation_result([sys.executable, "-I", "-B", runner, binary, example / "config", example / "ivk",
                         example / "example.req", example / "example.y", example / "example.proof",
                         model_id, Path(work) / "copies"], expected)
    print(f"{binary.name} {expected}", flush=True)


def benchmark(count, full_size, threads):
    # The public CLI execs a worker beside itself. Snapshot both and the oracle so an
    # atomic concurrent rebuild cannot change the programs midway through the samples.
    digests = build_digests(False)
    expected = {"cp_verify": digests["cp_verify"], "verify": digests["bend_verify"]}
    print(f"{platform.platform()} {platform.machine()}, {count} whole calls per binary, -j {threads}", flush=True)
    with tempfile.TemporaryDirectory(dir=BUILD) as tmp:
        binaries = Path(tmp)
        for name in ["cp_verify", "bend_verify", "verify"]:
            path = binaries / name
            shutil.copy2(BUILD / name, path)
            print(f"{name} executable SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()}", flush=True)
        for fixture in ["accepted-proof", "full-size"] if full_size else ["accepted-proof"]:
            times = {name: [] for name in expected}
            for index in range(count):
                for name in expected if index % 2 == 0 else reversed(expected):
                    _, elapsed = honest(binaries / name, EXAMPLES / fixture, expected[name], benchmark=True, threads=threads)
                    times[name].append(elapsed)
            for name, samples in times.items():
                print(f"{fixture} {name} median {median(samples):.3f}s (range {min(samples):.3f}–{max(samples):.3f}s)")
            ratio = median(times["verify"]) / median(times["cp_verify"])
            print(f"{fixture} Bend/C++ median wall-time ratio {ratio:.2f}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full-size", action="store_true", help="also run the two full-size examples (4 GiB each)")
    parser.add_argument("--reference-only", action="store_true", help="exercise the unchanged C++ verifier alone")
    parser.add_argument("--benchmark", type=int, metavar="SAMPLES", help="alternate exact-match whole calls and report medians")
    parser.add_argument("--extended", action="store_true", help="run the 79 item and 23 record alteration cases only")
    parser.add_argument("--threads", type=int, metavar="N", default=1, help="worker thread count for benchmarking (1 to 256)")
    args = parser.parse_args()
    if not 1 <= args.threads <= 256 or (args.benchmark is None and args.threads != 1):
        parser.error("--threads requires benchmarking and an integer from 1 to 256")
    if args.extended:
        if args.benchmark is not None or args.full_size:
            parser.error("--extended runs its own small fixture and cannot be combined with --benchmark or --full-size")
        extended(BUILD / "cp_verify")
        if not args.reference_only:
            extended(BUILD / "bend_verify")
        return
    if args.benchmark is not None:
        if args.benchmark < 1 or args.reference_only:
            parser.error("--benchmark requires a positive sample count and both verifiers")
        benchmark(args.benchmark, args.full_size, args.threads)
        return
    digests = build_digests(args.reference_only)
    fixtures = ["accepted-proof", "accepted-proof-clipped-gap"]
    if args.full_size:
        fixtures += ["full-size", "full-size-clipped-gap"]
    for fixture in fixtures:
        reference_record, _ = honest(BUILD / "cp_verify", EXAMPLES / fixture, digests["cp_verify"])
        if not args.reference_only:
            candidate_record, _ = honest(BUILD / "bend_verify", EXAMPLES / fixture, digests["bend_verify"])
            if reference_record != candidate_record:
                raise SystemExit(f"{fixture} differential closing records disagree")
    for name in digests:
        claim_options(BUILD / name)
        for fixture in fixtures[:2]:
            altered(BUILD / name, fixture)


if __name__ == "__main__":
    main()
