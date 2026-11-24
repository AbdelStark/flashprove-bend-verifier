#!/usr/bin/env python3
"""Sample the stacks of one standalone verification call and tabulate where its time goes.

    scripts/profile.py [FIXTURE] [--seconds N]        (default fixture: accepted-proof)

Writes build/profile/<fixture>.txt: the stage lines of `-timing`, then one row per function
at the top of the working thread's stack with its share of that thread's samples. The
generated C keeps Bend's names, so `extension_product` is `product` of src/extension.bend;
`term_drop`, `span_fade` and `rfc_wrap` are the runtime freeing and counting heap cells.
Sampling uses macOS `sample`. On Linux, run the printed command under `perf record -g`.
"""
import argparse
import os
import platform
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
EXAMPLES = ROOT / ".upstream/FlashProve/examples"
ROW = re.compile(r"^\s+(\S+)\s+\(in verify-bend\)\s+(\d+)\s*$")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("fixture", nargs="?", default="accepted-proof")
    ap.add_argument("--seconds", type=int, default=6, help="how long to sample")
    args = ap.parse_args()
    example = EXAMPLES / args.fixture
    stated = re.search(r" -policy (clipped-gap,[0-9,]+)", (example / "README.md").read_text())
    cmd = [str(BUILD / "verify-bend"), *(str(example / f) for f in
           ("config", "ivk", "example.req", "example.y", "example.proof")),
           "-id", (example / "ID.txt").read_text().strip(), "-data", str(BUILD), "-j", "1", "-timing",
           *(["-policy", stated[1]] if stated else [])]
    if platform.system() != "Darwin":
        print("profile: stack sampling here uses macOS `sample`. On Linux run:\n  perf record -g -- "
              + " ".join(cmd) + "\n  perf report --no-children --sort symbol", file=sys.stderr)
        return 2
    out = BUILD / "profile" / f"{args.fixture}.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "sample.txt"
        call = subprocess.Popen(cmd, env={**os.environ, "PATH": ""},
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(0.3)
        subprocess.run(["/usr/bin/sample", str(call.pid), str(args.seconds), "-file", str(raw)],
                       capture_output=True)
        stdout, stderr = call.communicate()
        if call.returncode != 0 or not raw.exists():
            print(f"profile: the call ended {call.returncode}\n{stdout[-500:]}{stderr[-500:]}", file=sys.stderr)
            return 1
        text = raw.read_text()
    section = text.split("Sort by top of stack", 1)[1] if "Sort by top of stack" in text else ""
    rows = [(int(m[2]), re.sub(r"^_+src_", "", re.sub(r"^(spin_|WL_FID_)", "", m[1])))
            for m in map(ROW.match, section.splitlines()) if m]
    total = sum(n for n, _ in rows)
    if not total:
        print("profile: no sample of the verifier was taken", file=sys.stderr)
        return 1
    lines = [f"# {args.fixture}: {total} samples of the working thread over {args.seconds} s",
             *(l for l in stderr.splitlines() if l.startswith("timing: ")),
             "share\tsamples\tfunction",
             *(f"{100 * n / total:5.1f}%\t{n}\t{name}" for n, name in sorted(rows, reverse=True))]
    out.write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:24]))
    print(f"profile: wrote {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
