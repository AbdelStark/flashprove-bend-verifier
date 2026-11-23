#!/usr/bin/env python3
"""Spike generator: BLAKE2b compression in Bend 2 with 64-bit words as (hi, lo) U32 pairs.
Emits a benchmark that chains N compressions and prints the final state."""
import sys

SIGMA = [
 [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],
 [14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3],
 [11,8,12,0,5,2,15,13,10,14,3,6,7,1,9,4],
 [7,9,3,1,13,12,11,14,2,6,5,10,4,0,15,8],
 [9,0,5,7,2,4,10,15,14,1,11,12,6,8,3,13],
 [2,12,6,10,0,11,8,3,4,13,7,5,15,14,1,9],
 [12,5,1,15,14,13,4,10,0,7,6,3,9,2,8,11],
 [13,11,7,14,12,1,3,9,5,0,15,4,8,6,2,10],
 [6,15,14,9,11,3,0,8,12,2,13,7,1,4,10,5],
 [10,2,8,4,7,6,1,5,15,11,9,14,3,12,13,0],
]
IV = [0x6a09e667f3bcc908,0xbb67ae8584caa73b,0x3c6ef372fe94f82b,0xa54ff53a5f1d36f1,
      0x510e527fade682d1,0x9b05688c2b3e6c1f,0x1f83d9abfb41bd6b,0x5be0cd19137e2179]

def hi(x): return (x >> 32) & 0xffffffff
def lo(x): return x & 0xffffffff

out = []
w = out.append
w("import Base\n")
w("type G4 is Data:\n  G4{ah: U32, al: U32, bh: U32, bl: U32, ch: U32, cl: U32, dh: U32, dl: U32}\n")
vf = ", ".join(f"v{i}{p}: U32" for i in range(16) for p in "hl")
w(f"type V16 is Data:\n  V16{{{vf}}}\n")
hf = ", ".join(f"h{i}{p}: U32" for i in range(8) for p in "hl")
w(f"type H8 is Data:\n  H8{{{hf}}}\n")
w("""# carry out of a 32-bit add s = a + b, branch-free
def carry(+a: U32, +b: U32, +s: U32) -> U32:
  U32.shrn(U32.or(U32.and(a, b), U32.and(U32.or(a, b), U32.not(s))), 31n)
""")
w("""def B2b.g(+ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32, +dh: U32, +dl: U32, +xh: U32, +xl: U32, +yh: U32, +yl: U32) -> G4:
  +s0l = U32.add(al, bl)
  +s0h = U32.add(U32.add(ah, bh), carry(al, bl, s0l))
  +a1l = U32.add(s0l, xl)
  +a1h = U32.add(U32.add(s0h, xh), carry(s0l, xl, a1l))
  +d1h = U32.xor(dl, a1l)
  +d1l = U32.xor(dh, a1h)
  +c1l = U32.add(cl, d1l)
  +c1h = U32.add(U32.add(ch, d1h), carry(cl, d1l, c1l))
  +e1h = U32.xor(bh, c1h)
  +e1l = U32.xor(bl, c1l)
  +b1h = U32.or(U32.shrn(e1h, 24n), U32.shln(e1l, 8n))
  +b1l = U32.or(U32.shrn(e1l, 24n), U32.shln(e1h, 8n))
  +s2l = U32.add(a1l, b1l)
  +s2h = U32.add(U32.add(a1h, b1h), carry(a1l, b1l, s2l))
  +a2l = U32.add(s2l, yl)
  +a2h = U32.add(U32.add(s2h, yh), carry(s2l, yl, a2l))
  +f1h = U32.xor(d1h, a2h)
  +f1l = U32.xor(d1l, a2l)
  +d2h = U32.or(U32.shrn(f1h, 16n), U32.shln(f1l, 16n))
  +d2l = U32.or(U32.shrn(f1l, 16n), U32.shln(f1h, 16n))
  +c2l = U32.add(c1l, d2l)
  +c2h = U32.add(U32.add(c1h, d2h), carry(c1l, d2l, c2l))
  +g1h = U32.xor(b1h, c2h)
  +g1l = U32.xor(b1l, c2l)
  +b2h = U32.or(U32.shln(g1h, 1n), U32.shrn(g1l, 31n))
  +b2l = U32.or(U32.shln(g1l, 1n), U32.shrn(g1h, 31n))
  G4{a2h, a2l, b2h, b2l, c2h, c2l, d2h, d2l}
""")
# round: a chain of 8 step defs; each destructures the previous G4 (a parameter) and runs the next G.
cols = [(0,4,8,12),(1,5,9,13),(2,6,10,14),(3,7,11,15)]
diags = [(0,5,10,15),(1,6,11,12),(2,7,8,13),(3,4,9,14)]
quads = cols + diags
def words(names): return [f"{n}{p}" for n in names for p in "hl"]
# state naming: before step i the 16 words are named by cur[i]
defs = []
cur = {i: f"v{i}" for i in range(16)}
# step 0 is the entry: B2b.round(v..., x...)
# step k (1..8) takes r: G4 = result of G number k-1, plus the 12 untouched state words, plus remaining x words
entry_params = ", ".join(f"+{n}: U32" for n in words([cur[i] for i in range(16)]) + words([f"x{i}" for i in range(16)]))
chain_defs = []
prev_call = None
for k in range(9):
    if k == 0:
        header = f"def B2b.round({entry_params}) -> V16:"
        body = []
    else:
        a,b,c,d = quads[k-1]
        others = [i for i in range(16) if i not in (a,b,c,d)]
        params = ["r: G4"] + [f"+{n}: U32" for n in words([cur[i] for i in others])] + [f"+{n}: U32" for n in words([f"x{i}" for i in range(2*k, 16)])]
        header = f"def B2b.round.s{k}({', '.join(params)}) -> V16:"
        na, nb, nc, nd = (f"w{k}_{i}" for i in (a,b,c,d))
        body = [f"  G4{{+{na}h, +{na}l, +{nb}h, +{nb}l, +{nc}h, +{nc}l, +{nd}h, +{nd}l}} = r"]
        cur = dict(cur); cur[a], cur[b], cur[c], cur[d] = na, nb, nc, nd
    if k < 8:
        a,b,c,d = quads[k]
        others = [i for i in range(16) if i not in (a,b,c,d)]
        gargs = ", ".join(words([cur[i] for i in (a,b,c,d)]) + words([f"x{2*k}", f"x{2*k+1}"]))
        rest = ", ".join(words([cur[i] for i in others]) + words([f"x{i}" for i in range(2*(k+1), 16)]))
        body.append(f"  B2b.round.s{k+1}(B2b.g({gargs}){', ' + rest if rest else ''})")
    else:
        body.append("  V16{" + ", ".join(words([cur[i] for i in range(16)])) + "}")
    chain_defs.append(header + "\n" + "\n".join(body) + "\n")
