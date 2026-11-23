import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_shape.bend as S
import ./segment_attention_psc.bend as P
import ./segment_attention_points.bend as Z
import ./segment_attention_scores.bend as C
import ./segment_attention_reads.bend as R
import ./segment_forest.bend as Forest
import ./key_stage_lookup_rows.bend as L
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F

type Pieces is Data:
  Pieces{w: S.Unit_, i: S.Unit_, h: S.Unit_}
type At is Data:
  At{shape: S.Shape, pieces: Pieces, check: P.Check}

def main_group(+s: S.Shape,u: S.Unit_,side: Nat) -> B.Elements:
  Z.middle(S.inner(u),side,S.lg(s))
def time(+s: S.Shape,u: S.Unit_,side: Nat) -> B.Elements:
  Z.middle(S.inner(u),Nat.add(side,S.lg(s)),S.lt(s))
def channel(+s: S.Shape,u: S.Unit_) -> B.Elements: S.tail(S.inner(u),S.ld(s))

def field(s: S.Shape,table: Nat,kind: R.TensorKind,+u: S.Unit_,side: Nat,loc: A.Aff) -> A.Aff:
  +sh = s
  A.minus(loc,R.batch(S.weights(u),sh,table,kind,main_group(sh,u,side),channel(sh,u),0n,[]))
def ix(at: At,k_: Nat) -> A.Aff:
  At{+s,Pieces{_,i,_},c} = at
  +k = k_
  field(s,S.h(s,3n),R.Index{k},i,0n,A.slot(P.prefix(c),Nat.add(5n,k)))

def ea(at: At,b_: Nat) -> A.Aff:
  At{+s,_,+c} = at
  +b = b_
  A.minus(A.slot(P.ends(c),Nat.mul(2n,b)),R.read(s,S.h(s,4n),R.Denominator{},b,Z.take(P.point(c),S.lg(s)),[]))
def eb(at: At,b_: Nat) -> A.Aff:
  At{+s,Pieces{w,_,_},+c} = at
  +b = b_
  A.minus(A.slot(P.ends(c),Nat.add(1n,Nat.mul(2n,b))),R.read(s,S.q(s,4n),R.OutputVector{},b,Z.take(P.point(c),S.lg(s)),channel(s,w)))

def equations(+at: At) -> A.Equations:
  At{+s,Pieces{+w,_,+h},+c} = at
  +v = P.prefix(c)
  +t = S.lt(s)
  zc = field(s,S.h(s,2n),R.Denominator{},w,1n,A.slot(v,2n))
  rh = field(s,S.o(s),R.Remainder{},w,1n,A.slot(v,3n))
  rp = field(s,S.o(s),R.Complement{},w,1n,A.slot(v,4n))
  rh2 = field(s,S.o(s),R.Remainder{},h,0n,A.slot(v,Nat.add(5n,t)))
  rp2 = field(s,S.o(s),R.Complement{},h,0n,A.slot(v,Nat.add(6n,t)))
  +r = P.point(c)
  ew = E.mul(Z.dot(main_group(s,w,1n),Z.take(r,S.lg(s))),Z.dot(time(s,w,1n),Z.middle(r,S.lg(s),t)))
  row = P.product_row(c,A.slot(v,1n),Z.polys(S.weights(w),ew))
  zc <> rh <> rp <> C.each(At,ix,at,t,rh2 <> rp2 <> row <> C.both(At,ea,eb,at,S.pairs(s),[]))

def ix_value(+v: A.Values,t: Nat,i: Nat,w: X.E3,acc: A.Aff) -> A.Aff:
  match t:
    case 0n: acc
    case 1n+k:
      +scale = w
      +j = i
      ix_value(v,k,Nat.add(1n,j),E.add(scale,scale),A.add(acc,A.slot(v,Nat.add(5n,j)),scale))

def division_key(+s: S.Shape, +w: S.Unit_,+i: S.Unit_,+v: A.Values) -> A.Aff:
  +lw = C.total(w)
  +z = A.get(S.inner(w),0n)
  +rem = A.minus(A.plus(C.scale(A.slot(v,0n),2n),A.slot(v,2n)),C.scale(A.slot(v,1n),2n))
  low = A.minus(rem,C.scale(C.biased(v,3n,lw),65536n))
  high = A.minus(A.minus(A.minus(C.scale(A.slot(v,2n),2n),A.const(lw)),rem),C.scale(C.biased(v,4n,lw),65536n))
  slot = A.add(A.scale(low,F.sub(F.one(),z)),high,z)
  bits = ix_value(v,S.lt(s),0n,F.one(),A.zero())
  ix = C.scale(A.minus(A.const(E.mul(C.total(i),Z.id(time(s,i,0n),F.zero()))),bits),A.size(Nat.sub(16n,S.lt(s))))
  A.plus(slot,ix)

def joined(forest: Forest.Claims,+s: S.Shape,keys: S.Keys,+fm: P.Check,+fd: P.Check,se: P.Check) -> A.Aff:
  Forest.Claims{L.Point{_,ms,t},alpha,+theta,_} = forest
  S.Keys{+rm,+rd,+km,+kd,+wl,ix,+wh,+step,+pad} = keys
  +prefix = P.prefix(se)
  +raw = P.prefix(fm)
  kr = A.plus(C.kr_key(raw,0n,rm),C.kr_key(raw,3n,rd))
  padding = E.mul(F.sub(F.one(),E.add(C.total(km),C.total(kd))),A.nat(pad))
  kf = A.plus(A.const(padding),A.plus(C.kf_key(s,False{},km,fm,step,pad),C.kf_key(s,True{},kd,fd,step,pad)))
  range = division_key(s,wl,ix,prefix)
  +n = S.lt(s)
  +lh = C.total(wh)
  window = A.plus(C.biased(prefix,Nat.add(5n,n),lh),C.scale(C.biased(prefix,Nat.add(6n,n),lh),A.size(20n)))
  init : A.Aff = A.Aff{[],ms,F.sub(alpha,t)}
  s0 = A.add(init,kr,E.negate(S.factor(rm)))
  s1 = A.add(s0,A.plus(kf,A.const(theta)),E.negate(S.factor(km)))
  s2 = A.add(s1,A.plus(range,A.const(E.mul(theta,A.nat(2n)))),E.negate(S.factor(wl)))
  A.add(s2,A.plus(window,A.const(E.mul(theta,A.nat(3n)))),E.negate(S.factor(wh)))
