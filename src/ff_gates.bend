import Base
import ./ff_shape.bend as G
import ./ff_reads.bend as Read
import ./ff_rounds.bend as R
import ./ff_norm.bend as Norm
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./segment_attention_scores.bend as C
import ./segment_attention_points.bend as Z
import ./base_check.bend as B
import ./fold.bend as F
import ./extension.bend as X
import ./sumcheck.bend as E

type Endpoints is Data:
  Endpoints{s:G.Shape,values:A.Values}
def reciprocal(data:Endpoints,k:Nat) -> A.Aff:
  Endpoints{s,vs} = data
  +i = k
  A.minus(A.slot(vs,i),Norm.recip(s,"rt",i))
def score(data:Endpoints,k:Nat) -> A.Aff:
  Endpoints{+s,vs} = data
  +i = k
  A.minus(A.slot(vs,Nat.add(G.field(s,"NI"),i)),Read.sh(s,"sc","rt",i,0n))
def selector(data:Endpoints,k:Nat) -> A.Aff:
  Endpoints{+s,vs} = data
  +i = k
  +n = G.field(s,"NE")
  A.minus(A.slot(vs,Nat.add(Nat.add(G.field(s,"NI"),G.field(s,"LamM")),i)),Read.sh(s,"sel","rt",Nat.div(i,n),Nat.mod(i,n)))
def reads(+s:G.Shape,tt:P.Check) -> A.Equations:
  +data : Endpoints = Endpoints{s,P.ends(tt)}
  +n = G.field(s,"LamM")
  C.each(Endpoints,reciprocal,data,G.field(s,"NI"),C.each(Endpoints,score,data,n,
    C.each(Endpoints,selector,data,Nat.mul(n,G.field(s,"NE")),[])))

def rhs(n:Nat,+s:G.Shape,+routed:Bool,+z:B.Elements,+name:String,+len:Nat,+stride:Nat,+pt:String,acc:A.Aff) -> A.Aff:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      +lm = Nat.div(i,len)
      +col = Nat.mod(i,len)
      w = A.eq(z,Nat.add(Nat.mul(lm,stride),col))
      at = Bool.pick(Nat,routed,1n+Nat.mul(2n,lm),lm)
      x = Read.long(s,name,pt,at,Bool.pick(Nat,routed,Nat.add(len,col),col))
      rhs(i,s,routed,z,name,len,stride,pt,A.add(acc,x,w))
def gate(+s:G.Shape,+routed:Bool,+level:R.Level,start:A.Aff) -> A.Equations:
  +psc = R.check(level)
  +n = Bool.pick(Nat,routed,G.field(s,"LamM"),G.field(s,"Lam"))
  +step = G.field(s,"S2")
  +len = Nat.div(Bool.pick(Nat,routed,G.field(s,"fe"),G.field(s,"f")),step)
  +stride = Bool.pick(Nat,routed,len,Nat.div(G.field(s,"Pf"),step))
  +z = Z.take(R.at(level),Nat.sub(List.length(&2,X.E3,R.at(level)),G.field(s,"la")))
  +pt = Bool.pick(String,routed,"Z_b","Z_a")
  +vs = P.ends(psc)
  [Norm.product(psc,start),
    A.plus(A.slot(vs,0n),rhs(Nat.mul(n,len),s,routed,z,"s",len,stride,pt,A.zero())),
    A.plus(A.slot(vs,1n),rhs(Nat.mul(n,len),s,routed,z,"u",len,stride,pt,A.zero()))]
def weights(n:Nat,+z:B.Elements,acc:B.Elements) -> B.Elements:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      weights(i,z,A.eq(z,i) <> acc)
def hot(n:Nat,+s:G.Shape,+lm:Nat,acc:A.Aff) -> A.Aff:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      hot(i,s,lm,A.plus(acc,Read.sh(s,"sel","zt",lm,i)))
def one(s:G.Shape,i:Nat) -> A.Aff:
  +shape = s
  hot(G.field(shape,"NE"),shape,i,A.const(E.negate(F.one())))
def groups(+s:G.Shape,l:R.Level,m:R.Level,stack:P.Check,experts:B.Elements) -> A.Equations:
  +vs = P.ends(stack)
  +n = G.field(s,"LamM")
  start = A.weighted(vs,weights(n,experts,[]),1n,2n,A.zero())
  C.cat(gate(s,False{},l,A.slot(vs,1n)),C.cat(gate(s,True{},m,start),C.each(G.Shape,one,s,n,[])))
def embedding(+s:G.Shape,z:B.Elements,slot:A.Values) -> A.Equations:
  match slot:
    case []: []
    case v <> _:
      +width = Nat.div(G.field(s,"d"),G.field(s,"S2"))
      [A.minus(Read.residual(s,weights(width,z,[]),"Z_E",0n),A.hidden(v))]
