#!/usr/bin/env python3
"""Reference for tests/extension_random.bend: the checksum of 10,000 pseudo-random products
in F_p[X]/(X^3 - 2), computed with Python integers. Prints the expected `#|` line and how
often each special operand shape occurred."""
M = 0xFFFFFFFF
P = 2**64 - 2**32 + 1


def nxt(s):  # xorshift32
    a = s ^ ((s << 13) & M)
    b = a ^ (a >> 17)
    return b ^ ((b << 5) & M)


def shape(k, h, l):
    special = {1: (0, 0), 2: (0, 1), 3: (M, 0), 4: (M - 1, M), 5: (0, l)}
    return special.get(k, (h, 0 if h == M and l else l))


def run(n, s):
    acc, plain_a, plain_b = 0, 0, 0
    for _ in range(n):
        w = []
        for _ in range(13):
            s = nxt(s)
            w.append(s)
        v = [(h << 32) | l for h, l in (shape((w[12] >> (3 * i)) & 7, w[2 * i], w[2 * i + 1]) for i in range(6))]
        assert all(x < P for x in v)
        a, b = v[:3], v[3:]
        plain_a += a[1] == 0 and a[2] == 0
        plain_b += b[1] == 0 and b[2] == 0
        c = ((a[0] * b[0] + 2 * (a[1] * b[2] + a[2] * b[1])) % P,
             (a[0] * b[1] + a[1] * b[0] + 2 * a[2] * b[2]) % P,
             (a[0] * b[2] + a[1] * b[1] + a[2] * b[0]) % P)
        for x in c:
            acc = (acc * 31 + (x >> 32)) & M
            acc = (acc * 31 + (x & M)) & M
    return acc, plain_a, plain_b


if __name__ == "__main__":
    acc, plain_a, plain_b = run(10000, 2463534242)
    print(f"#|{acc}")
    print(f"base-field first operand: {plain_a}, base-field second operand: {plain_b}")
