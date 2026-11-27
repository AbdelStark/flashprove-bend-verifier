import Base
import ./head_aff.bend as H
import ./norm_digits.bend as D
import ./oracle_sample.bend as Sample
import ./head_rounds.bend as R
import ./head_types.bend as G
import ./head_catalog.bend as C
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./segment_model.bend as M
import ./row_tensor.bend as T
import ./extension.bend as X
import ./sumcheck.bend as E
import ./base_check.bend as B
import ./fold.bend as F
import ./header.bend as Header
import ./pow2.bend as P2

def Rows() -> Data: List<&2,H.Aff>
def two(k: Nat) -> Nat: P2.pow2(k)
def slot(vs: A.Values,i: Nat) -> H.Aff: H.slot(A.at(vs,i))
def join(a: Rows,b: Rows) -> Rows: List.append(&2,H.Aff,a,b)

# Materialize the shared five-limb digit identities in the head's tensor form.
def packed(s: G.Shape,row: A.Aff) -> H.Aff:
  A.Aff{cs,ms,c} = row
  H.Aff{A.coefficients(cs,Sample.row_bits(C.u3(s)),[]),ms,c}
def packed_rows(+s:G.Shape,rs:A.Equations) -> Rows:
  match rs:
    case []: []
    case x <> tail: packed(s,x) <> packed_rows(s,tail)
def word(s:G.Shape,t:Nat,j:Nat,n:Nat) -> H.Aff: packed(s,D.word(t,j,n))
def low(s:G.Shape,t:Nat) -> H.Aff: packed(s,D.low(t))
def high(s:G.Shape,t:Nat) -> H.Aff: packed(s,D.high(t))
def recip(s:G.Shape,t:Nat) -> H.Aff: packed(s,D.recip(t))
def carries(s:G.Shape,t:Nat,ws:A.Values,left:Nat,i:Nat) -> Rows: packed_rows(s,D.carries(t,ws,left,i))
def lines(s:G.Shape,t:Nat,p:A.Values,eps:Nat,mf:Nat) -> Rows: packed_rows(s,D.lines(t,p,eps,mf))

def product_row(+c: P.Check,start: A.Aff) -> H.Aff:
  +vs = P.ends(c)
  H.from_psc(P.row(c,start,E.mul(D.scalar(vs,0n),D.scalar(vs,1n))))

def pref(c: P.Check) -> A.Aff: A.slot(P.prefix(c),0n)

def stream_limbs(+s: G.Shape,offsets: List<&2,Nat>,+table: Nat,+point: F.Factors,+n: Nat,+gamma: X.E3,+scale: X.E3,acc: H.Aff) -> H.Aff:
  match offsets:
    case []: acc
    case x <> rest:
      term = H.shifted(s,0n,Nat.add(table,x),n,point,scale)
      stream_limbs(s,rest,table,point,n,gamma,E.mul(scale,gamma),H.plus(acc,term))

def squares(+s: G.Shape,+check: P.Check,ws: A.Values,+gamma: X.E3) -> Rows:
  +d = C.log_channels(s)
  plain = D.powers(d,P.half(),F.one())
  val = D.weighted(ws,gamma,plain,A.zero())
  +ends = P.ends(check)
  +count = Nat.div(C.channels(s),two(C.ls(s)))
  high_bits = Nat.sub(d,C.ls(s))
  pattern = T.eq(A.rev(F.take(X.E3,P.point(check),high_bits)))
  packed = stream_limbs(s,G.limbs(s),G.offset(s,2n),pattern,count,gamma,F.one(),H.zero())
  [product_row(check,val),H.minus(slot(ends,0n),slot(ends,1n)),H.minus(slot(ends,0n),packed)]

def ledger(+s: G.Shape,+ws: A.Values,+p: A.Values,+omega: X.E3,+check: P.Check) -> Rows:
  +v = P.ends(check)
  +tab = G.offset(s,8n)
  +q = G.offset(s,7n)
  start = H.from_psc(D.weighted(p,omega,F.one(),A.zero()))
  first = H.minus(H.from_psc(pref(check)),start)
  subst = H.from_psc(P.row(check,pref(check),D.products(v,omega)))
  ends : Rows = [H.minus(slot(v,0n),low(s,tab)),H.minus(slot(v,1n),high(s,tab)),H.minus(slot(v,2n),word(s,tab,80n,3n)),H.minus(slot(v,3n),word(s,tab,83n,3n))]
  first <> subst <> join(ends,join(carries(s,q,ws,9n,0n),lines(s,q,p,C.eps(s),C.mf(s))))

def norm_stream(+s: G.Shape,+keys: R.Keys,offsets: List<&2,Nat>,+table: Nat,+scale: X.E3,acc: H.Aff) -> H.Aff:
  match offsets:
    case []: acc
    case x <> tail:
      placed = H.placed(s,keys,0n,table,x,C.ls(s),scale)
      norm_stream(s,keys,tail,table,E.mul(scale,A.nat(256n)),H.plus(acc,placed))

def stream(+s: G.Shape,keys: R.Keys,+c: P.Check) -> Rows:
  +vs = P.ends(c)
  sx = norm_stream(s,keys,G.limbs(s),G.offset(s,3n),F.one(),H.zero())
  [product_row(c,pref(c)),H.minus(slot(vs,0n),recip(s,G.offset(s,9n))),H.minus(slot(vs,1n),sx)]

def norm(+s: G.Shape,h: R.Heard,k: R.Keys,link: Nat) -> IO(M.Equations):
  R.Heard{_,+ws,g,sq,p,o,row,n,_} = h
  do IO<M.Equations>:
    ok : Unit <- Header.require(Nat.is_eq(List.length(&2,Nat,G.limbs(s)),5n),"NO: head-norm-limbs")
    return H.section(join(squares(s,sq,ws,g),join(ledger(s,ws,p,o,row),stream(s,k,n))),link)

def logits(+s: G.Shape,h: R.Heard,link: Nat) -> M.Equations:
  R.Heard{_,_,_,_,_,_,_,_,+c} = h
  +d = C.channels(s)
  +t = G.offset(s,5n)
  +fs = T.eq(A.rev(List.drop(&2,X.E3,P.point(c),C.lt(s))))
  a = H.plus(H.shifted(s,0n,t,d,fs,F.one()),H.shifted(s,0n,Nat.add(t,d),d,fs,A.nat(256n)))
  H.section([product_row(c,pref(c)),H.minus(slot(P.ends(c),0n),a)],link)
