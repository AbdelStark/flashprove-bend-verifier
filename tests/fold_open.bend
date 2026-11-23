import Base
import ../src/fold_open.bend as O
import ../src/fold_cs.bend as CS
import ../src/extension.bend as E
import ../src/leaf_shape.bend as S
import ../src/base_check.bend as B
import ../src/opening_bytes.bend as OB
import ../src/hash_bytes.bend as H
import ../src/fold.bend as F

# R13.12 first-list joins, including two main positions sharing a short mask opening and a repeated draw.
# At (2,3,5) main row weights 0..7 are -8,16,12,-24,10,-20,-15,30. Mask weights at 2 are -1,2.
def e(x: U32) -> E.E3: E.E3{0,x,0,0,0,0}
def w(x: U32) -> H.Bytes: [x,0,0,0,0,0]
def col(i: Nat, blocks: List<&2,H.Bytes>) -> OB.Column: OB.Column{i,List.concat(&2,U32,blocks)}
def stage() -> S.Stage: S.Stage{B.Code{3n,4n,1n},B.Code{2n,2n,1n},3,1}
def gs() -> B.Elements: [e(2),e(3),e(5)]
def raw() -> OB.Places: [5n,1n,5n]
def cases() -> OB.Columns:
  [col(1n,[[2,0,3,0,5,0],w(17),w(19),w(23)]),col(5n,[[7,0,11,0,13,0],w(29),w(31),w(37)])]
def abs(x: E.E3) -> String:
  E.E3{h,l,a,b,c,d} = x
  Bool.pick(String,U32.is_zero(U32.or(U32.or(a,b),U32.or(c,d))),U32.show(h) ++ "," ++ U32.show(l),"ext")
def rows(xs: CS.Draws) -> String:
  match xs:
    case []: ""
    case CS.Draw{p,m,n,f} <> tail: Nat.show(p) ++ "=" ++ abs(m) ++ "/" ++ abs(n) ++ "/" ++ abs(f) ++ "|" ++ rows(tail)
def show(v: Maybe<&2,CS.Draws>) -> String:
  match v:
    case None{}: "refused"
    case Some{xs}: rows(xs)
def second(index: OB.Columns) -> Maybe<&2,CS.Draws>:
  own: OB.Columns = [col(1n,[w(13),w(2),w(19),w(23)]),col(5n,[w(11),w(3),w(31),w(37)])]
  omega: OB.Columns = [col(1n,[w(7),w(5),w(3),w(1)]),col(5n,[w(5),w(7),w(11),w(13)])]
  O.key(O.Second{1n,1n,4n},stage(),gs(),raw(),[index,own,omega])
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show(O.ranges(3n,1n,stage(),gs(),raw(),cases(),[])))
    IO.print(show(second([col(1n,[w(2)])])))
    IO.print(show(second([col(5n,[w(2)])])))
    IO.print(show(O.ranges(3n,1n,stage(),gs(),raw(),List.take(&2,OB.Column,cases(),1n),[])))
    IO.print(show(O.ranges(2n,1n,stage(),gs(),raw(),cases(),[])))
#|5=0,276/4294967294,4294967268/0,43|1=0,92/4294967294,4294967280/0,27|5=0,276/4294967294,4294967268/0,43|
#|5=0,2/0,4/0,43|1=0,166/0,2/0,27|5=0,2/0,4/0,43|
#|refused
#|refused
#|refused