for dfn in reversed(chain_defs):
    w(dfn)
# compress: chain of 12 round defs + final; each destructures the previous V16 parameter.
hp = [f"h{i}{p}" for i in range(8) for p in "hl"]
mp_names = [f"m{i}{p}" for i in range(16) for p in "hl"]
mp = ", ".join(f"+{n}: U32" for n in mp_names)
cdefs = []
vn = [f"v{i}{p}" for i in range(16) for p in "hl"]
for r in range(12, -1, -1):
    params = ["v: V16"] + [f"+{n}: U32" for n in hp] + ([f"+{n}: U32" for n in mp_names] if r < 12 else [])
    lines = [f"def B2b.rounds.r{r}({', '.join(params)}) -> H8:", "  V16{" + ", ".join("+" + n for n in vn) + "} = v"]
    if r < 12:
        s = SIGMA[r % 10]
        xs = ", ".join(f"m{s[i]}{p}" for i in range(16) for p in "hl")
        nxt_m = (", " + ", ".join(mp_names)) if r + 1 < 12 else ""
        lines.append(f"  B2b.rounds.r{r+1}(B2b.round({', '.join(vn)}, {xs}), {', '.join(hp)}{nxt_m})")
    else:
        res = [f"U32.xor(h{i}{p}, U32.xor(v{i}{p}, v{i+8}{p}))" for i in range(8) for p in "hl"]
        lines.append("  H8{" + ", ".join(res) + "}")
    cdefs.append("\n".join(lines) + "\n")
for dfn in cdefs:
    w(dfn)
