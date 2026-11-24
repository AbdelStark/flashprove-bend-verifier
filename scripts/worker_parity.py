#!/usr/bin/env python3
"""Replay native verifier calls with different worker counts and compare their output."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


def run_cli(command, *, parity_dir=None, case=None, workers=(1, 16), **kwargs):
    """With a parity directory, save exact outputs and return the serial result to the validator."""
    if parity_dir is None:
        return subprocess.run(command, capture_output=True, text=True, **kwargs)

    results = {count: subprocess.run([*command, "-j", str(count)], capture_output=True, **kwargs)
               for count in workers}
    observations = {
        count: {"exit": result.returncode,
                "stdout_base64": base64.b64encode(result.stdout).decode("ascii"),
                "stderr_base64": base64.b64encode(result.stderr).decode("ascii")}
        for count, result in results.items()
    }
    record = parity_dir / f"{case}.json"
    record.write_text(json.dumps(observations, indent=2) + "\n")
    if any(obs != observations[workers[0]] for obs in observations.values()):
        raise RuntimeError(f"worker disagreement for {case}: {record}")
    serial = results[workers[0]]
    return subprocess.CompletedProcess(command, serial.returncode, serial.stdout.decode(), serial.stderr.decode())


def dual_fault(out):
    example = ROOT / ".upstream/FlashProve/examples/accepted-proof"
    with tempfile.TemporaryDirectory(dir=BUILD) as tmp:
        copy = Path(tmp)
        shutil.copytree(example / "ivk", copy / "ivk")
        with (copy / "ivk/key.bin").open("r+b") as key:
            key.write(bytes(8))
        (copy / "truncated.proof").touch()
        command = [BUILD / "verify-bend", example / "config", copy / "ivk", example / "example.req",
                   example / "example.y", copy / "truncated.proof", "-id",
                   (example / "ID.txt").read_text().strip(), "-data", BUILD]
        result = run_cli(command, parity_dir=out, case="key-and-request", workers=(1, 2, 4, 8, 16),
                         env={**os.environ, "PATH": ""}, timeout=600)
        if result.returncode != 1 or (result.stdout + result.stderr).splitlines() != ["NO: key-header"]:
            raise RuntimeError("expected the key-header failure before the request failure")


def main():
    out = Path(tempfile.mkdtemp(prefix="worker-parity-", dir=BUILD))
    print(f"Worker parity evidence: {out.relative_to(ROOT)}", flush=True)
    for name in ("fixtures", "tables", "fuzz", "ordering"):
        (out / name).mkdir()
    summary = {
        "upstream_commit": subprocess.check_output(
            ["git", "-C", ROOT / ".upstream/FlashProve", "rev-parse", "HEAD"], text=True).strip(),
        "bend_source_digest": (BUILD / "verify-bend.digest").read_text().strip(),
        "binary_sha256": {name: hashlib.sha256((BUILD / name).read_bytes()).hexdigest()
                          for name in ("verify-bend", "cp_verify")},
        "workers": [1, 16],
        "fuzz_seed": "speed-first-pass",
    }
    (out / "identity.json").write_text(json.dumps(summary, indent=2) + "\n")
    suites = (
        ("fixtures", "standalone-test.py", ["--full-size"]),
        ("tables", "standalone-rejections.py", []),
        ("fuzz", "fuzz-differential.py", ["-n", "32", "--seed", summary["fuzz_seed"], "-j", "4",
                                         "--out", out / "fuzz-verdicts.json"]),
    )
    for phase, script, args in suites:
        subprocess.run([sys.executable, "-B", ROOT / "scripts" / script, "--parity-dir", out / phase, *args],
                       check=True)
    fuzz = json.loads((out / "fuzz-verdicts.json").read_text())
    if len(fuzz) != 64 or any(row["cpp"] != row["bend"] or row["cpp"] not in ("accept", "reject") for row in fuzz):
        raise RuntimeError(f"C++ differential check failed: {out / 'fuzz-verdicts.json'}")
    dual_fault(out / "ordering")
    for phase, expected in (("fixtures", 6), ("tables", 20), ("fuzz", 64), ("ordering", 1)):
        observed = len(list((out / phase).glob("*.json")))
        if observed != expected:
            raise RuntimeError(f"{phase}: expected {expected} worker comparisons, observed {observed}")
        print(f"{phase}: {observed} worker comparisons passed")


if __name__ == "__main__":
    main()
