#!/usr/bin/env python3
"""Mechanical anti-drift checks over the repo's Markdown. Run by `make docs-check` and CI.

Rules (each failure prints `path:line: rule: message`):
  status    every file under docs/ declares `> Status: living|frozen|superseded` near its top
  link      every relative Markdown link resolves to a file in the repo
  pin       a Bend version or FlashProve commit written in a living doc equals the lock file
  make      every `make <target>` written in a living doc is a target of the Makefile
  req       a requirement ID (REQ-<AREA>-<n>) is defined at most once across docs/spec
  open      no TODO/TBD/FIXME in a living doc unless the same line cites an issue (#123)
  path      every repo path written in backticks in AGENTS.md exists

Frozen and superseded docs are snapshots: only `status` and `link` apply to them.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATUS = re.compile(r"^> Status: (living|frozen|superseded)\b", re.M)
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)\)")
REQ_DEF = re.compile(r"^\|?\s*\*\*(REQ-[A-Z0-9]+-\d+)\*\*", re.M)
OPEN = re.compile(r"\b(TODO|TBD|FIXME)\b")
ISSUE = re.compile(r"#\d+")


def lock(name: str) -> dict[str, str]:
    pairs = (l.split("=", 1) for l in (ROOT / name).read_text().splitlines() if "=" in l and not l.startswith("#"))
    return {k.strip(): v.strip() for k, v in pairs}


def tracked_markdown() -> list[Path]:
    out = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "*.md"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.split("\n")
    return [ROOT / p for p in out if p]


def main() -> int:
    bend_version = lock("toolchain.lock")["BEND_VERSION"]
    commit = lock("upstream.lock")["FLASHPROVE_COMMIT"]
    makefile = (ROOT / "Makefile").read_text() if (ROOT / "Makefile").exists() else ""
    targets = set(re.findall(r"^([A-Za-z0-9_.-]+):", makefile, re.M))
    errors: list[str] = []
    req_seen: dict[str, str] = {}

    for md in tracked_markdown():
        rel = md.relative_to(ROOT)
        text = md.read_text()
        in_docs = rel.parts[0] == "docs"
        m = STATUS.search("\n".join(text.splitlines()[:12]))
        if in_docs and not m:
            errors.append(f"{rel}:1: status: missing `> Status: living|frozen|superseded` in the first 12 lines")
        living = not (m and m.group(1) != "living")
        fenced = False
        for n, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("```"):
                fenced = not fenced
            if fenced:
                continue
            for target in LINK.findall(line):
                if re.match(r"^(https?:|mailto:|#)", target):
                    continue
                path = (md.parent / target.split("#", 1)[0]).resolve()
                if not path.exists():
                    errors.append(f"{rel}:{n}: link: `{target}` does not resolve")
            if not living:
                continue
            for v in re.findall(r"\bBend (\d+\.\d+\.\d+)\b", line):
                if v != bend_version:
                    errors.append(f"{rel}:{n}: pin: Bend {v} but toolchain.lock pins {bend_version}")
            for sha in re.findall(r"\b[0-9a-f]{7,40}\b", line):
                if "FlashProve" in line and re.search(r"[a-f]", sha) and re.search(r"\d", sha) \
                        and not commit.startswith(sha):
                    errors.append(f"{rel}:{n}: pin: FlashProve commit {sha} but upstream.lock pins {commit[:12]}")
            for t in re.findall(r"`make ([A-Za-z0-9_.-]+)", line):
                if t not in targets:
                    errors.append(f"{rel}:{n}: make: `make {t}` is not a Makefile target")
            if OPEN.search(line) and not ISSUE.search(line) and rel.name != "check-docs.py":
                errors.append(f"{rel}:{n}: open: {OPEN.search(line).group(1)} without an issue reference")
            if rel.as_posix() == "AGENTS.md":
                for p in re.findall(r"`((?:docs|scripts|src|tests|research|\.github)/[^`*<> ]*|[A-Za-z.]+\.(?:lock|md))`", line):
                    if not (ROOT / p).exists():
                        errors.append(f"{rel}:{n}: path: `{p}` does not exist")
        if in_docs and len(rel.parts) > 1 and rel.parts[1] == "spec":
            for req in REQ_DEF.findall(text):
                if req in req_seen:
                    errors.append(f"{rel}:1: req: {req} already defined in {req_seen[req]}")
                req_seen[req] = str(rel)

    for e in errors:
        print(e)
    print(f"docs-check: {len(errors)} problem(s) in {len(tracked_markdown())} Markdown files")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
