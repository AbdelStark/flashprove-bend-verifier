import Base
import ./extension.bend as Ext
import ./goldilocks.bend as Field

def mul(a: Ext.E3, b: Ext.E3) -> Ext.E3:
  Ext.E3{x0, x1, x2, x3, x4, x5} = a
  Ext.E3{y0, y1, y2, y3, y4, y5} = b
  Ext.E3.mul(x0, x1, x2, x3, x4, x5, y0, y1, y2, y3, y4, y5)

def add(a: Ext.E3, b: Ext.E3) -> Ext.E3:
  Ext.E3{x0, x1, x2, x3, x4, x5} = a
  Ext.E3{y0, y1, y2, y3, y4, y5} = b
  Ext.pack(Ext.add(Field.Gl{x0, x1}, Field.Gl{y0, y1}), Ext.add(Field.Gl{x2, x3}, Field.Gl{y2, y3}), Ext.add(Field.Gl{x4, x5}, Field.Gl{y4, y5}))

# Returns p - b, including the word p for zero; Ext.add reduces the sum.
def negative(+bh: U32, +bl: U32) -> Field.Gl:
  +lo = U32.sub(1, bl)
  hi = U32.sub(U32.sub(4294967295, bh), Field.borrow(1, bl))
  Field.Gl{hi, lo}

def negate(b: Ext.E3) -> Ext.E3:
  Ext.E3{y0, y1, y2, y3, y4, y5} = b
  Ext.pack(negative(y0, y1), negative(y2, y3), negative(y4, y5))

# PSC's running residual starts at the incoming claim. Each sent coefficient
# removes moment[t] * q[t]; scaling the residual by fixed_inv recovers q[fixed].
def known(residual: Ext.E3, moment: Ext.E3, coefficient: Ext.E3) -> Ext.E3:
  add(residual, negate(mul(moment, coefficient)))

# Horner evaluation after challenge sampling, traversing completed q backwards.
def horner(value: Ext.E3, challenge: Ext.E3, coefficient: Ext.E3) -> Ext.E3:
  add(mul(value, challenge), coefficient)
