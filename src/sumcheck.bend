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

# Negation also feeds exported targets and direct equality checks, which require canonical zero.
def negative(+bh: U32, +bl: U32) -> Field.Gl:
  lo = U32.sub(1, bl)
  hi = U32.sub(U32.sub(4294967295, bh), Field.borrow(1, bl))
  # Keep this kernel unboxed for the legacy worker's allocation-free C ABI.
  +mask = U32.sub(0,Field.borrow(0,U32.or(bh,bl)))
  Field.Gl{U32.and(hi,mask),U32.and(lo,mask)}

def negate(b: Ext.E3) -> Ext.E3:
  Ext.E3{y0, y1, y2, y3, y4, y5} = b
  Ext.pack(negative(y0, y1), negative(y2, y3), negative(y4, y5))

# A multiplier that is one or minus one needs no product. unit(s) is 1 for
# one, 2 for minus one and 0 otherwise; by(unit(s),s,w) equals mul(s,w).
def unit(s: Ext.E3) -> U32:
  Ext.E3{a, b, c, d, e, f} = s
  +rest = U32.is_zero(U32.or(U32.or(c, d), U32.or(e, f)))
  +h = a
  +l = b
  U32.add(Bool.to_u32(rest && U32.is_eq(h, 0) && U32.is_eq(l, 1)), U32.mul(2, Bool.to_u32(rest && U32.is_eq(h, 4294967295) && U32.is_eq(l, 0))))

def by(mode: U32, +s: Ext.E3, w: Ext.E3) -> Ext.E3:
  match mode:
    case 1: w
    case 2: negate(w)
    case _: mul(s, w)

# PSC's running residual starts at the incoming claim. Each sent coefficient
# removes moment[t] * q[t]; scaling the residual by fixed_inv recovers q[fixed].
def known(residual: Ext.E3, moment: Ext.E3, coefficient: Ext.E3) -> Ext.E3:
  add(residual, negate(mul(moment, coefficient)))

# Horner evaluation after challenge sampling, traversing completed q backwards.
def horner(value: Ext.E3, challenge: Ext.E3, coefficient: Ext.E3) -> Ext.E3:
  add(mul(value, challenge), coefficient)
