import Base
import ./ff_shape.bend as G
import ./segment_attention_aff.bend as A
import ./extension.bend as X
import ./base_check.bend as B
import ./fold.bend as F
import ./oracle_sample.bend as Sample

# R11.2 lists the lookup accumulator panels, then the panels of KT. Within a
# routed segment each local expert layer gets one selector panel, in layer order.
type Spec is Data:
  Spec{kind: Nat, expert_layer: Nat}
type Panel is Data:
  Panel{spec: Spec, first_weight: Nat, rows: Nat, columns: Nat, width: Nat, column_bits: Nat, serial: Nat}
def Panels() -> Data: List<&2,Panel>

def route(+kind: Nat) -> Bool: Nat.is_eq(kind,6n) || Nat.is_eq(kind,7n) || Nat.is_eq(kind,10n)
def weighted(+k:Nat) -> Bool: Nat.is_lt(k,8n) || Nat.is_eq(k,10n) || Nat.is_eq(k,11n)
def second(+k:Nat) -> Bool: Nat.is_le(6n,k)
def moe_only(+k:Nat) -> Bool: Nat.is_eq(k,5n) || Nat.is_le(12n,k)

def name(+k: Nat) -> String:
  match k:
    case 0n: "G"
    case 1n: "U"
    case 2n: "O"
    case 3n: "D"
    case 4n: "V"
    case 5n: "LR"
    case 6n: "G"
    case 7n: "U"
    case 8n: "N1"
    case 9n: "N2"
    case 10n: "D"
    case 11n: "QK"
    case 12n: "XR"
    case 13n: "DD"
    case _: "MR"

def copies(+k: Nat,+n: Nat,+rest: List<&2,Spec>) -> List<&2,Spec>:
  match n:
    case 0n: rest
    case 1n++i: copies(k,i,Spec{k,i} <> rest)
def specs(+left: Nat,+layers: Nat,+rest: List<&2,Spec>) -> List<&2,Spec>:
  match left:
    case 0n: rest
    case 1n++k: specs(k,layers,copies(k,Bool.pick(Nat,route(k),layers,1n),rest))

def columns(+s: G.Shape,+k: Nat) -> Nat:
  match k:
    case 2n: G.field(s,"dq")
    case 3n: G.field(s,"f")
    case 8n: 1n
    case 9n: 1n
    case 10n: G.field(s,"fe")
    case 12n: 1n
    case 13n: G.field(s,"NE")
    case 14n: G.field(s,"NE")
    case _: G.field(s,"d")

def build(+xs: List<&2,Spec>,+s: G.Shape,+start: Nat,+order: Nat,+acc: Panels) -> Panels:
  match xs:
    case []: List.reverse(&2,Panel,acc)
    case Spec{+k,lm} <> tail:
      +route_ = route(k)
      +ny = columns(s,k)
      +ni = Bool.pick(Nat,route_,G.field(s,"NE"),Bool.pick(Nat,moe_only(k),G.field(s,"LamM"),G.field(s,"Lam")))
      +wy = Sample.row_bits(ny)
      n = Bool.pick(Nat,weighted(k),Bool.pick(Nat,route_,1n,ni),0n)
      +j = order
      +first = start
      p : Panel = Panel{Spec{k,lm},first,ni,ny,Nat.add(wy,Sample.row_bits(ni)),wy,j}
      build(tail,s,Nat.add(first,n),1n+j,p <> acc)

def panels(+s: G.Shape) -> Panels: build(specs(15n,G.field(s,"LamM"),[]),s,0n,0n,[])

# Largest panels are placed first. Equal widths retain the public list order.
def offset(+all: Panels,+bits: Nat,+serial: Nat,+acc: Nat) -> Nat:
  match all:
    case []: acc
    case Panel{_,_,_,_,+w,_,i} <> tail:
      n = Bool.pick(Nat,Nat.is_lt(bits,w) || (Nat.is_eq(bits,w) && Nat.is_lt(i,serial)),A.size(w),0n)
      offset(tail,bits,serial,Nat.add(acc,n))

def layer(+k: Nat,+row: Nat,+lm: Nat) -> Nat:
  Bool.pick(Nat,route(k),1n+Nat.mul(2n,lm),Bool.pick(Nat,moe_only(k),1n+Nat.mul(2n,row),row))

# KL records are checked when the public statement is loaded. Words 0..6
# select the projections, and the three extra words per expert layer select LR/G/U.
def scale_index(+k:Nat) -> Nat:
  match k:
    case 0n: 4n
    case 1n: 5n
    case 2n: 3n
    case 3n: 6n
    case 4n: 2n
    case 6n: 1n
    case 7n: 2n
    case 10n: 6n
    case _: 0n

def word(+xs:List<&2,U32>,+i:Nat) -> Nat:
  U32.to_nat(Maybe.default(&2,U32,List.get(&2,U32,xs,i),0))

def shift(+kl:List<&2,U32>,+layers:Nat,+index:Nat,+k:Nat) -> X.E3:
  extra = Nat.is_le(5n,k) && Nat.is_le(k,7n)
  at = Bool.pick(Nat,extra,Nat.add(Nat.mul(13n,layers),Nat.mul(3n,Nat.div(index,2n))),Nat.mul(13n,index))
  i = Nat.add(at,scale_index(k))
  Bool.pick(X.E3,Nat.is_lt(k,8n) || Nat.is_eq(k,10n) || Nat.is_eq(k,11n),A.nat(A.size(Nat.sub(16n,word(kl,i)))),F.one())
