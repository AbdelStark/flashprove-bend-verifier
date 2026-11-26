import Base
import ../src/fold.bend as F
import ../src/sumcheck.bend as E
import ../src/extension.bend as X
import ../src/base_check.bend as B
import ../src/row_tensor.bend as T

def e(x:U32) -> X.E3: X.E3{0,x,0,0,0,0}
def same(xs:B.Elements,ys:B.Elements) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case Con{x,tail} Con{y,more}: B.equal(x,y) && same(tail,more)
    case _ _: False{}

def zeros(n: Nat) -> B.Elements: List.replicate(X.E3,n,F.zero())

# Equality factors {1-x,x} with cubic x, {1,x} factors, zero endpoints on
# either side and Boolean selectors, against the list expansion.
def scatter() -> F.Form:
  +x: X.E3 = X.E3{0,7,0,3,0,11}
  +y: X.E3 = X.E3{5,1,0,0,9,2}
  [F.Term{X.E3{0,3,1,4,0,2},T.eq([x,y,x,y])},
   F.Term{y,[F.Factor{F.one(),x},F.Low{},F.Factor{F.sub(F.one(),y),y},F.High{}]},
   F.Term{x,[F.Factor{F.zero(),y},F.Factor{x,F.zero()},F.Factor{F.one(),F.zero()},F.Factor{F.zero(),F.one()}]},
   F.Term{e(9),[F.Factor{F.one(),F.one()},F.Factor{x,y},F.Factor{F.sub(F.one(),x),x},F.Factor{y,x}]}]

# Seven general bits take the dense in-place path; the Boolean term does not.
def wide() -> F.Form:
  +x: X.E3 = X.E3{0,7,0,3,0,11}
  +y: X.E3 = X.E3{5,1,0,0,9,2}
  +z: X.E3 = X.E3{0,2,8,0,0,1}
  [F.Term{X.E3{0,3,1,4,0,2},T.eq([x,y,z,x,y,z,x])},
   F.Term{y,[F.Factor{x,y},F.Factor{F.one(),z},F.Factor{F.zero(),x},F.Factor{y,F.zero()},F.Factor{z,x},F.Factor{F.one(),F.one()},F.Factor{x,x}]},
   F.Term{e(5),[F.Factor{x,y},F.High{},F.Factor{z,x},F.Factor{y,y},F.Factor{x,z},F.Factor{z,z},F.Low{}]},
   F.Term{z,T.eq([y,x,z,z,y,x,y])}]

def main() -> IO(Unit):
  +forms : F.Form = [F.Term{e(3),T.choice(3n,5n)},F.Term{e(4),T.choice(3n,5n)},
    F.Term{e(2),[F.Factor{e(1),e(2)},F.Factor{e(3),e(4)},F.Factor{e(0),e(5)}]}]
  +base = List.replicate(X.E3,8n,e(1))
  do IO<Unit>:
    IO.print(Bool.show(same(F.expand(forms,base),[e(1),e(1),e(1),e(1),e(31),e(68),e(41),e(81)])))
    IO.print(Bool.show(same(F.expand(forms,base),F.expand_list(forms,base))))
    IO.print(Bool.show(same(F.expand(forms,[e(11)]),[e(11)])))
    IO.print(Bool.show(same(F.materialize(forms,3n),[e(0),e(0),e(0),e(0),e(30),e(67),e(40),e(80)])))
    IO.print(Bool.show(same(F.expand(scatter(),zeros(16n)),F.expand_list(scatter(),zeros(16n)))))
    IO.print(Bool.show(same(F.materialize(wide(),7n),F.expand_list(wide(),zeros(128n)))))
#|True
#|True
#|True
#|True
#|True
#|True
