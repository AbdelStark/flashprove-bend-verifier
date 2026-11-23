import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_shape.bend as S
import ./segment_attention_psc.bend as P
import ./segment_attention_scores.bend as C
import ./segment_attention_points.bend as Z
import ./segment_attention_reads.bend as R
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./extension.bend as X
import ./fold.bend as F

type Stage is Data:
  Stage{s:S.Shape,zero:B.Elements,maxima:A.Values,sf:P.Check,sd:P.Check,hb:P.Check}
def maximum(st: Stage,id: Nat) -> A.Aff:
  Stage{+s,z,vals,_,_,_} = st
  +b = id
  A.minus(A.slot(vals,b),R.read(s,S.h(s,5n),R.Maximum{},b,Z.take(z,S.lg(s)),[]))
def query(st: Stage,id: Nat) -> A.Aff:
  Stage{+s,_,_,+sf,_,_} = st
  +pt = P.point(sf)
  +b = id
  read = R.read(s,S.q(s,7n),R.Query{},b,Z.middle(pt,S.lt(s),S.lg(s)),S.tail(pt,S.ld(s)))
  A.minus(A.slot(P.ends(sf),Nat.mul(2n,b)),read)
def key(st: Stage,id: Nat) -> A.Aff:
  Stage{+s,_,_,sf,+sd,_} = st
  +i = id
  read = R.read(s,S.q(s,8n),R.KeyVector{},Nat.mul(i,S.ha(s)),Z.middle(P.point(sd),S.lt(s),S.lg(s)),S.tail(P.point(sf),S.ld(s)))
  A.minus(A.slot(P.ends(sd),i),read)
def lookup_bit(st: Stage,index: Nat) -> A.Aff:
  Stage{+s,_,_,_,+sd,_} = st
  +i = index
  +lt = S.lt(s)
  read = R.read(s,S.h(s,6n),R.Index{Nat.mod(i,lt)},Nat.div(i,lt),Z.middle(P.point(sd),lt,S.lg(s)),[])
  A.minus(A.slot(P.ends(sd),Nat.add(S.layers(s),i)),read)
def complement(st: Stage,id: Nat) -> A.Aff:
  Stage{_,_,_,_,_,hb} = st
  +vs = P.ends(hb)
  +b = id
  A.plus(A.minus(A.slot(vs,Nat.add(1n,Nat.mul(2n,b))),A.slot(vs,Nat.mul(2n,b))),A.const(F.one()))
def bits(n: Nat,+s: S.Shape,+b: Nat,+g: B.Elements,+rk: B.Elements,acc: A.Aff) -> A.Aff:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      x = R.read(s,S.h(s,7n),R.Index{i},b,g,[])
      bits(i,s,b,g,rk,A.add(acc,x,E.negate(A.eq(rk,i))))
def interpolation(st: Stage,id: Nat) -> A.Aff:
  Stage{+s,_,_,_,_,+hb} = st
  +b = id
  +r = P.point(hb)
  bits(S.lt(s),s,b,Z.middle(r,S.lt(s),S.lg(s)),S.tail(r,4n),A.slot(P.ends(hb),Nat.mul(2n,b)))

def sf_factor(+s:S.Shape,+z:B.Elements,+r:B.Elements) -> X.E3:
  E.mul(Z.dot(Z.take(z,S.lg(s)),Z.middle(r,S.lt(s),S.lg(s))),Z.dot(Z.middle(z,S.lg(s),S.lt(s)),Z.take(r,S.lt(s))))
def hb_factor(+s:S.Shape,+z:B.Elements,+r:B.Elements) -> X.E3:
  +t = S.lt(s)
  +g = S.lg(s)
  +j = Nat.add(g,t)
  a = Z.dot(Z.middle(z,j,4n),S.tail(r,4n))
  b = Z.dot(Z.middle(z,Nat.add(j,4n),g),Z.middle(r,t,g))
  E.mul(a,E.mul(b,Z.dot(S.tail(z,t),Z.take(r,t))))

def ith(n: Nat,+vs: A.Values,index: Nat,pj: B.Elements,acc: X.E3) -> X.E3:
  match n pj:
    case 0n _: acc
    case 1n+k Con{+y,tail}:
      +i = index
      +iy = A.scalar(A.at(vs,i))
      f = E.add(E.mul(iy,F.sub(E.add(y,y),F.one())),F.sub(F.one(),y))
      ith(k,vs,Nat.add(1n,i),tail,E.mul(f,acc))
    case _ _: acc
def s0(ws:B.Elements,+vs:A.Values,+s:S.Shape,+pj:B.Elements,b:Nat,acc:X.E3) -> X.E3:
  match ws:
    case []: acc
    case w <> tail:
      +i = b
      k = A.scalar(A.at(vs,Nat.div(i,S.ha(s))))
      v = ith(S.lt(s),vs,Nat.add(S.layers(s),Nat.mul(i,S.lt(s))),pj,E.mul(w,k))
      s0(tail,vs,s,pj,Nat.add(1n,i),E.add(acc,v))
def sd_row(+s:S.Shape,+sf:P.Check,+sd:P.Check,om:X.E3) -> A.Aff:
  +t = S.lt(s)
  +g = S.lg(s)
  +r = P.point(sf)
  +p = P.point(sd)
  +ws = A.powers(S.pairs(s),om,F.one())
  factor = E.mul(Z.dot(Z.take(r,t),S.tail(p,t)),Z.dot(Z.middle(r,t,g),Z.middle(p,t,g)))
  start = A.weighted(P.ends(sf),ws,2n,1n,A.zero())
  P.row(sd,start,E.mul(factor,s0(ws,P.ends(sd),s,A.rev(Z.take(p,t)),0n,F.zero())))

def equations(+st: Stage,om:X.E3,om4:X.E3,om5:X.E3) -> A.Equations:
  Stage{+s,+z,v,+sf,+sd,+hb} = st
  +np = S.pairs(s)
  +ws = A.powers(np,om,F.one())
  a = P.product_row(sf,A.weighted(v,ws,1n,0n,A.zero()),Z.polys(ws,sf_factor(s,z,P.point(sf))))
  b = sd_row(s,sf,sd,om4)
  c = P.product_row(hb,A.zero(),Z.polys(A.powers(np,om5,F.one()),hb_factor(s,z,P.point(hb))))
  last : A.Equations = c <> C.both(Stage,complement,interpolation,st,np,[])
  ends = C.each(Stage,key,st,S.layers(s),C.each(Stage,lookup_bit,st,Nat.mul(np,S.lt(s)),last))
  C.each(Stage,maximum,st,np,a <> C.each(Stage,query,st,np,b <> ends))
