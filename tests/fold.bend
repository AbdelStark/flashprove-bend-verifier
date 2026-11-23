import Base
import ../src/fold.bend as F
import ../src/fold_cs.bend as CS
import ../src/base_check.bend as B
import ../src/leaf_shape.bend as S
import ../src/extension.bend as Ext

def e(x: U32) -> Ext.E3: Ext.E3{0,x,0,0,0,0}
def show(x: Ext.E3) -> String:
  Ext.E3{h,l,a,b,c,d} = x
  Bool.pick(String,U32.is_zero(U32.or(U32.or(a,b),U32.or(c,d))),U32.show(h) ++ " " ++ U32.show(l),"extension")

def list(xs: B.Elements) -> String:
  match xs:
    case []: ""
    case x <> tail: show(x) ++ "/" ++ list(tail)

def print_row(row: Maybe<&2,F.Claim>) -> IO(Unit):
  match row:
    case None{}: IO.print("refused")
    case Some{F.Claim{main,mask,target}}:
      do IO<Unit>:
        IO.print(show(target))
        IO.print(list(F.expand(main,CS.zeros(4n))))
        IO.print(list(mask))

def d(+x: U32) -> CS.Draw: CS.Draw{U32.to_nat(x),e(U32.add(x,1)),e(U32.add(x,2)),e(U32.add(x,3))}

# Oracle: field 2 fold_mask_weights/form and generator_row on code (5,4,2) and mask (4,2,1).
# CS weights use theta^(2+3*i+j), including both occurrences of position 17; mask position there is 1.
def main() -> IO(Unit):
  +g: B.Elements = [e(2),e(3),e(5)]
  form: F.Form = [F.Term{e(2),[F.Factor{e(1),e(3)},F.Factor{e(1),e(4)}]}]
  old: F.Single = F.Single{form,[e(7),e(11)],[e(13),e(17)],e(11)}
  stage: S.Stage = S.Stage{B.Code{5n,4n,2n},B.Code{4n,2n,1n},2,1}
  next: S.Stage = S.Stage{B.Code{4n,2n,1n},B.Code{4n,8n,1n},1,1}
  seed: CS.Seed = CS.Seed{[e(2),e(3),e(5),e(6),e(7)],e(8)}
  do IO<Unit>:
    IO.print(list(F.fresh(1n,g,8n)))
    IO.print(list(F.scaled(F.fold_low([e(2)],[e(1),e(4),e(6),e(2)]),e(45))))
    IO.print(show(F.round(e(101),e(3),e(5),e(7))))
    print_row(CS.switch(stage,next,old,e(3),[d(17),d(1),d(17)],seed,e(9)))
#|0 15/0 30/0 45/0 5/0 25/0 1/0 0/0 0/
#|0 315/4294967294 4294967207/
#|0 878
#|0 1686809
#|0 1318636469/4294967157 1961279506/61619 1778969427/4267361797 2143397412/
#|4294967294 4294825071/0 999842/4294967294 4294536831/0 3007070/0 5763/4294967294 4292024336/0 22014/0 58167/4294967294 4294966289/0 2016/0 1512/4294967294 4294964273/0 1260/4294967294 4294964777/4294967294 4294965407/0 24/
