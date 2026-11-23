import Base
import ../src/fold_carry.bend as C
import ../src/fold_frame.bend as R
import ../src/fold.bend as F
import ../src/fold_cs.bend as S
import ../src/row_tensor.bend as X
import ../src/base_check.bend as B
import ../src/extension.bend as E
import ../src/sumcheck.bend as A

# R12.16 and Cs.switchParts/switchAddKept at the pinned revision. Two extension carrier rows,
# three kept F rows. The carried rest holds two mask messages, the three kinds of tails
# and the three old F-pad entries. The replacement's pad can change independently.
def e(x: Nat) -> E.E3: E.E3{0,U32.from_nat(x),0,0,0,0}
def flat(bits: Nat,w: Nat) -> F.Form:
  [F.Term{e(w),List.replicate(F.Factor,bits,F.Factor{F.one(),F.one()})}]
def keep() -> C.Kept: C.Kept{1n,10n,3n,1n,flat(8n,1n),e(8160n)}
def closed() -> R.Closed:
  R.Closed{F.Single{flat(6n,1n),[e(1n),e(1n),e(1n),e(1n)],[e(2n),e(2n),e(2n),e(2n)],e(18458n)},[R.On{1n,False{},flat(8n,2n)}]}
def rest() -> B.Elements: [E.E3{0,2,0,0,0,0},E.E3{0,3,0,0,0,0},E.E3{0,4,0,0,0,0},E.E3{0,5,0,0,0,0},E.E3{0,1,0,0,0,0},E.E3{0,4,0,0,0,0},E.E3{0,7,0,0,0,0},E.E3{0,10,0,0,0,0},E.E3{0,6,0,0,0,0},E.E3{0,9,0,0,0,0},E.E3{0,2,0,0,0,0},E.E3{0,3,0,0,0,0},E.E3{0,12,0,0,0,0},E.E3{0,13,0,0,0,0},E.E3{0,22,0,0,0,0},E.E3{0,23,0,0,0,0},E.E3{0,3,0,0,0,0},E.E3{0,5,0,0,0,0},E.E3{0,7,0,0,0,0},E.E3{0,11,0,0,0,0},E.E3{0,82,0,0,0,0},E.E3{0,83,0,0,0,0},E.E3{0,84,0,0,0,0}]
def carrier(+i: Nat, +alter: Bool) -> E.E3:
  +pos = Nat.div(i,2n)
  original = Maybe.default(&2,E.E3,List.get(&2,E.E3,rest(),pos),e(0n))
  odd = Bool.pick(E.E3,alter && Nat.is_eq(pos,20n),e(999n),original)
  Bool.pick(E.E3,Nat.is_eq(Nat.mod(i,2n),0n),e(1n+pos),odd)
def replaced(+i: Nat, +newpad: Nat) -> E.E3:
  +j = Nat.mod(i,4n)
  +pos = Nat.div(i,4n)
  +v = Nat.add(1n+pos,Nat.mul(10n,j))
  valid = Bool.pick(Nat,Nat.is_eq(j,2n) && Nat.is_le(61n,pos),newpad,v)
  e(Bool.pick(Nat,Nat.is_lt(j,3n),valid,0n))
def inner(n: Nat, +f: F.Form, +g: Bool, +alt: Bool, +pad: Nat, sum: E.E3) -> E.E3:
  match n:
    case 0n: sum
    case 1n+left:
      +i = left
      v = Bool.pick(E.E3,g,carrier(i,alt),replaced(i,pad))
      inner(i,f,g,alt,pad,B.masked(sum,v,R.weight(f,i,F.zero())))
def total(xs: R.Forms, +alt: Bool, +pad: Nat, acc: E.E3) -> E.E3:
  match xs:
    case []: acc
    case R.On{+id,_,f} <> tail:
      +g = Nat.is_eq(id,9n)
      total(tail,alt,pad,inner(Bool.pick(Nat,g,128n,256n),f,g,alt,pad,acc))
def valid(xs: List<&2,R.Equation>, +alt: Bool, +pad: Nat) -> Bool:
  match xs:
    case []: True{}
    case R.Equation{fs,t} <> tail: B.equal(total(fs,alt,pad,F.zero()),t) && valid(tail,alt,pad)
def equations(sw: Maybe<&2,C.Switch>) -> Maybe<&2,C.Equations>:
  match sw:
    case None{}: None{}
    case Some{s}: C.switch(s,closed(),[C.Opening{S.Draw{17n,E.E3{1846792359,1299247516,0,0,0,0},E.E3{4294967294,4294891903,0,0,0,0},E.E3{4294967294,4294814641,0,0,0,0}},[E.E3{1846792359,1299250200,0,0,0,0},E.E3{657057041,3061244955,0,0,0,0},E.E3{3762289019,528272415,0,0,0,0}]},C.Opening{S.Draw{1n,E.E3{2794890977,2155141341,0,0,0,0},E.E3{4294967294,4294891903,0,0,0,0},E.E3{4294967294,4294814641,0,0,0,0}},[E.E3{2794890977,2155141379,0,0,0,0},E.E3{2334910037,942358460,0,0,0,0},E.E3{1874929096,4024542837,0,0,0,0}]},C.Opening{S.Draw{17n,E.E3{1846792359,1299247516,0,0,0,0},E.E3{4294967294,4294891903,0,0,0,0},E.E3{4294967294,4294814641,0,0,0,0}},[E.E3{1846792359,1299250200,0,0,0,0},E.E3{657057041,3061244955,0,0,0,0},E.E3{3762289019,528272415,0,0,0,0}]}])
def audit(eq: Maybe<&2,C.Equations>) -> IO(Unit):
  match eq:
    case None{}: IO.print("shape mismatch")
    case Some{C.Equations{+ps,+gs}}:
      +both = List.append(&2,R.Equation,ps,gs)
      do IO<Unit>:
        IO.print(Nat.show(List.length(&2,R.Equation,ps)) ++ "/" ++ Nat.show(List.length(&2,R.Equation,gs)))
        IO.print(Bool.show(valid(both,False{},71n)))
        IO.print(Bool.show(valid(both,False{},500n)))
        IO.print(Bool.show(valid(both,True{},71n)))
def main() -> IO(Unit):
  audit(equations(C.frame(9n,B.Code{7n,64n,2n},B.Code{4n,4n,2n},[keep()])))
#|2/18
#|True
#|True
#|False
