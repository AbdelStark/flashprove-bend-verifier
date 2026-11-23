import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_points.bend as Z
import ./base_check.bend as B
import ./extension.bend as X
import ./fold.bend as F

type Field is Data:
  Field{name:String,value:Nat}
type Tensor is Data:
  Tensor{matrix: Nat,off: Nat,limbs: Nat,count: Nat,width: Nat}
type NamedTensor is Data:
  NamedTensor{name:String,tensor:Tensor}
type Run is Data:
  Run{first:Nat,length:Nat}
type Segment is Data:
  Segment{call:Nat,col_bits:Nat,count:Nat,moe:Bool,runs:List<&2,Run>}
type NamedSegment is Data:
  NamedSegment{name:String,segment:Segment}
type Table is Data:
  Table{matrix:Nat,length:Nat,offset:Nat,partitions:List<&2,Nat>}
type NamedTable is Data:
  NamedTable{matrix:String,point:String,table:Table}
type Call is Data:
  Call{prefix:Nat,extra:Nat,bits:Nat,kind:String}
type Shape is Data:
  Shape{fields:List<&2,Field>,tensors:List<&2,NamedTensor>,segments:List<&2,NamedSegment>,tables:List<&2,NamedTable>,calls:List<&2,Call>}

def field_at(xs:List<&2,Field>,+n:String) -> Nat:
  match xs:
    case []: 0n
    case Field{k,v} <> tail: Bool.pick(Nat,String.eq(k,n),v,field_at(tail,n))
def field(s:Shape,name:String) -> Nat:
  Shape{xs,_,_,_,_} = s
  field_at(xs,name)
def tensor_at(xs:List<&2,NamedTensor>,+n:String) -> Tensor:
  match xs:
    case []: Tensor{0n,0n,0n,0n,0n}
    case NamedTensor{k,v} <> tail: Bool.pick(Tensor,String.eq(k,n),v,tensor_at(tail,n))
def tensor(s:Shape,name:String) -> Tensor:
  Shape{_,xs,_,_,_} = s
  tensor_at(xs,name)
def segment_at(xs:List<&2,NamedSegment>,+n:String) -> Segment:
  match xs:
    case []: Segment{0n,0n,0n,False{},[]}
    case NamedSegment{k,v} <> tail: Bool.pick(Segment,String.eq(k,n),v,segment_at(tail,n))
def segment(s:Shape,name:String) -> Segment:
  Shape{_,_,ss,_,_} = s
  segment_at(ss,name)
def table_at(xs:List<&2,NamedTable>,+mn:String,+pt:String) -> Table:
  match xs:
    case []: Table{0n,0n,0n,[]}
    case NamedTable{m,p,t} <> tail: Bool.pick(Table,String.eq(m,mn) && String.eq(p,pt),t,table_at(tail,mn,pt))
def table(s:Shape,matrix:String,point:String) -> Table:
  Shape{_,_,_,ts,_} = s
  table_at(ts,matrix,point)
def offset(s:Table) -> Nat:
  Table{_,_,o,_} = s
  o
def location(rs:List<&2,Run>,+index:Nat) -> Nat:
  match rs:
    case []: 0n
    case Run{start,+n} <> tail: Bool.pick(Nat,Nat.is_lt(index,n),Nat.add(start,index),location(tail,Nat.sub(index,n)))
def pos(seg:Segment,i:Nat) -> Nat:
  Segment{_,_,_,_,rs} = seg
  location(rs,i)
def call(s:Shape,seg:Segment) -> Call:
  Shape{_,_,_,_,cs} = s
  Segment{i,_,_,_,_} = seg
  Maybe.default(&2,Call,List.get(&2,Call,cs,i),Call{0n,0n,0n,""})
def coordinates(+s:Shape,+key:B.Elements,c:Call) -> B.Elements:
  Call{_,j,_,_} = c
  +r = field(s,"forest_top")
  Z.cat(A.rev(Z.take(key,j)),A.rev(List.drop(&2,X.E3,key,r)))
def e(+s:Shape,key:B.Elements,c:Call) -> X.E3:
  Call{first,+i,_,_} = c
  z = A.rev(A.slice(key,i,Nat.sub(field(s,"forest_top"),i)))
  A.eq(z,Nat.div(first,A.size(i)))
def ec(+s:Shape,key:B.Elements,name:String) -> X.E3: e(s,key,call(s,segment(s,name)))
def zl(+s:Shape,key:B.Elements,name:String) -> B.Elements: Z.take(coordinates(s,key,call(s,segment(s,name))),field(s,"ll"))
def zcol(+s:Shape,key:B.Elements,+c:Call) -> B.Elements:
  Call{_,_,n,_} = c
  A.slice(coordinates(s,key,c),field(s,"ll"),n)
def zj(+s:Shape,key:B.Elements,name:String) -> B.Elements: zcol(s,key,call(s,segment(s,name)))
def el(s:Shape,key:B.Elements,name:String,lam:Nat) -> X.E3: A.eq(zl(s,key,name),lam)
def head_cols(s:Shape,name:String,point:String) -> Nat: offset(table(s,name,point))
