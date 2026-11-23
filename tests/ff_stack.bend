import Base
import ../src/ff_stack.bend as S
import ../src/ff_stack_panels.bend as P
import ../src/base_check.bend as B
import ../src/fold.bend as F
import ../src/extension.bend as X
import ../src/sumcheck.bend as E

# R11.2 step 11. The inverse of the token sumcheck epsilon recovers KT.
# Panel bases follow decreasing size with the original order breaking ties.
def main() -> IO(Unit):
  +v : X.E3 = X.E3{0,3,0,5,0,7}
  +panels : P.Panels = [P.Panel{P.Spec{0n,0n},0n,2n,4n,3n,2n,0n},
    P.Panel{P.Spec{1n,0n},2n,2n,16n,5n,4n,1n},P.Panel{P.Spec{2n,0n},4n,2n,4n,3n,2n,2n}]
  do IO<Unit>:
    IO.print(Bool.show(B.equal(E.mul(v,S.inverse(v)),F.one())))
    IO.print(Bool.show(B.equal(E.mul(v,S.inverse(F.one())),F.one())))
    IO.print(Nat.show(P.offset(panels,5n,1n,0n)))
    IO.print(Nat.show(P.offset(panels,3n,0n,0n)))
    IO.print(Nat.show(P.offset(panels,3n,2n,0n)))
#|True
#|False
#|0
#|32
#|40
