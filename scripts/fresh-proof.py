#!/usr/bin/env python3
"""Generate one H821 commitment and next-token proof and compare both production verifiers.

Run on Linux with one available CUDA GPU, GNU g++ 13+ and the CUDA compiler
required by the pinned FlashProve release. Start in a checkout prepared by
`make upstream standalone`. Provider files live in a private temporary
directory. A successful run prints only public hashes and closing evidence.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CONFIG = "examples/accepted-proof/config"
INPUTS = ["config", "ivk", "in/example.req", "out/example.y", "out/example.proof"]
BUILD = re.compile(r"(?<= build=)[0-9a-f]{64}$")
SOURCES = ["VERSION", "LICENSE", "NOTICE", "verifier", "prover", "blocks", "tools",
           CONFIG, "examples/accepted-proof/ID.txt"]


def closing(text):
    lines = text.rstrip().splitlines()[-4:]
    if (len(lines) != 4 or not lines[0].startswith("commitment: ")
            or not lines[1].startswith("proof of work: ")
            or not lines[2].startswith("result-v1 status=0 ")
            or BUILD.search(lines[2]) is None or lines[3] != "YES"):
        raise ValueError("missing successful whole-call closing evidence")
    return lines


def compare(cpp, bend, request, ident, bend_digest):
    reference = closing(cpp)
    candidate = closing(bend)
    if BUILD.search(candidate[2])[0] != bend_digest:
        raise ValueError("Bend build digest disagrees with the supplied binary bundle")
    if [BUILD.sub("<digest>", s) for s in candidate] != [BUILD.sub("<digest>", s) for s in reference]:
        raise ValueError("the two verifiers reported different public results")
    tokens = len(request) // 4 - 2
    if len(request) % 4 or tokens <= 0 or struct.unpack("<II", request[-8:]) != (tokens - 1, tokens):
        raise ValueError("the generated request does not exclusively cover the next token")
    fields = dict(word.split("=", 1) for word in candidate[2].split()[1:])
    expected = {"claim": "next-token", "tokens": "none", "y": "yes", "id": ident,
                "T": str(tokens), "r": str(tokens - 1), "e": str(tokens)}
    if any(fields[k] != v for k, v in expected.items()):
        raise ValueError("accepted coverage disagrees with the caller's request")
    return candidate, BUILD.search(reference[2])[0]


def serving_identity(directory, pin):
    programs = {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                for name in ("cp_commit", "cp_prove", "cp_verify")}
    samples = {}
    for name in ("cp_commit", "cp_prove"):
        entries = [line.partition(" ") for line in (directory / (name + ".build")).read_text().splitlines()]
        record = {key: value for key, _, value in entries}
        if record["sha256"] != programs[name] or record["said-commit"] != pin or record["program"] != "hc/" + name:
            raise ValueError(f"serving build record disagrees with {name}")
        if name == "cp_commit" and record["verifier-beside"] != programs["cp_verify"]:
            raise ValueError("cp_verify disagrees with the committer's serving build record")
        samples[name] = record["compiler-sample"]
    return {"program_sha256": programs, "compiler_sample": samples}


def check_commitment(checkout, work, env, binary, data, digest, pin):
    identity = serving_identity(Path(env.get("BUILD", checkout / "prover/build/hc")), pin)
    kit = checkout / "prover/examples/target_released_next"
    kit.mkdir()
    for item in ("policy.txt", "KL.bin", "layout.txt"):
        (kit / item).write_bytes((checkout / CONFIG / item).read_bytes())
    provider = work / "provider"
    with (work / "run.log").open("w") as log:
        result = subprocess.run(["prover/examples/run_target_example.sh", kit.name, provider],
                                cwd=checkout, stdout=log, stderr=subprocess.STDOUT, env=env)
    if result.returncode:
        stage = next((s for s in ("cp_verify", "cp_prove", "cp_commit")
                      if (provider / (s + ".log")).is_file()), "setup")
        raise RuntimeError(f"upstream fresh-proof run failed at {stage}, status {result.returncode}")
    cpp = (provider / "cp_verify.log").read_text()
    ident = re.search(r"^commitment ID: ([a-f0-9 ]+)$",
                      (provider / "cp_commit.log").read_text(), re.M)[1].replace(" ", "")
    if not re.fullmatch("[0-9a-f]{64}", ident) or ident == (checkout / "examples/accepted-proof/ID.txt").read_text().strip():
        raise ValueError("expected a fresh 256-bit commitment ID")
    actual = subprocess.run([binary, *INPUTS, "-id", ident, "-data", data, "-q"], cwd=provider,
                            env={"BEND_THREADS": "1", "PATH": ""}, capture_output=True,
                            text=True, timeout=3600)
    if actual.returncode:
        detail = (actual.stderr or actual.stdout).strip().splitlines()
        raise RuntimeError(f"Bend rejected the public C++-accepted proof with status {actual.returncode}: "
                           + " ".join(detail[-2:]))
    lines, cpp_digest = compare(cpp, actual.stdout, (provider / INPUTS[2]).read_bytes(), ident, digest)
    paths = ["config/policy.txt", "config/KL.bin", "config/layout.txt", "ivk/key.bin",
             "ivk/leaf/0.bin", *INPUTS[2:]]
    hashes = {p: hashlib.sha256((provider / p).read_bytes()).hexdigest() for p in paths}
    print(json.dumps({"flashprove_commit": pin, "serving_build": identity,
                      "cpp_source": cpp_digest, "bend_source": digest,
                      "proof_bytes": (provider / INPUTS[4]).stat().st_size,
                      "next_token": struct.unpack("<I", (provider / INPUTS[3]).read_bytes())[0],
                      "public_sha256": hashes, "closing": lines}, indent=2))


def run(args):
    pin = re.search(r"^FLASHPROVE_COMMIT=([a-f0-9]{40})$", (ROOT / "upstream.lock").read_text(), re.M)[1]
    ref = args.upstream.resolve()
    binary = args.bend.resolve(strict=True)
    digest = binary.with_name(binary.name + ".digest").read_text().strip()
    data = args.data.resolve(strict=True)
    env = {key: os.environ[key] for key in ("PATH", "CUDA_VISIBLE_DEVICES", "CUDA_DEVICE_ORDER")
           if key in os.environ}
    with tempfile.TemporaryDirectory(prefix="fp-prover.", dir=args.scratch) as tmp:
        work = Path(tmp).resolve()
        env.update(HOME=str(work), TMPDIR=str(work))
        checkout = work / "source"
        checkout.mkdir()
        # The example helper expects a kit next to itself. Change only this disposable export.
        archive = work / "source.tar"
        with archive.open("wb") as stream:
            subprocess.run(["git", "-C", ref, "archive", pin, *SOURCES], stdout=stream, check=True)
        subprocess.run(["tar", "xf", archive, "-C", checkout], check=True)
        for name, command in (("verifier", ["verifier/build.sh"]),
                              ("prover", ["prover/build.sh", "serving", pin])):
            print(f"Building pinned production {name}", file=sys.stderr, flush=True)
            with (work / (name + ".log")).open("w+") as log:
                proc = subprocess.run(command, cwd=checkout, stdout=log, stderr=subprocess.STDOUT, env=env)
                if proc.returncode:
                    log.seek(0)
                    raise RuntimeError(f"{name} build failed: " + "\n".join(log.read().splitlines()[-12:]))
        check_commitment(checkout, work, env, binary, data, digest, pin)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", type=Path, default=Path(os.environ.get("SLURM_TMPDIR", "/tmp")),
                        help="node-local directory with private ancestry or a sticky /tmp")
    parser.add_argument("--upstream", type=Path, default=ROOT / ".upstream/FlashProve")
    parser.add_argument("--bend", type=Path, default=ROOT / "build/verify-bend")
    parser.add_argument("--data", type=Path, default=ROOT / "build")
    run(parser.parse_args())
