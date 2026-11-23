#!/usr/bin/env python3
"""Materialize the binary64 tables for the two supported H821 model geometries (FORMAT §12.6).

Output is public input. The verifier checks its length and K(72) against the
policy committed by the caller's ID. Each file contains little-endian U32s.
"""
import argparse
from array import array
from math import ceil, cos, exp, floor, sin
from pathlib import Path
import sys
from tempfile import NamedTemporaryFile


def nearest(x):
    return floor(x + 0.5) if x >= 0 else ceil(x - 0.5)


def clamp(x, low, high):
    return min(max(x, low), high)


def silu():
    for t in range(65536):
        z = clamp(t - 32768, -16384, 16383) / 256
        yield 4096 + clamp(nearest(64 * (z / (1 + exp(-z)))), -4095, 4095)


def sigmoid():
    for t in range(65536):
        if t < 32768:
            yield 16 * nearest(4096 / (1 + exp(-(t - 16384) / 256)))
        else:
            yield 128 + clamp(t - 49152, -127, 127)


def rotary(lt, theta):
    freqs = [theta ** (-2 * i / 128) for i in range(64)]
    for fn in (cos, sin):
        for t in range(1 << lt):
            for freq in freqs:
                yield 4096 + nearest(4096 * fn(t * freq))


def softmax():
    u = 0
    while value := round(4096 * exp(-u / 256)):
        yield value
        u += 1


def write(directory, name, words, count):
    data = array("I", words)
    if data.itemsize != 4 or len(data) != count:
        raise ValueError(f"unexpected table size for {name}: {len(data)} x {data.itemsize}")
    if sys.byteorder != "little":
        data.byteswap()
    with NamedTemporaryFile(dir=directory, delete=False) as handle:
        data.tofile(handle)
        path = Path(handle.name)
    path.replace(directory / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    write(args.output, "silu-8-4095.bin", silu(), 65536)
    write(args.output, "sigmoid-1.bin", sigmoid(), 65536)
    write(args.output, "softmax-12-8.bin", softmax(), 2307)
    for lt, theta in [(6, 10000), (10, 500000)]:
        write(args.output, f"rotary-{lt}-128-12-{theta}.bin", rotary(lt, theta), (1 << lt) * 128)


if __name__ == "__main__":
    main()
