import Base
import ../src/fold_batt.bend as Bat
import ../src/fold_frame.bend as R
import ../src/lin_own.bend as Own
import ../src/key_stage_batt.bend as Key
import ../src/key_stage_lookup_rows.bend as L
import ../src/fold.bend as F
import ../src/base_check.bend as B
import ../src/extension.bend as E

# Two one-column records as in blocks/iop/batt.h. At gamma=3, chi_0=-2 and chi_1=3.
def e(n: U32) -> E.E3: E.E3{0,n,0,0,0,0}

def records() -> Bat.Pending:
  [Own.Pending{[F.Term{e(2),[]}],[e(0)],[Own.Slot{0n,e(7)}],e(13)},
   Own.Pending{[F.Term{e(4),[]}],[e(1)],[Own.Slot{1n,e(11)}],e(17)}]

def target(sum: Key.Combined) -> Bool:
  match sum:
    case Key.Combined{[L.Mask{L.IndexMask{},1n,b},L.Mask{L.IndexMask{},0n,a}],t}:
      B.equal(a,e(7)) && B.equal(b,e(55)) && B.equal(t,e(98))
    case _: False{}

def weights(+theta: E.E3) -> Bool:
  fs = Bat.weights(records(),[e(3)],theta,e(7),[])
  B.equal(R.weight(fs,0n,F.zero()),e(392))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Bool.show(target(Bat.merge(records(),e(5),F.one(),[],F.zero()))))
    IO.print(Bool.show(weights(e(5))))
    IO.print(Bool.show(weights(e(4))))
    IO.print(Bool.show(Bat.point_sizes(records(),2n,True{})))
#|True
#|True
#|False
#|False