hpp = ", ".join(f"+{n}: U32" for n in hp)
w(f"def B2b.compress({hpp}, {mp}, +t0h: U32, +t0l: U32, +t1h: U32, +t1l: U32, +fh: U32, +fl: U32) -> H8:")
vinit = list(hp)
for i in range(8):
    ivh, ivl = str(hi(IV[i])), str(lo(IV[i]))
    if i == 4: ivh, ivl = f"U32.xor({ivh}, t0h)", f"U32.xor({ivl}, t0l)"
    if i == 5: ivh, ivl = f"U32.xor({ivh}, t1h)", f"U32.xor({ivl}, t1l)"
    if i == 6: ivh, ivl = f"U32.xor({ivh}, fh)", f"U32.xor({ivl}, fl)"
    vinit += [ivh, ivl]
w("  B2b.rounds.r0(V16{" + ", ".join(vinit) + "}, " + ", ".join(hp) + ", " + ", ".join(mp_names) + ")\n")
# chain loop
w(f"def chain(n: Nat, h: H8, {mp}) -> H8:")
w("  match n:")
w("    case 0n:")
w("      h")
w("    case 1n+p:")
w("      H8{" + ", ".join("+" + n for n in hp) + "} = h")
ma = ", ".join(mp_names)
w(f"      chain(p, B2b.compress({', '.join(hp)}, {ma}, 0, 128, 0, 0, 0, 0), {ma})\n")
# Emit only the reusable kernel when building the verifier.
if sys.argv[1:] == ["kernel"]:
    print("\n".join(out))
    sys.exit(0)
w("def hex8.go(n: Nat, +x: U32, acc: String) -> String:\n  match n:\n    case 0n:\n      acc\n    case 1n+p:\n      hex8.go(p, U32.shrn(x, 4n), String.take(String.drop(\"0123456789abcdef\", U32.to_nat(U32.and(x, 15))), 1n) ++ acc)\n")
w("def hex8(x: U32) -> String:\n  hex8.go(8n, x, \"\")\n")
w("def H8.show(h: H8) -> String:")
w("  H8{" + ", ".join(f"h{i}{p}" for i in range(8) for p in "hl") + "} = h")
w("  " + " ++ ".join(f"hex8(h{i}h) ++ hex8(h{i}l) ++ \" \"" for i in range(8)) + "\n")
MODE = sys.argv[1] if len(sys.argv) > 1 else "1000"
h0 = list(IV); h0[0] ^= 0x01010040
hinit = ", ".join(f"{hi(x)}, {lo(x)}" for x in h0)
if MODE == "tree":
    D = int(sys.argv[2])
    zeros = ", ".join(["0"] * 30)
    w("def leaf(+i: U32) -> H8:")
    w(f"  B2b.compress({hinit}, 0, i, {zeros}, 0, 128, 0, 0, 0, 0)\n")
    w("def node(l: H8, r: H8) -> H8:")
    w("  H8{" + ", ".join(f"+a{i}" for i in range(16)) + "} = l")
    w("  H8{" + ", ".join(f"+b{i}" for i in range(16)) + "} = r")
    w(f"  B2b.compress({hinit}, " + ", ".join(f"a{i}" for i in range(16)) + ", " + ", ".join(f"b{i}" for i in range(16)) + ", 0, 128, 0, 0, 0, 0)\n")
    w("def htree(+d: Nat, +i: U32) -> H8:")
    w("  match d:")
    w("    case 0n:")
    w("      leaf(i)")
    w("    case 1n+p:")
    w("      l r = htree(p, i) htree(p, U32.add(i, U32.shln(1, p)))")
    w("      node(l, r)\n")
    w("def main() -> IO(Unit):")
    w("  do IO<Unit>:")
    w(f"    IO.print(H8.show(htree({D}n, 0)))")
else:
    N = int(MODE)
    msg = bytes(range(128))
    mw = [int.from_bytes(msg[8*i:8*i+8], "little") for i in range(16)]
    minit = ", ".join(f"{hi(x)}, {lo(x)}" for x in mw)
    w("def main() -> IO(Unit):")
    w("  do IO<Unit>:")
    w(f"    IO.print(H8.show(chain({N}n, H8{{{hinit}}}, {minit})))")
print("\n".join(out))
