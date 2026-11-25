#!/usr/bin/env python3
"""Aggregate consecutive request-clock intervals from one or two serial full-proof runs."""
from collections import Counter
from pathlib import Path
import re
import sys


def tally(path):
    text = Path(path).read_text()
    if "timing: workers 1" not in text.splitlines():
        raise ValueError(f"{path}: expected one observed worker")
    markers = [(name, int(t)) for name, t in
               re.findall(r"^request-clock (\w+) (\d+)$", text, re.M)]
    starts = [i for i, (name, _) in enumerate(markers) if name == "request_entry"]
    if len(starts) != 1:
        raise ValueError(f"{path}: expected one request")
    # Shared and own LIN also run during key verification. Their timestamps
    # precede the request. The final verdict is printed after its outer timer.
    stamps = markers[starts[0]:]
    if [name for name, _ in stamps[-2:]] != ["request_return", "verdict_written"]:
        raise ValueError(f"{path}: missing request return or verdict")
    visits, times = Counter(), Counter()
    for (_, begin), (name, end) in zip(stamps[:-2], stamps[1:-1]):
        if end < begin:
            raise ValueError(f"{path}: clock went backwards at {name}")
        visits[name] += 1
        times[name] += end - begin
    reported = re.findall(r"^timing: request (\d+) ms$", text, re.M)
    if reported != [str(sum(times.values()))]:
        raise ValueError(f"{path}: intervals disagree with the outer request timer")
    times["request_total"] = int(reported[0])
    visits["request_total"] = 1
    return visits, times


def main(paths):
    if len(paths) not in (1, 2):
        raise SystemExit("usage: tally-outer.py BEFORE_STDERR [AFTER_STDERR]")
    runs = [tally(path) for path in paths]
    visits = runs[0][0]
    if any(other != visits for other, _ in runs[1:]):
        raise ValueError("runs visited different request boundaries")
    columns = ["disjoint_ms"] if len(paths) == 1 else ["before_ms", "after_ms"]
    print("boundary", "visits", *columns, sep="\t")
    for name, n in visits.items():
        print(name, n, *(times[name] for _, times in runs), sep="\t")


if __name__ == "__main__":
    main(sys.argv[1:])
