import Base
import ./extension.bend as X
import ./fold.bend as F
import ./sumcheck.bend as E
import ./base_check.bend as B
import ./row_tensor.bend as T
import ./key_stage_lookup_rows.bend as L
import ./key_stage_matrix.bend as Matrix
import ./oracle_sample.bend as Sample
import ./segment_attention_aff.bend as A
import ./segment_model.bend as M
import ./head_types.bend as G
import ./head_catalog.bend as C
import ./head_rounds.bend as R

# An affine expression on the single logical U3 array is constrained to zero.
type Aff is Data:
  Aff{terms: F.Form, masks: L.Masks, c: X.E3}

def constant(v: X.E3) -> Aff: Aff{[],[],v}
def zero() -> Aff: constant(F.zero())
def from_psc(v: A.Aff) -> Aff:
  A.Aff{_,ms,c} = v
  Aff{[],ms,c}

def slot(v: A.Value) -> Aff: from_psc(A.hidden(v))

def add(a: Aff, b: Aff, +s: X.E3) -> Aff:
  Aff{ts,ms,c} = a
  Aff{ys,ns,d} = b
  Aff{T.scale(ys,s,ts),L.sum(L.scale(ns,s),ms),E.add(c,E.mul(s,d))}

def minus(a: Aff,b: Aff) -> Aff: add(a,b,E.negate(F.one()))
def scale(a: Aff,s: X.E3) -> Aff: add(zero(),a,s)
def plus(a: Aff,b: Aff) -> Aff: add(a,b,F.one())

def cell(s: G.Shape, index: Nat) -> Aff:
  Aff{[F.Term{F.one(),T.choice(Sample.row_bits(C.u3(s)),index)}],[],F.zero()}

def block(bits: Nat, source: Nat, dest: Nat, n: Nat, f: F.Factors, w: X.E3, acc: F.Form) -> F.Form:
  +width = bits
  Matrix.stretch(1n+Nat.mul(2n,width),width,source,dest,n,f,w,acc)

def shifted(s: G.Shape, source: Nat, dest: Nat, n: Nat, point: F.Factors, weight: X.E3) -> Aff:
  Aff{block(Sample.row_bits(C.u3(s)),source,dest,n,point,weight,[]),[],F.zero()}

def spread_runs(rs: List<&2,G.Run>, +point: F.Factors, +bits: Nat, +divisor: Nat, dest: Nat, +w: X.E3, acc: F.Form) -> F.Form:
  match rs:
    case []: acc
    case G.Run{j,n} <> tail:
      +len = Nat.div(n,divisor)
      +at = dest
      moved = block(bits,Nat.div(j,divisor),at,len,point,w,acc)
      spread_runs(tail,point,bits,divisor,Nat.add(at,len),w,moved)

def fill(g: G.Segment, k: R.Keys, lt: Nat, bits: Nat, dest: Nat, +skip: Nat, w: X.E3) -> Aff:
  G.Segment{_,j,_,rs} = g
  point = T.eq(List.drop(&2,X.E3,R.column(k,lt,j),skip))
  Aff{spread_runs(rs,point,bits,Nat.pow(2n,skip),dest,w,[]),[],F.zero()}

# Segment ordinal follows head-profile.py. tableAt is the absolute U3 offset,
# index in its entries, block_bits 0 for each entry or ls for a block of S2.
def placed(+s: G.Shape, k: R.Keys, seg: Nat, tableAt: Nat, index: Nat, block_bits: Nat, scl: X.E3) -> Aff:
  fill(G.segment(s,seg),k,C.lt(s),Sample.row_bits(C.u3(s)),Nat.add(tableAt,index),block_bits,scl)

def equation(a: Aff, link: Nat) -> M.Aff:
  Aff{ts,ms,c} = a
  M.Aff{[M.Read{link,"U3",ts}],ms,E.negate(c)}

def section(xs: List<&2,Aff>, +link: Nat) -> M.Equations:
  match xs:
    case []: []
    case x <> tail: equation(x,link) <> section(tail,link)
