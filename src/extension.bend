import Base
import ./goldilocks.bend as Field

# Coefficients of 1, X, X^2 in F_p[X]/(X^3 - 2), each in high/low limb order.
type E3 is Data:
  E3{c0h: U32, c0l: U32, c1h: U32, c1l: U32, c2h: U32, c2l: U32}

def add(a: Field.Gl, b: Field.Gl) -> Field.Gl:
  Field.Gl{+ah, +al} = a
  Field.Gl{+bh, +bl} = b
  +lo = U32.add(al, bl)
  +c = Field.carry(al, bl, lo)
  +h = U32.add(ah, bh)
  +hi = U32.add(h, c)
  +overflow = U32.or(Field.carry(ah, bh, h), Field.carry(h, c, hi))
  Field.Gl.reduce(0, overflow, hi, lo)

def product(a: Field.Gl, b: Field.Gl) -> Field.Gl:
  Field.Gl{ah, al} = a
  Field.Gl{bh, bl} = b
  Field.Gl.mul(ah, al, bh, bl)

def pack(c0: Field.Gl, c1: Field.Gl, c2: Field.Gl) -> E3:
  Field.Gl{c0h, c0l} = c0
  Field.Gl{c1h, c1l} = c1
  Field.Gl{c2h, c2l} = c2
  E3{c0h, c0l, c1h, c1l, c2h, c2l}

def E3.mul(a0h: U32, a0l: U32, a1h: U32, a1l: U32, a2h: U32, a2l: U32, b0h: U32, b0l: U32, b1h: U32, b1l: U32, b2h: U32, b2l: U32) -> E3:
  +a0: Field.Gl = Field.Gl{a0h, a0l}
  +a1: Field.Gl = Field.Gl{a1h, a1l}
  +a2: Field.Gl = Field.Gl{a2h, a2l}
  +b0: Field.Gl = Field.Gl{b0h, b0l}
  +b1: Field.Gl = Field.Gl{b1h, b1l}
  +b2: Field.Gl = Field.Gl{b2h, b2l}
  +d1 = add(b1, b1)
  +d2 = add(b2, b2)
  # Multiplication followed by replacing X^3 with 2 and X^4 with 2X.
  c0 = add(add(product(a0, b0), product(a1, d2)), product(a2, d1))
  c1 = add(add(product(a0, b1), product(a1, b0)), product(a2, d2))
  c2 = add(add(product(a0, b2), product(a1, b1)), product(a2, b0))
  pack(c0, c1, c2)
