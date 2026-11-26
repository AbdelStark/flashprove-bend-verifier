#!/usr/bin/env python3
"""Shared paths and helpers for the scripts that run the published FlashProve fixtures."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / ".upstream/FlashProve/examples"
BUILD = ROOT / "build"
SHA = r"[0-9a-f]{64}"
INPUTS = ("config", "ivk", "example.req", "example.y", "example.proof")


def reference_digest():
    """The source digest the unmodified C++ verifier prints in its closing record."""
    return re.search(r"prints `build=(" + SHA + r")`", (EXAMPLES / "README.md").read_text())[1]


def inputs(example):
    """The five positional input paths of a fixture, in command-line order."""
    return [example / name for name in INPUTS]


def stated_policy(example):
    """The `-policy` option a fixture's README publishes; a clipped-gap fixture must state one."""
    found = re.search(r" -policy (clipped-gap,[0-9,]+)", (example / "README.md").read_text())
    if "clipped-gap" in example.name and not found:
        raise SystemExit(f"{example.name}: README states no -policy")
    return ["-policy", found[1]] if found else []


def check_run(command, code, last, timeout=600, **kwargs):
    """Run `command`; require exit `code` and `last` as the exact final line of stdout and stderr."""
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, **kwargs)
    lines = (result.stdout + result.stderr).splitlines()
    if result.returncode != code or lines[-1:] != [last]:
        raise SystemExit(f"{command[0]} exited {result.returncode}, wanted {code} and {last!r}\n" + "\n".join(lines[-20:]))
    return result

