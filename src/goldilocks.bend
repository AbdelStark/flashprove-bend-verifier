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

# high 32 bits of the 64-bit product a * b
def mulhi(+a: U32, +b: U32) -> U32:
  +al = U32.and(a, 65535)
  +ah = U32.shrn(a, 16n)
  +bl = U32.and(b, 65535)
  +bh = U32.shrn(b, 16n)
  +ll = U32.mul(al, bl)
  +lh = U32.mul(al, bh)
  +hl = U32.mul(ah, bl)
  +hh = U32.mul(ah, bh)
  +t = U32.add(lh, U32.shrn(ll, 16n))
  +u = U32.add(hl, U32.and(t, 65535))
  U32.add(U32.add(hh, U32.shrn(t, 16n)), U32.shrn(u, 16n))

# x3:x2:x1:x0 (128 bits) mod p, canonical
def Gl.reduce(+x3: U32, +x2: U32, +x1: U32, +x0: U32) -> Gl:
  +lo0 = U32.sub(x0, x3)
  +b0 = borrow(x0, x3)
  +hi0 = U32.sub(x1, b0)
  +b1 = borrow(x1, b0)
  +sub = U32.and(4294967295, U32.sub(0, b1))
  +lo0b = U32.sub(lo0, sub)
  +hi0b = U32.sub(hi0, borrow(lo0, sub))
  +lo1 = U32.sub(0, x2)
  +hi1 = U32.sub(x2, Bool.to_u32(U32.is_ne(x2, 0)))
  +lo2 = U32.add(lo0b, lo1)
  +c = carry(lo0b, lo2)
  +hi2a = U32.add(hi0b, hi1)
  +ca = carry(hi0b, hi2a)
  +hi2 = U32.add(hi2a, c)
  +cb = carry(hi2a, hi2)
  +add = U32.and(4294967295, U32.sub(0, U32.or(ca, cb)))
  +lo3 = U32.add(lo2, add)
  +hi3 = U32.add(hi2, carry(lo2, lo3))
  +ge = Bool.to_u32(Bool.and(U32.is_eq(hi3, 4294967295), U32.is_ne(lo3, 0)))
  Gl{U32.and(hi3, U32.sub(ge, 1)), U32.sub(lo3, ge)}

# The 128-bit product of two 64-bit values in four limbs, x0 lowest.
type W is Data:
  W{x3: U32, x2: U32, x1: U32, x0: U32}

# Both halves of the 64-bit product a * b, from four 16-bit partial products.
type P is Data:
  P{hi: U32, lo: U32}

def mul32(+a: U32, +b: U32) -> P:
  +al = U32.and(a, 65535)
  +ah = U32.shrn(a, 16n)
  +bl = U32.and(b, 65535)
  +bh = U32.shrn(b, 16n)
  +ll = U32.mul(al, bl)
  +lh = U32.mul(al, bh)
  +hl = U32.mul(ah, bl)
  +hh = U32.mul(ah, bh)
  +t = U32.add(lh, U32.shrn(ll, 16n))
  +u = U32.add(hl, U32.and(t, 65535))
  P{U32.add(U32.add(hh, U32.shrn(t, 16n)), U32.shrn(u, 16n)), U32.or(U32.shln(u, 16n), U32.and(ll, 65535))}

def Gl.wide.join(p00: P, p01: P, p10: P, p11: P) -> W:
  P{+h00, +x0} = p00
  P{+h01, +l01} = p01
  P{+h10, +l10} = p10
  P{+h11, +l11} = p11
  +s1a = U32.add(h00, l01)
  +c1a = carry(h00, s1a)
  +x1 = U32.add(s1a, l10)
  +c1b = carry(s1a, x1)
  +s2a = U32.add(h01, h10)
  +c2a = carry(h01, s2a)
  +s2b = U32.add(s2a, l11)
  +c2b = carry(s2a, s2b)
  +cc = U32.add(c1a, c1b)
  +x2 = U32.add(s2b, cc)
  +c2c = carry(s2b, x2)
  +x3 = U32.add(U32.add(h11, c2a), U32.add(c2b, c2c))
  W{x3, x2, x1, x0}

def Gl.wide(+a1: U32, +a0: U32, +b1: U32, +b0: U32) -> W:
  Gl.wide.join(mul32(a0, b0), mul32(a0, b1), mul32(a1, b0), mul32(a1, b1))

def Gl.mul(+a1: U32, +a0: U32, +b1: U32, +b0: U32) -> Gl:
  +x0 = U32.mul(a0, b0)
  +h00 = mulhi(a0, b0)
  +l01 = U32.mul(a0, b1)
  +h01 = mulhi(a0, b1)
  +l10 = U32.mul(a1, b0)
  +h10 = mulhi(a1, b0)
  +l11 = U32.mul(a1, b1)
  +h11 = mulhi(a1, b1)
  +s1a = U32.add(h00, l01)
  +c1a = carry(h00, s1a)
  +x1 = U32.add(s1a, l10)
  +c1b = carry(s1a, x1)
  +s2a = U32.add(h01, h10)
  +c2a = carry(h01, s2a)
  +s2b = U32.add(s2a, l11)
  +c2b = carry(s2a, s2b)
  +cc = U32.add(c1a, c1b)
  +x2 = U32.add(s2b, cc)
  +c2c = carry(s2b, x2)
  +x3 = U32.add(U32.add(h11, c2a), U32.add(c2b, c2c))
  Gl.reduce(x3, x2, x1, x0)

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
