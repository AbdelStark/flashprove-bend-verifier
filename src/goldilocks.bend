import Base

# Goldilocks field p = 2^64 - 2^32 + 1; an element is two U32 limbs (hi, lo), canonical (< p).
type Gl is Data:
  Gl{hi: U32, lo: U32}

# carry out of s = a + b
def carry(a: U32, s: U32) -> U32:
  Bool.to_u32(U32.is_lt(s, a))

# borrow out of a - b
def borrow(a: U32, b: U32) -> U32:
  Bool.to_u32(U32.is_lt(a, b))

# A 16-bit half times a 32-bit word fits in the pinned runtime's 48-bit Nat.
# The second sum equals floor(a * b / 2^16), also strictly below 2^48.
def mulhi(+a: U32, +b: U32) -> U32:
  low  = Nat.mul(U32.to_nat(U32.and(a, 65535)), U32.to_nat(b))
  high = Nat.mul(U32.to_nat(U32.shrn(a, 16n)), U32.to_nat(b))
  U32.from_nat(Nat.div(Nat.add(high, Nat.div(low, 65536n)), 65536n))

def radix() -> Nat: Nat.mul(65536n, 65536n)

def high_word(n: Nat) -> Nat: Nat.div(n, radix())

# A column of three limbs with its incoming carry is below 3 * 2^32.
def column(a: U32, b: U32, c: U32, carry_in: Nat) -> Nat:
  Nat.add(Nat.add(U32.to_nat(a), U32.to_nat(b)), Nat.add(U32.to_nat(c), carry_in))

# Write q = 2^32. Since q² = q - 1 and q³ = -1 modulo p, the residue
# before carrying is (x0 - x2 - x3) + q * (x1 + x2). Bias the low column
# by 2q and the high column by q - 2 so both stay nonnegative.
def Gl.reduce(x3: U32, +x2: U32, x1: U32, x0: U32) -> Gl:
  +low = Nat.sub(Nat.add(U32.to_nat(x0), Nat.double(radix())), Nat.add(U32.to_nat(x2), U32.to_nat(x3)))
  +high = Nat.add(Nat.add(U32.to_nat(x1), U32.to_nat(x2)), Nat.add(4294967294n, high_word(low)))
  # Removing the high bias leaves (wrap - 1) extra q² units. Carry their
  # equivalent (wrap - 1) * (q - 1) into the two low limbs.
  +wrap = high_word(high)
  +corrected = Nat.sub(Nat.add(U32.to_nat(U32.from_nat(low)), Nat.add(radix(), 1n)), wrap)
  +lo = U32.from_nat(corrected)
  +hi = U32.sub(U32.add(U32.from_nat(high), U32.from_nat(Nat.add(wrap, high_word(corrected)))), 2)
  +ge = Bool.to_u32(Bool.and(U32.is_eq(hi, 4294967295), U32.is_ne(lo, 0)))
  Gl{U32.and(hi, U32.sub(ge, 1)), U32.sub(lo, ge)}

# The 128-bit product of two 64-bit values in four limbs, x0 lowest.
type W is Data:
  W{x3: U32, x2: U32, x1: U32, x0: U32}

# Both halves of the 64-bit product of two 32-bit words.
type P is Data:
  P{hi: U32, lo: U32}

def mul32(+a: U32, +b: U32) -> P:
  P{mulhi(a, b), U32.mul(a, b)}

def Gl.wide.join(p00: P, p01: P, p10: P, p11: P) -> W:
  P{+h00, +x0} = p00
  P{+h01, +l01} = p01
  P{+h10, +l10} = p10
  P{+h11, +l11} = p11
  +mid = column(h00, l01, l10, 0n)
  +top = column(h01, h10, l11, high_word(mid))
  W{U32.add(h11, U32.from_nat(high_word(top))), U32.from_nat(top), U32.from_nat(mid), x0}

def Gl.wide(+a1: U32, +a0: U32, +b1: U32, +b0: U32) -> W:
  Gl.wide.join(mul32(a0, b0), mul32(a0, b1), mul32(a1, b0), mul32(a1, b1))

def Gl.reduce_wide(w: W) -> Gl:
  W{x3, x2, x1, x0} = w
  Gl.reduce(x3, x2, x1, x0)

def Gl.mul(a1: U32, a0: U32, b1: U32, b0: U32) -> Gl:
  Gl.reduce_wide(Gl.wide(a1, a0, b1, b0))

# r - x4 * 2^32 (mod p) for a canonical r and x4 below 2^32 - 1. Since 2^128 = -2^32 (mod p),
# this takes the fifth limb x4 of a sum of products off the reduced lower four.
def Gl.lower(r: Gl, +x4: U32) -> Gl:
  Gl{+hi, +lo} = r
  +b = borrow(hi, x4)
  +l2 = U32.add(lo, b)
  Gl{U32.add(U32.sub(U32.sub(hi, x4), b), carry(lo, l2)), l2}

# 2x (mod p) for a canonical x.
def Gl.double(+h: U32, +l: U32) -> Gl:
  +lo2 = U32.shln(l, 1n)
  +hi2 = U32.or(U32.shln(h, 1n), U32.shrn(l, 31n))
  +ge = U32.or(U32.shrn(h, 31n), Bool.to_u32(Bool.and(U32.is_eq(hi2, 4294967295), U32.is_ne(lo2, 0))))
  Gl{U32.sub(U32.add(hi2, ge), borrow(lo2, ge)), U32.sub(lo2, ge)}
