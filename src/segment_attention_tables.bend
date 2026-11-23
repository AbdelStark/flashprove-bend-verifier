import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_shape.bend as S
import ./segment_attention_psc.bend as P
import ./segment_attention_points.bend as Z
import ./segment_attention_rounds.bend as Proof
import ./segment_attention_division.bend as D
import ./segment_model.bend as M
import ./base_check.bend as B
import ./fold.bend as F

def score(+s: S.Shape,i: Nat,z: B.Elements) -> M.Functional:
  M.Functional{0n,A.size(S.lm(s)),Z.equality(S.tail(z,S.lm(s))),Nat.mul(i,S.score_width(s))}
def heads(+s: S.Shape,i: Nat,phi: F.Form) -> M.Functional:
  M.Functional{1n,A.size(S.lt(s)),phi,S.h(s,i)}
def q(+s: S.Shape,i: Nat,zc:B.Elements,toks:F.Form) -> M.Functional:
  M.Functional{4n,A.size(S.la(s)),Z.lng(s,zc,toks),S.q(s,i)}
def score_q(+s:S.Shape,+d:Bool,+r:B.Elements,+z:B.Elements,+col:Bool,id:Nat) -> M.Functional:
  low = Bool.pick(B.Elements,col,S.tail(z,S.lb(s)),Z.query_lo(s,z))
  q(s,id,S.tail(r,S.ld(s)),Z.token(s,d,r,col,low))

def functions(+s: S.Shape, keys: S.Keys, proof: Proof.Proof) -> M.Functionals:
  S.Keys{_,_,+fm,+fd,+w,+ix,_,_,_} = keys
  Proof.Proof{km,kd,sc_e,sc_m,sc_d,+z,_,sc_f,sd,hb,_,_,_,_,_} = proof
  +zm = S.inner(fm)
  +zd = S.inner(fd)
  +rm = P.point(km)
  +rd = P.point(kd)
  +rev_m = P.point(sc_m)
  +rev_d = P.point(sc_d)
  +rf = P.point(sc_f)
  +r_sd = P.point(sd)
  +t = S.lt(s)
  +g = S.lg(s)
  +zi = D.time(s,w,1n)
  +zc = D.channel(s,w)
  +ri_e = Z.middle(P.point(sc_e),g,t)
  +rc = S.tail(rf,S.ld(s))
  +n = S.lb(s)
  [score(s,0n,zm),score(s,1n,Z.vm_point(s,False{},rev_m,zi)),score(s,2n,Z.vm_point(s,True{},rev_d,zi)),
   heads(s,0n,Z.token(s,False{},zm,False{},Z.query_lo(s,zm))),heads(s,1n,Z.token(s,True{},zd,False{},Z.query_lo(s,zd))),
   heads(s,2n,Z.equality(zi)),heads(s,3n,Z.equality(D.time(s,ix,0n))),heads(s,4n,Z.equality(ri_e)),heads(s,5n,Z.equality(Z.middle(z,g,t))),
   heads(s,6n,Z.equality(S.tail(r_sd,t))),heads(s,7n,Z.equality(Z.take(P.point(hb),t))),
   M.Functional{2n,A.size(S.la(s)),Z.lng(s,zc,Z.equality(zi)),S.o(s)},
   score_q(s,False{},rm,zm,False{},0n),score_q(s,False{},rm,zm,True{},1n),
   score_q(s,True{},rd,zd,False{},2n),score_q(s,True{},rd,zd,True{},3n),q(s,4n,zc,Z.equality(ri_e)),
   q(s,5n,zc,Z.token(s,False{},rev_m,True{},S.tail(rev_m,n))),q(s,6n,zc,Z.token(s,True{},rev_d,True{},S.tail(rev_d,n))),
   q(s,7n,rc,Z.equality(Z.take(rf,t))),q(s,8n,rc,Z.equality(Z.take(r_sd,t)))]
