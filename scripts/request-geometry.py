#!/usr/bin/env python3
"""Derive R14.4/9/10 tree places from the pinned configuration-only planner's export."""
import argparse
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/request_geometry.bend"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("key_geometry", ROOT / "scripts/key-geometry.py")
geometry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(geometry)


def inspect(folder, chain, imported, require):
    rounds = geometry.rows(folder / f"proof.{chain}.rounds.tsv")
    messages = geometry.rows(folder / f"proof.{chain}.messages.tsv")
    chunks = iter(messages[i:i+3] for i, row in enumerate(messages) if row[0] == "opened symbols")
    sends = {}
    next_place = imported
    schedule = []
    for row in rounds:
        name, scope = row[:2]
        roots, draws, depth = map(int, (row[6], row[10], row[11]))
        if roots:
            sends.setdefault(scope, []).extend(range(next_place, next_place + roots))
            next_place += roots
        if not draws:
            continue
        opened = []
        for place, expected in require(name, scope, sends):
            role, (d, w, s) = geometry.shape(next(chunks), draws, depth)
            if not (role.startswith(expected + ";") or role == expected):
                raise ValueError(f"{chain} {scope}: expected {expected}, got {role}")
            if place is not None and place >= next_place:
                raise ValueError(f"{chain} {scope}: unopened tree {place}")
            target = "G.Table{}" if place is None else f"G.Local{{{place}n}}"
            opened.append(f"G.Tree{{{target},{d}n,{w}n,{s}n}}")
        schedule.append("[" + ",".join(opened) + "]")
    if next(chunks, None) is not None:
        raise ValueError(f"unconsumed openings in {chain}")
    return schedule, next_place


def previous(scope):
    base, _, suffix = scope.rpartition(", ")
    return f"{base}, stage {int(suffix.removeprefix('stage '))-1}"


def switch(scope, sends):
    if scope.endswith(", last stage"):
        # The final stage has no new switch oracle of its own.
        front = scope.rsplit(", ", 1)[0] + ", stage "
        stage = max((int(s[len(front):]) for s in sends if s.startswith(front)), default=0)
        key = front + str(stage)
    else:
        key = previous(scope)
    return [(sends[key][-1], scope + ", switch oracle")]


def first(name, scope, sends):
    if name == "LOC":
        published = sends[scope]
        # The first SEND also publishes the request's index-mask tree. Its opening
        # is deferred to proof.second. A carried row shares the next segment's
        # first tree with the kept and newly sent main rows (R12.16, R14.4).
        places = [published[0], *published[2:]] if scope == "G0" else published
        if len(places) != 3:
            raise ValueError(f"unexpected moment count for {scope}: {published}")
        first = "carried" if scope != "G0" else "G0, moment 1, group 1"
        return [(places[0], f"{scope}, tree of {first}"),
                (places[1], f"{scope}, tree of {scope}, moment 2, group 1"),
                (places[2], f"{scope}, tree of {scope}, moment 3, group 1")]
    if scope == "last group, stage 1":
        return [(sends["last group"][0], scope + ", tree of carried")]
    return switch(scope, sends)


def shared(name, scope, sends):
    if name == "LOC":
        return [(None, "table, table")]
    if scope == "folded row, stage 1":
        return [(sends["table, folded row"][0], scope + ", tree of the folded row"),
                (sends["table, Omega"][1], scope + ", tree of the mask of the split between Omega and the folded row")]
    if scope == "Omega, stage 1":
        return [(sends["table, Omega"][0], scope + ", tree of Omega"),
                (sends["table, Omega"][1], scope + ", tree of the mask of the split between Omega and the folded row"),
                (sends[scope][0], scope + ", fresh mask")]
    return switch(scope, sends)


def render(folder):
    one, count = inspect(folder, "first", 0, first)
    sh, _ = inspect(folder, "shared", 0, shared)

    def second(name, scope, sends):
        if scope == "a request's own test, stage 1":
            return [(1, scope + ", tree of a request's masks"), (count-1, scope + ", tree of W"),
                    (count, scope + ", tree of Omega")]
        return switch(scope, sends)
    two, _ = inspect(folder, "second", count+1, second)
    return (one, sh, two)


def generate(exports):
    lines = ["# Generated from configuration-only H821 plans by scripts/request-geometry.py.",
             "import Base", "import ./plan_types.bend as P", "import ./key_stage_geometry.bend as G", ""]
    for folder, name in (("accepted-proof","small"), ("full-size","full")):
        shapes = render(exports / folder)
        if shapes != render(exports / (folder + "-clipped-gap")):
            raise ValueError("the closed policy changed an opening shape")
        lines.extend([f"def {name}(chain: P.Chain) -> G.Schedule:", "  match chain:"])
        for kind, sched in zip(("RequestFirst", "RequestShared", "RequestSecond"), shapes):
            lines.extend([f"    case P.{kind}{{}}:", "      [" + ",\n       ".join(sched) + "]"])
        lines.extend(["    case _: []",""])
    lines.extend(["def schedule(profile: P.Profile, chain: P.Chain) -> G.Schedule:",
                  "  match profile:", "    case P.SmallExact{}: small(chain)", "    case P.SmallClipped{}: small(chain)",
                  "    case P.FullExact{}: full(chain)", "    case P.FullClipped{}: full(chain)", ""])
    return "\n".join(lines)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exports", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source = generate(args.exports)
    if args.check:
        if SOURCE.read_text() != source:
            raise SystemExit("request geometry differs from the pinned configuration export")
    else:
        SOURCE.write_text(source)
