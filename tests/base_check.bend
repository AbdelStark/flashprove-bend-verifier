import Base
import ../src/base_check.bend as B
import ../src/extension.bend as Ext
import ../src/hash_bytes.bend as H
import ../src/opening_bytes.bend as OB

def wires(xs: H.Bytes) -> H.Bytes:
  match xs:
    case []: []
    case x <> tail: H.cat([H.word(x),wires(tail)])

def body() -> H.Bytes:
  # main messages, mask messages, main tail, mask tail; each triple is one E.
  wires([4,5,6, 3,0,4, 0,3,2, 3,1,9, 1,2,3, 2,3,7])

def parse(raw: H.Bytes) -> Maybe<&2,B.Rows>:
  B.read(B.Code{3n,2n,1n},B.Code{2n,2n,1n},raw)

def lambda() -> Ext.E3:
  Ext.E3{0,2,0,1,0,3}

# Pinned blocks/code/code.h symbol_at minus lambda times the original symbols, ordered by R7.1.
# At 5 the mask code is evaluated at 1. The corresponding star target is (250,315,120).
def first() -> OB.Column:
  OB.Column{0n,[3,0,4,0,2,0,142,0,14,0,224,0,0,0,7,0,6,0,95,0,23,0,443,0]}

def second(main: U32, mask: U32) -> OB.Column:
  OB.Column{5n,[8,0,4,0,2,0,main,9633791,3707764711,4294967294,3590324195,12845055,0,0,12,0,6,0,mask,0,4294967268,4294967294,410,0]}

def opened(result: Maybe<&2,B.Rows>, lam: Ext.E3, places: OB.Places, columns: OB.Columns) -> Bool:
  match result:
    case None{}: False{}
    case Some{rows}: B.symbols(rows,lam,places,columns)

def claim(result: Maybe<&2,B.Rows>, target: U32, main_weights: B.Elements, mask_weights: B.Elements) -> Bool:
  match result:
    case None{}: False{}
    case Some{rows}: B.linear(rows,lambda(),Ext.E3{0,250,0,315,0,120},Ext.E3{0,target,0,1,0,3},main_weights,mask_weights)

def present(result: Maybe<&2,B.Rows>) -> Bool:
  match result:
    case None{}: False{}
    case Some{_}: True{}

def main() -> IO(Unit):
  +rows = parse(body())
  +pos: OB.Places = [0n,5n]
  +col = second(3825205205,65)
  +cols: OB.Columns = [first(),col]
  +mw: B.Elements = [Ext.E3{0,3,0,1,0,4},Ext.E3{0,1,0,5,0,9}]
  +kw: B.Elements = [Ext.E3{0,2,0,6,0,5},Ext.E3{0,3,0,5,0,8}]
  do IO<Unit>:
    IO.print(Bool.show(opened(rows,lambda(),pos,cols)))
    IO.print(Bool.show(claim(rows,7,mw,kw)))
    IO.print(Bool.show(opened(rows,lambda(),pos,[first(),second(3825205204,65)])))
    IO.print(Bool.show(opened(rows,lambda(),pos,[first(),second(3825205205,64)])))
    IO.print(Bool.show(opened(rows,Ext.E3{0,2,0,0,0,3},pos,cols)))
    IO.print(Bool.show(opened(rows,lambda(),pos,[first()])))
    IO.print(Bool.show(opened(rows,lambda(),pos,[col,first()])))
    IO.print(Bool.show(opened(rows,lambda(),[5n,0n],[col,first()])))
    IO.print(Bool.show(opened(rows,lambda(),[],[])))
    IO.print(Bool.show(claim(rows,8,mw,kw)))
    IO.print(Bool.show(claim(rows,7,kw,mw)))
    IO.print(Bool.show(claim(rows,7,[],kw)))
    IO.print(Bool.show(present(parse(List.drop(&2,U32,body(),1n)))))
    IO.print(Bool.show(present(parse(0 <> body()))))
    IO.print(Bool.show(present(parse(H.cat([H.le(1),H.le(4294967295),List.drop(&2,U32,body(),8n)])))))
    IO.print(Bool.show(present(B.read(B.Code{3n,2n,1n},B.Code{4n,2n,1n},body()))))

#|True
#|True
#|False
#|False
#|False
#|False
#|False
#|False
#|False
#|False
#|False
#|False
#|False
#|False
#|False
#|False
