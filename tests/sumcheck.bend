import Base
import ../src/extension.bend as Ext
import ../src/sumcheck.bend as Psc

def show(value: Ext.E3) -> String:
  Ext.E3{a,b,c,d,e,f} = value
  U32.show(a) ++ " " ++ U32.show(b) ++ " " ++ U32.show(c) ++ " " ++ U32.show(d) ++ " " ++ U32.show(e) ++ " " ++ U32.show(f)

# q(T) = q0 + q1 T + q2 T^2, with coefficients in F[X]/(X^3 - 2).
# Plain weights (2,1,1) fix q1; equality weights (1,X,X) fix q0.
def main() -> IO(Unit):
  do IO<Unit>:
    +zero: Ext.E3 = Ext.E3{0,0,0,0,0,0}
    +one: Ext.E3 = Ext.E3{0,1,0,0,0,0}
    two: Ext.E3 = Ext.E3{0,2,0,0,0,0}
    +x: Ext.E3 = Ext.E3{0,0,0,1,0,0}
    +q0: Ext.E3 = Ext.E3{0,1,0,2,0,3}
    +q1: Ext.E3 = Ext.E3{4294967295,0,0,4,0,1}
    +q2: Ext.E3 = Ext.E3{0,0,0,1,0,2}
    plain_claim: Ext.E3 = Ext.E3{0,1,0,9,0,9}
    IO.print(show(Psc.known(Psc.known(plain_claim, two, q0), one, q2)))
    equality_claim: Ext.E3 = Ext.E3{0,7,0,1,0,8}
    IO.print(show(Psc.known(Psc.known(equality_claim, x, q1), x, q2)))
    IO.print(show(Psc.horner(Psc.horner(Psc.horner(zero, x, q2), x, q1), x, q0)))
    IO.print(show(Psc.known(zero, zero, one)))
#|4294967295 0 0 4 0 1
#|0 1 0 2 0 3
#|0 5 0 5 0 7
#|0 0 0 0 0 0
