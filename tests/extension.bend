import Base
import ../src/extension.bend as Ext
import ../src/goldilocks.bend as Field

def show(value: Ext.E3) -> String:
  Ext.E3{a, b, c, d, e, f} = value
  U32.show(a) ++ " " ++ U32.show(b) ++ " " ++ U32.show(c) ++ " " ++ U32.show(d) ++ " " ++ U32.show(e) ++ " " ++ U32.show(f)

def limbs(value: Field.Gl) -> String:
  Field.Gl{hi, lo} = value
  U32.show(hi) ++ " " ++ U32.show(lo)

# Expected products use schoolbook polynomial multiplication modulo X^3 - 2 and p.
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show(Ext.E3.mul(0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1)))
    IO.print(show(Ext.E3.mul(0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1)))
    IO.print(show(Ext.E3.mul(4294967295, 0, 4294967295, 0, 4294967295, 0, 4294967295, 0, 4294967295, 0, 4294967295, 0)))
    IO.print(show(Ext.E3.mul(0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6)))
    IO.print(show(Ext.E3.mul(4294967295, 0, 4294967294, 4294967295, 4294967294, 4294967294, 4294967294, 4294967293, 4294967294, 4294967292, 4294967294, 4294967291)))
    IO.print(show(Ext.E3.mul(0, 0, 0, 0, 0, 0, 4294967295, 0, 4294967295, 0, 4294967295, 0)))
    IO.print(show(Ext.E3.mul(2616525818, 2952618119, 1109109337, 1539779615, 507698712, 958177034, 3866634704, 1693497972, 1153488315, 4161179334, 941894787, 1199539299)))
    # ((2^32 - 1) + 2 * 2^128) mod p = (2^32 - 2) * 2^32.
    # Correcting the high-limb borrow also wraps the low limb.
    IO.print(limbs(Field.Gl.lower(Field.Gl{0, 4294967295}, 2)))
    # Direct 128-bit reduction vectors span the signed carry cases of
    # x0 - x2 - x3 + 2^32 * (x1 + x2). Expected limbs are divmod(X % p, 2^32).
    IO.print(limbs(Field.Gl.reduce(4294967295, 0, 0, 4294967294)))
    IO.print(limbs(Field.Gl.reduce(0, 0, 4294967295, 1)))
    IO.print(limbs(Field.Gl.reduce(0, 4294967295, 4294967295, 4294967295)))
    IO.print(limbs(Field.Gl.reduce(4294967295, 4294967295, 4294967295, 4294967295)))
    # floor((2^32 - 1)^2 / 2^32) exercises the maximum 48-bit partial sum.
    IO.print(U32.show(Field.mulhi(4294967295, 4294967295)))
    # Adding two raw 64-bit words still reduces at the second multiple of p.
    IO.print(limbs(Ext.add(Field.Gl{4294967295, 4294967295}, Field.Gl{4294967295, 4294967295})))

#|0 2 0 0 0 0
#|0 0 0 2 0 0
#|0 5 0 4 0 3
#|0 58 0 49 0 28
#|0 58 0 49 0 28
#|0 0 0 0 0 0
#|2822347717 1272377527 3139375100 2795758142 971541336 761933512
#|4294967294 0
#|4294967295 0
#|0 0
#|4294967294 4294967295
#|4294967294 0
#|4294967294
#|1 4294967292
