import Base
import ../src/base_check.bend as B
import ../src/extension.bend as E
import ../src/fold.bend as F
import ../src/fold_cs.bend as CS
import ../src/lin_own.bend as Own
import ../src/row_tensor.bend as X

def same(xs: B.Elements, ys: B.Elements) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case Con{x,a} Con{y,b}: B.equal(x,y) && same(a,b)
    case _ _: False{}

def weights(+n: Nat) -> F.Form:
  +z: E.E3 = E.E3{0,7,0,11,0,13}
  fs = X.eq(List.take(&2,E.E3,[z,F.zero(),F.one(),z,z,z],n))
  [F.Term{z,fs},F.Term{F.one(),X.choice(n,5n)},F.Term{F.zero(),X.choice(n,0n)}]

# A dense Boolean table is an independent evaluator for the original placed
# weights. Include both hiding scales, on opposite sides of the code switch.
def folded(form: F.Form, +gs: B.Elements, +eps: E.E3) -> B.Elements:
  dense = F.expand_list(form,CS.zeros(32n))
  first = F.scaled(F.fold_low(List.take(&2,E.E3,gs,2n),dense),eps)
  F.fold_low(List.drop(&2,E.E3,gs,2n),F.scaled(first,E.E3{0,3,0,2,0,1}))

def same_width(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def check(+ws: F.Form, +rows: Nat, +places: Nat, +k: Nat, +off: Nat, n: Nat, +gs: B.Elements, +eps: E.E3) -> Bool:
  +direct = Own.table(ws,rows,places,k,off)
  +compact = Own.weight_table(ws,rows,places,k,off,gs,n)
  same_width(F.fits(direct,5n),F.fits(compact,5n)) &&
    same(folded(direct,gs,eps),folded(compact,gs,eps))

def cases(n: Nat, +gs: B.Elements) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +w = k
      +ws = weights(w)
      check(ws,3n,4n,3n,0n,1n,gs,F.zero()) && check(ws,3n,4n,3n,0n,1n,gs,F.one()) &&
        check(ws,3n,4n,3n,4n,1n,gs,E.E3{0,5,0,11,0,3}) && cases(w,gs)

def main() -> IO(Unit):
  +x: E.E3 = E.E3{0,5,0,2,0,19}
  # Four gammas exercise contraction, three force the original shape path.
  IO.print(Bool.show(cases(7n,[F.zero(),F.one(),x,F.zero()]) &&
    cases(7n,[x,F.zero(),F.one(),x]) && cases(7n,[F.one(),x,F.one()]) &&
    check(weights(4n),1n,16n,1n,1n,3n,[x,F.one()],F.one()) &&
    check(weights(5n),5n,4n,3n,0n,2n,[F.zero(),x,F.one()],x) &&
    check(weights(4n),3n,4n,3n,4n,0n,[x,F.zero(),x,F.one(),x],F.one())))

#|True
