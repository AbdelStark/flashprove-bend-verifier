import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_shape.bend as S
import ./segment_attention_psc.bend as P
import ./segment_attention_scores.bend as C
import ./segment_attention_points.bend as Z
import ./segment_attention_reads.bend as R
import ./segment_attention_division.bend as D
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F

# R11.3 group 6, numerator and denominator over all real causal tiles.
type Values is Data:
  Values{shape: S.Shape, diagonal: Bool, check: P.Check, wl: S.Unit_, tile: B.Elements, gam: X.E3}

def a(data: Values,index: Nat) -> A.Aff:
  Values{+s,+d,+c,_,+pt,_} = data
  +b = index
  +tab = Nat.mul(S.score_width(s),Bool.pick(Nat,d,2n,1n))
  val = A.plus(A.const(A.nat(128n)),A.plus(R.plane(s,tab,d,pt,3n,b),C.scale(R.plane(s,tab,d,pt,4n,b),256n)))
  A.minus(A.slot(P.ends(c),Nat.mul(2n,b)),val)
def b(data: Values,index: Nat) -> A.Aff:
  Values{+s,+d,+c,w,_,gam} = data
  +i = index
  tab = S.q(s,Bool.pick(Nat,d,6n,5n))
  val = R.read(s,tab,R.ValueVector{},i,Z.take(P.point(c),S.lg(s)),D.channel(s,w))
  A.minus(A.slot(P.ends(c),Nat.add(1n,Nat.mul(2n,i))),A.plus(A.const(gam),val))
def dot(+s:S.Shape,+d:Bool,+r:B.Elements,+w:S.Unit_) -> X.E3:
  +zi = Z.take(D.time(s,w,1n),S.tiles(s))
  decide = Bool.pick(Unit -> X.E3,d,
    _ => Z.dot(zi,Z.middle(r,S.lg(s),S.tiles(s))),_ => Z.weighted_marginal(A.size(S.tiles(s)),s,r,zi,F.zero()))
  E.mul(decide(Unit{}),Z.dot(D.main_group(s,w,1n),Z.take(r,S.lg(s))))
def rows(+s: S.Shape,+d: Bool,+check: P.Check,+w: S.Unit_,gam: X.E3,claim: A.Aff) -> A.Equations:
  +r = P.point(check)
  tile = Z.vm_point(s,d,r,D.time(s,w,1n))
  product = P.product_row(check,claim,Z.polys(S.weights(w),dot(s,d,r,w)))
  product <> C.both(Values,a,b,Values{s,d,check,w,tile,gam},S.pairs(s),[])
def equations(+s: S.Shape,+wl: S.Unit_,+vm: P.Check,vd: P.Check,se: P.Check,+gam: X.E3) -> A.Equations:
  +v = P.prefix(vm)
  +w = P.prefix(se)
  combined = A.minus(A.minus(A.plus(A.slot(v,0n),A.slot(v,1n)),A.slot(w,0n)),A.scale(A.slot(w,2n),gam))
  combined <> C.cat(rows(s,False{},vm,wl,gam,A.slot(v,0n)),rows(s,True{},vd,wl,gam,A.slot(v,1n)))
