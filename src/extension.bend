import Base
import ./goldilocks.bend as Field

# Coefficients of 1, X, X^2 in F_p[X]/(X^3 - 2), each in high/low limb order.
type E3 is Data:
  E3{c0h: U32, c0l: U32, c1h: U32, c1l: U32, c2h: U32, c2l: U32}

def add(a: Field.Gl, b: Field.Gl) -> Field.Gl:
  Field.Gl{+ah, +al} = a
  Field.Gl{+bh, +bl} = b
  +low = Nat.add(U32.to_nat(al), U32.to_nat(bl))
  +high = Nat.add(Nat.add(U32.to_nat(ah), U32.to_nat(bh)), Field.high_word(low))
  +lo = U32.from_nat(low)
  +hi = U32.from_nat(high)
  # (high, lo) reaches p at (q - 1, 1), where q = 2^32. It can only
  # reach 2p for noncanonical operands. Preserve reduction there as well.
  first = Bool.or(Nat.is_ge(high, Field.radix()), Bool.and(U32.is_eq(hi, 4294967295), U32.is_ne(lo, 0)))
  +twice_high = Nat.add(Field.radix(), 4294967294n)
  second = Bool.or(Nat.is_gt(high, twice_high), Bool.and(Nat.is_eq(high, twice_high), U32.is_ge(lo, 2)))
  +k = U32.add(Bool.to_u32(first), Bool.to_u32(second))
  Field.Gl{U32.sub(U32.add(hi, k), Field.borrow(lo, k)), U32.sub(lo, k)}

def product(a: Field.Gl, b: Field.Gl) -> Field.Gl:
  Field.Gl{ah, al} = a
  Field.Gl{bh, bl} = b
  Field.Gl.mul(ah, al, bh, bl)

def pack(c0: Field.Gl, c1: Field.Gl, c2: Field.Gl) -> E3:
  Field.Gl{c0h, c0l} = c0
  Field.Gl{c1h, c1l} = c1
  Field.Gl{c2h, c2l} = c2
  E3{c0h, c0l, c1h, c1l, c2h, c2l}

# p + q + r for three 128-bit products, reduced once. The sum is below 3 * 2^128, so its fifth limb is at most 2.
def sum3(p: Field.W, q: Field.W, r: Field.W) -> Field.Gl:
  Field.W{+p3, +p2, +p1, +p0} = p
  Field.W{+q3, +q2, +q1, +q0} = q
  Field.W{+r3, +r2, +r1, +r0} = r
  +s0 = Field.column(p0, q0, r0, 0n)
  +s1 = Field.column(p1, q1, r1, Field.high_word(s0))
  +s2 = Field.column(p2, q2, r2, Field.high_word(s1))
  +s3 = Field.column(p3, q3, r3, Field.high_word(s2))
  value = Field.Gl.reduce(U32.from_nat(s3), U32.from_nat(s2), U32.from_nat(s1), U32.from_nat(s0))
  Field.Gl.lower(value, U32.from_nat(Field.high_word(s3)))

# Schoolbook product with X^3 replaced by 2: d1 and d2 are 2 b1 and 2 b2. Each coefficient
# sums its three 128-bit products before one reduction.
def E3.mul.go(d1: Field.Gl, d2: Field.Gl, +a0h: U32, +a0l: U32, +a1h: U32, +a1l: U32, +a2h: U32, +a2l: U32, +b0h: U32, +b0l: U32, +b1h: U32, +b1l: U32, +b2h: U32, +b2l: U32) -> E3:
  Field.Gl{+d1h, +d1l} = d1
  Field.Gl{+d2h, +d2l} = d2
  c0 = sum3(Field.Gl.wide(a0h, a0l, b0h, b0l), Field.Gl.wide(a1h, a1l, d2h, d2l), Field.Gl.wide(a2h, a2l, d1h, d1l))
  c1 = sum3(Field.Gl.wide(a0h, a0l, b1h, b1l), Field.Gl.wide(a1h, a1l, b0h, b0l), Field.Gl.wide(a2h, a2l, d2h, d2l))
  c2 = sum3(Field.Gl.wide(a0h, a0l, b2h, b2l), Field.Gl.wide(a1h, a1l, b1h, b1l), Field.Gl.wide(a2h, a2l, b0h, b0l))
  pack(c0, c1, c2)

# Product by an element of the base field: three base products.
def E3.scale(+x0h: U32, +x0l: U32, +x1h: U32, +x1l: U32, +x2h: U32, +x2l: U32, +sh: U32, +sl: U32) -> E3:
  pack(Field.Gl.mul(x0h, x0l, sh, sl), Field.Gl.mul(x1h, x1l, sh, sl), Field.Gl.mul(x2h, x2l, sh, sl))

def E3.mul.pick(plain_b: Bool, plain_a: Bool, +a0h: U32, +a0l: U32, +a1h: U32, +a1l: U32, +a2h: U32, +a2l: U32, +b0h: U32, +b0l: U32, +b1h: U32, +b1l: U32, +b2h: U32, +b2l: U32) -> E3:
  match plain_b plain_a:
    case True{} _: E3.scale(a0h, a0l, a1h, a1l, a2h, a2l, b0h, b0l)
    case False{} True{}: E3.scale(b0h, b0l, b1h, b1l, b2h, b2l, a0h, a0l)
    case False{} False{}: E3.mul.go(Field.Gl.double(b1h, b1l), Field.Gl.double(b2h, b2l), a0h, a0l, a1h, a1l, a2h, a2l, b0h, b0l, b1h, b1l, b2h, b2l)

# An operand whose X and X^2 coefficients are zero lies in the base field.
def E3.mul(+a0h: U32, +a0l: U32, +a1h: U32, +a1l: U32, +a2h: U32, +a2l: U32, +b0h: U32, +b0l: U32, +b1h: U32, +b1l: U32, +b2h: U32, +b2l: U32) -> E3:
  E3.mul.pick(U32.is_zero(U32.or(U32.or(b1h, b1l), U32.or(b2h, b2l))), U32.is_zero(U32.or(U32.or(a1h, a1l), U32.or(a2h, a2l))), a0h, a0l, a1h, a1l, a2h, a2l, b0h, b0l, b1h, b1l, b2h, b2l)
