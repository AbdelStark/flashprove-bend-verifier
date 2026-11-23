import Base
import ../src/extension.bend as X
import ../src/fold.bend as F
import ../src/base_check.bend as B
import ../src/sumcheck.bend as E
import ../src/row_tensor.bend as V
import ../src/smallness_packing.bend as P

def eval(xs: F.Form, +i: Nat, acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case F.Term{p,fs} <> tail: eval(tail,i,E.add(acc,V.entry(fs,i,p)))

def test(n: Nat, +u: X.E3, +ts: F.Form, sum: X.E3) -> Bool:
  match n:
    case 0n: B.equal(sum,P.total(97n,u))
    case 1n+k:
      +i = k
      +got = eval(ts,i,F.zero())
      B.equal(got,P.three(i,u)) && test(i,u,ts,E.add(sum,got))

def main() -> IO(Unit):
  +u: X.E3 = X.E3{0,91,0,143,0,587}
  do IO<Unit>:
    terms : F.Form <- P.left(7n,u)
    IO.print(Bool.show(test(97n,u,terms,F.zero())))

#|True
