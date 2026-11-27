#!/usr/bin/env python3
"""Mechanical anti-drift checks over the repo's Markdown. Run by `make docs-check` and CI.

Rules (each failure prints `path:line: rule: message`):
  status    every file under docs/ declares `> Status: living|frozen|superseded` near its top
  link      relative Markdown links point to checkout files or their directories
  pin       a Bend version or FlashProve commit written in a living doc equals the lock file
  make      literal make goals in inline code and sh/bash fences exist in the Makefile
  req       a requirement ID (REQ-<AREA>-<n>) is defined at most once across docs/spec
  open      no TODO/TBD/FIXME in a living doc unless the same line cites an issue (#123)
  path      every repo path written in backticks in AGENTS.md exists
  trace     every requirement row in docs/spec cites a `make` target that a workflow runs,
            directly or through `make ci` and the targets' prerequisites

Frozen and superseded docs are snapshots: only `status` and `link` apply to them.
"""
import os
import re
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATUS = re.compile(r"^> Status: (living|frozen|superseded)\b", re.M)
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)\)")
REQ_DEF = re.compile(r"^\|?\s*\*\*(REQ-[A-Z0-9]+-\d+)\*\*", re.M)
OPEN = re.compile(r"\b(TODO|TBD|FIXME)\b")
ISSUE = re.compile(r"#\d+")
GOAL = re.compile(r"[\w.][\w./-]*")
UPSTREAM_REF = re.compile(
    r"(?:github\.com/anthropics/FlashProve/(?:tree|blob|commit)/"
    r"|raw\.githubusercontent\.com/anthropics/FlashProve/"
    r"|\bFlashProve\s+(?:commit|revision)\s+`?)([0-9a-f]{7,40})\b", re.I)


def lock(name: str) -> dict[str, str]:
    pairs = (l.split("=", 1) for l in (ROOT / name).read_text().splitlines() if "=" in l and not l.startswith("#"))
    return {k.strip(): v.strip() for k, v in pairs}


def checkout_files() -> set[Path]:
    # Include new files during editing, exclude ignored outputs and working-tree deletions.
    names = subprocess.check_output(["git", "ls-files", "-coz", "--exclude-standard"], cwd=ROOT)
    paths = (Path(os.fsdecode(name)) for name in names.split(b"\0") if name)
    return {path for path in paths if (ROOT / path).is_file()}


def make_goals(command: str) -> list[str]:
    """Check the examples' simple `make GOAL ... NAME=value` form, using the repo Makefile."""
    if not re.match(r"^\s*make\s", command):
        return []
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        args = list(lexer)[1:]
    except ValueError:
        return []
    goals = [arg for arg in args if not re.match(r"^[A-Za-z_]\w*=", arg)]
    # Flags can select another Makefile. Shell control, redirections and expansions
    # also take an example outside the literal command form this checker understands.
    return goals if all(GOAL.fullmatch(goal) for goal in goals) else []


def workflow_reach(makefile: str) -> set[str]:
    """Make targets that a workflow step runs, closed over Makefile prerequisites."""
    deps: dict[str, set[str]] = {}
    for rule, prereqs in re.findall(r"^([\w./-]+(?: +[\w./-]+)*):(?!=)([^#\n]*)", makefile, re.M):
        for goal in rule.split():
            deps.setdefault(goal, set()).update(prereqs.replace("|", " ").split())
    todo = [goal for wf in sorted((ROOT / ".github/workflows").glob("*.y*ml"))
            for command in re.findall(r"^\s*(?:-\s+)?run:\s*(.+)$", wf.read_text(), re.M)
            for goal in make_goals(command)]
    seen: set[str] = set()
    while todo:
        goal = todo.pop()
        if goal not in seen:
            seen.add(goal)
            todo.extend(deps.get(goal, ()))
    return seen


def main() -> int:
    bend_version = lock("toolchain.lock")["BEND_VERSION"]
    commit = lock("upstream.lock")["FLASHPROVE_COMMIT"]
    makefile = (ROOT / "Makefile").read_text() if (ROOT / "Makefile").exists() else ""
    targets = {goal for rule in re.findall(r"^([\w./-]+(?: +[\w./-]+)*):", makefile, re.M)
               for goal in rule.split()}
    reach = workflow_reach(makefile)
    errors: list[str] = []
    req_seen: dict[str, str] = {}
    files = checkout_files()
    members = files | {parent for path in files for parent in path.parents}
    markdown = sorted(path for path in files if path.suffix == ".md")

    for rel in markdown:
        md = ROOT / rel
        text = md.read_text()
        in_docs = rel.parts[0] == "docs"
        m = STATUS.search("\n".join(text.splitlines()[:12]))
        if in_docs and not m:
            errors.append(f"{rel}:1: status: missing `> Status: living|frozen|superseded` in the first 12 lines")
        living = not (m and m.group(1) != "living")
        fence = None
        continued = ""
        for n, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("```"):
                fence = line.strip()[3:].strip() if fence is None else None
                continued = ""
                continue
            if living:
                snippets = []
                if fence is None:
                    snippets = re.findall(r"`([^`\n]+)`", line)
                elif fence in {"sh", "bash"}:
                    if line.endswith("\\"):
                        continued += line[:-1]
                        continue
                    snippets = [continued + line]
                    continued = ""
                for snippet in snippets:
                    for goal in make_goals(snippet):
                        if goal not in targets:
                            errors.append(f"{rel}:{n}: make: `make {goal}` is not a Makefile target")
            if fence is not None:
                continue
            for target in LINK.findall(line):
                if re.match(r"^(https?:|mailto:|#)", target):
                    continue
                path = md.parent / target.split("#", 1)[0]
                if (Path(os.path.relpath(path, ROOT)) not in members or
                        Path(os.path.relpath(path.resolve(), ROOT)) not in members):
                    errors.append(f"{rel}:{n}: link: `{target}` does not resolve in the checkout")
            if not living:
                continue
            for v in re.findall(r"\bBend (\d+\.\d+\.\d+)\b", line):
                if v != bend_version:
                    errors.append(f"{rel}:{n}: pin: Bend {v} but toolchain.lock pins {bend_version}")
            for sha in UPSTREAM_REF.findall(line):
                if not commit.startswith(sha.lower()):
                    errors.append(f"{rel}:{n}: pin: FlashProve commit {sha} but upstream.lock pins {commit[:12]}")
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
            if living:
                for n, line in enumerate(text.splitlines(), 1):
                    req = REQ_DEF.match(line)
                    if not req:
                        continue
                    goals = [g for snippet in re.findall(r"`([^`\n]+)`", line) for g in make_goals(snippet)]
                    if not goals:
                        errors.append(f"{rel}:{n}: trace: {req.group(1)} cites no `make` command")
                    for goal in goals:
                        if goal in targets and goal not in reach:
                            errors.append(f"{rel}:{n}: trace: {req.group(1)} cites `make {goal}`, which no workflow runs")

    for e in errors:
        print(e)
    print(f"docs-check: {len(errors)} problem(s) in {len(markdown)} Markdown files")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
