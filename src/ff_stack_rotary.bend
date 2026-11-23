import Base
import ./ff_stack.bend as S
import ./ff_shape.bend as G
import ./fold.bend as F
import ./row_tensor.bend as T
import ./segment_attention_aff.bend as A
import ./extension.bend as X
import ./sumcheck.bend as E
import ./base_check.bend as B
import ./policy_tables.bend as Tables

type Point is Data:
  Point{heads:B.Elements,active:B.Elements,constant:B.Elements}

def heads(+s:G.Shape,+z:B.Elements,+seg:G.Segment,n:Nat,+limit:Nat,rev:B.Elements) -> B.Elements:
  match n:
    case 0n: rev
    case 1n+k:
      +j = k
      +w = G.field(s,"dh")
      val = Bool.pick(X.E3,Nat.is_lt(j,limit),A.eq(z,Nat.div(G.pos(seg,Nat.mul(j,w)),w)),F.zero())
      heads(s,z,seg,j,limit,val <> rev)

def add(v:Array<X.E3> & X.E3,idx:U32,x:X.E3) -> Array<X.E3>:
  (a,old) = v
  Array.set(X.E3,a,idx,E.add(old,x))

type Partial is Type:
  Partial{remaining:List<&2,U32>,sums:Array<X.E3>}

def columns(xs:List<&2,U32>,remaining:Nat,i:U32,+weight:X.E3,a:Array<X.E3>) -> Partial:
  match xs remaining:
    case xs 0n: Partial{xs,a}
    case Con{v,rest} 1n+k:
      +j = i
      x = F.sub(A.nat(U32.to_nat(v)),A.nat(4096n))
      columns(rest,k,U32.add(j,1),weight,add(Array.get(X.E3,a,j),j,E.mul(weight,x)))
    case _ _: Partial{[],a}

def rows(eta:B.Elements,p:Partial) -> Partial:
  match eta p:
    case Nil{} x: x
    case Con{w,tail} Partial{xs,buf}: rows(tail,columns(xs,64n,0,w,buf))

def list(xs:List<X.E3>,acc:B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,X.E3,acc)
    case x <> tail: list(tail,x <> acc)
def values(p:Partial) -> B.Elements:
  Partial{_,buf} = p
  list(Array.to_list(X.E3,buf),[])

def halves(a:Partial,+eta:B.Elements) -> B.Elements & B.Elements:
  Partial{xs,buf} = a
  (list(Array.to_list(X.E3,buf),[]),values(rows(eta,Partial{xs,Array.new(X.E3,6n,F.zero())})))
def mix(cs:B.Elements,ss:B.Elements,ls:B.Elements) -> B.Elements:
  match cs ss ls:
    case Con{+c,tail} Con{+s,more} Con{+a,Con{+b,rest}}:
      E.add(E.mul(c,a),E.mul(s,b)) <> F.sub(E.mul(c,b),E.mul(s,a)) <> mix(tail,more,rest)
    case _ _ _: []
def combined(t:B.Elements & B.Elements,ls:B.Elements) -> B.Elements:
  (c,s) = t
  mix(c,s,ls)
def point(+s:G.Shape,key:B.Elements,terms:B.Elements,table:Tables.Table) -> Point:
  Tables.Table{xs,_} = table
  +seg = G.segment(s,"QK")
  +raw = A.rev(G.zj(s,key,"QK"))
  +low = S.fold_eq(F.take(X.E3,raw,7n))
  +eta = S.fold_eq(A.rev(terms))
  hi = heads(s,A.rev(List.drop(&2,X.E3,raw,7n)),seg,64n,Nat.add(G.field(s,"H"),G.field(s,"G")),[])
  parts = halves(rows(eta,Partial{xs,Array.new(X.E3,6n,F.zero())}),eta)
  Point{hi,combined(parts,low),F.scaled(low,A.nat(4096n))}
