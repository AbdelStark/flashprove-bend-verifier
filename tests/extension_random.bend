import Base
import ../src/extension.bend as Ext
import ../src/goldilocks.bend as Field

# 10,000 pseudo-random products in F_p[X]/(X^3 - 2), folded into one checksum. The operands
# come from xorshift32; three bits per coefficient force the edge shapes 0, 1, p - 1, the
# largest value under the top high limb, and a zero high limb, so both base-field fast paths
# and the single-reduction path with a fifth limb are exercised. The expected line is what
# tests/extension_random.py computes with Python integers.

def next(+s: U32) -> U32:
  +a = U32.xor(s, U32.shln(s, 13n))
  +b = U32.xor(a, U32.shrn(a, 17n))
  U32.xor(b, U32.shln(b, 5n))

# A random pair of limbs, with the low limb cleared where the pair is not below p.
def canon(+h: U32, +l: U32) -> Field.Gl:
  +over = Bool.to_u32(Bool.and(U32.is_eq(h, 4294967295), U32.is_ne(l, 0)))
  Field.Gl{h, U32.and(l, U32.sub(over, 1))}

def shape(+k: U32, +h: U32, +l: U32) -> Field.Gl:
  Bool.pick(Field.Gl, U32.is_eq(k, 1), Field.Gl{0, 0},
    Bool.pick(Field.Gl, U32.is_eq(k, 2), Field.Gl{0, 1},
      Bool.pick(Field.Gl, U32.is_eq(k, 3), Field.Gl{4294967295, 0},
        Bool.pick(Field.Gl, U32.is_eq(k, 4), Field.Gl{4294967294, 4294967295},
          Bool.pick(Field.Gl, U32.is_eq(k, 5), Field.Gl{0, l}, canon(h, l))))))

def bits(+w: U32, at: Nat) -> U32:
  U32.and(U32.shrn(w, at), 7)

def product(x0: Field.Gl, x1: Field.Gl, x2: Field.Gl, y0: Field.Gl, y1: Field.Gl, y2: Field.Gl) -> Ext.E3:
  Field.Gl{a, b} = x0
  Field.Gl{c, d} = x1
  Field.Gl{e, f} = x2
  Field.Gl{g, h} = y0
  Field.Gl{i, j} = y1
  Field.Gl{k, l} = y2
  Ext.E3.mul(a, b, c, d, e, f, g, h, i, j, k, l)

def mixin(acc: U32, x: U32) -> U32:
  U32.add(U32.mul(acc, 31), x)

def fold(r: Ext.E3, acc: U32) -> U32:
  Ext.E3{a, b, c, d, e, f} = r
  mixin(mixin(mixin(mixin(mixin(mixin(acc, a), b), c), d), e), f)

def run(n: Nat, +s: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      +s1 = next(s)
      +s2 = next(s1)
      +s3 = next(s2)
      +s4 = next(s3)
      +s5 = next(s4)
      +s6 = next(s5)
      +s7 = next(s6)
      +s8 = next(s7)
      +s9 = next(s8)
      +s10 = next(s9)
      +s11 = next(s10)
      +s12 = next(s11)
      +w = next(s12)
      r = product(shape(bits(w, 0n), s1, s2), shape(bits(w, 3n), s3, s4), shape(bits(w, 6n), s5, s6),
        shape(bits(w, 9n), s7, s8), shape(bits(w, 12n), s9, s10), shape(bits(w, 15n), s11, s12))
      run(m, w, fold(r, acc))

def main() -> IO(Unit):
  IO.print(U32.show(run(10000n, 2463534242, 0)))

#|2624099612
