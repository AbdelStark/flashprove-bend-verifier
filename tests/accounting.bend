import Base
import ../src/accounting.bend as A
import ../src/accounting_catalog.bend as C
import ../src/plan_types.bend as P

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Bool.show(A.admitted(C.stages(P.FullClipped{}))))
    IO.print(Bool.show(A.bound(C.Bound{20n,140n,[0,1]},128n)))
    IO.print(Bool.show(A.bound(C.Bound{20n,140n,[1,1]},128n)))
    IO.print(Bool.show(A.bound(C.Bound{20n,140n,[4294967295]},128n)))
    IO.print(Bool.show(A.bound(C.Bound{33n,140n,[1]},128n)))
    IO.print(Bool.show(A.bound(C.Bound{0n,127n,[1]},128n)))
#|True
#|True
#|False
#|True
#|False
#|False
