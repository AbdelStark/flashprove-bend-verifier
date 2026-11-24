import Base
import ../../../src/fold.bend as F
import ../../../src/lin_own.bend as L
import ../../../src/row_tensor.bend as X

# Time the LIN row permutation alone. Keep 4,096 independent terms live and
# consume every output list cell. The total includes constructing the inputs
# once and constructing and traversing the layout twenty times.
def inputs(n: Nat, acc: F.Form) -> F.Form:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      width = Nat.add(12n,Nat.mod(i,12n))
      inputs(i,F.Term{F.one(),X.choice(width,i)} <> acc)

def widths(terms: F.Form, acc: Nat) -> Nat:
  match terms:
    case []: acc
    case F.Term{_,fs} <> rest: widths(rest,Nat.add(acc,List.length(&2,F.Factor,fs)))

def run(n: Nat, +terms: F.Form, acc: Nat) -> Nat:
  match n:
    case 0n: acc
    case 1n+k: run(k,terms,Nat.add(acc,widths(L.table(terms,8192n,1024n,15n,8192n),0n)))

def main() -> IO(Unit):
  IO.print(Nat.show(run(20n,inputs(4096n,[]),0n)))
