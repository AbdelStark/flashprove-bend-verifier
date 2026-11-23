import sys
d = open(sys.argv[1], "rb").read(); n = len(d) // 8; p = (1 << 64) - (1 << 32) + 1
x = 0; bad = 0
for i in range(n):
    w = int.from_bytes(d[8 * i:8 * i + 8], "little"); x ^= w; bad += w >= p
print(x >> 32, x & 0xffffffff, f"bad={bad} n={n}")
