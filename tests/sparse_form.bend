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

def main() -> IO(Unit):
  +forms : F.Form = [F.Term{e(3),T.choice(3n,5n)},F.Term{e(4),T.choice(3n,5n)},
    F.Term{e(2),[F.Factor{e(1),e(2)},F.Factor{e(3),e(4)},F.Factor{e(0),e(5)}]}]
  +base = List.replicate(X.E3,8n,e(1))
  do IO<Unit>:
    IO.print(Bool.show(same(F.expand(forms,base),[e(1),e(1),e(1),e(1),e(31),e(68),e(41),e(81)])))
    IO.print(Bool.show(same(F.expand(forms,base),F.expand_list(forms,base))))
    IO.print(Bool.show(same(F.expand(forms,[e(11)]),[e(11)])))
    IO.print(Bool.show(same(F.materialize(forms,3n),[e(0),e(0),e(0),e(0),e(30),e(67),e(40),e(80)])))
#|True
#|True
#|True
#|True
