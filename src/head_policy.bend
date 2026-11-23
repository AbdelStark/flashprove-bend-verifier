import Base
import ./head_types.bend as G
import ./head_catalog.bend as C
import ./head_aff.bend as H
import ./head_rounds.bend as R
import ./head_coverage.bend as V
import ./segment_attention_aff.bend as A
import ./segment_model.bend as M
import ./fold.bend as F
import ./sumcheck.bend as E
import ./extension.bend as X
import ./key_stage_lookup.bend as Int
import ./head_tables.bend as Tables

def digits(n: Nat, +s: G.Shape, i: Nat, +avg: X.E3, +w: X.E3, acc: H.Aff) -> H.Aff:
  match n:
    case 0n: acc
    case 1n+k:
      +j = i
      digit = H.plus(H.cell(s,j),H.constant(avg))
      digits(k,s,1n+j,avg,E.mul(w,A.nat(256n)),H.add(acc,digit,w))

def range(field: Nat) -> Nat & Nat:
  match field:
    case 0n: (0n,5n)
    case 1n: (5n,1n)
    case 2n: (6n,5n)
    case 3n: (11n,5n)
    case 4n: (16n,2n)
    case _: (18n,3n)

def term(s: G.Shape, cell: Nat, dims: Nat & Nat, w: X.E3) -> H.Aff:
  (off,n) = dims
  digits(n,s,Nat.add(cell,Nat.add(99n,off)),E.mul(A.nat(128n),w),F.one(),H.zero())

def gap(+s: G.Shape, table: Nat, field: Nat, w: X.E3) -> H.Aff:
  term(s,G.offset(s,table),range(field),w)

def exp_cells(n: Nat, +s: G.Shape, off: Nat, +length: Nat, +j: Nat, +w: X.E3, acc: H.Aff) -> H.Aff:
  match n:
    case 0n: acc
    case 1n+left:
      +at = off
      fs = Tables.ones(j)
      a = H.shifted(s,0n,at,length,fs,w)
      exp_cells(left,s,Nat.add(at,length),length,j,E.mul(w,A.nat(256n)),H.plus(acc,a))

def equations(+s: G.Shape, +cov: V.Covered, k: R.Keys, link: Nat) -> M.Equations:
  +count = V.ncost(cov)
  +n = A.nat(count)
  +erc = V.cost(cov,R.tokens(k))
  a = H.minus(H.plus(H.add(gap(s,11n,0n,n),gap(s,11n,1n,n),A.nat(C.clip(s))),gap(s,11n,2n,n)),
    H.constant(E.mul(n,A.nat(C.theta(s)))))
  b = H.minus(H.plus(gap(s,11n,1n,n),gap(s,11n,4n,n)),H.constant(A.nat(Bool.pick(Nat,Nat.is_eq(count,0n),0n,C.cap(s)))))
  c = H.minus(H.plus(gap(s,10n,0n,erc),gap(s,10n,3n,erc)),H.constant(E.mul(erc,A.nat(C.clip(s)))))
  +jv = C.jv(s)
  +block = A.size(C.ls(s))
  +len = Nat.div(jv,block)
  start = Nat.add(G.offset(s,1n),Nat.div(Nat.add(Nat.mul(4n,C.channels(s)),Nat.mul(3n,jv)),block))
  adjusted = F.sub(E.mul(A.nat(8421505n),A.nat(jv)),E.mul(A.nat(1n+Nat.sub(jv,C.vocab(s))),A.nat(A.size(C.family(s)))))
  end = H.plus(gap(s,10n,5n,erc),H.constant(E.mul(erc,adjusted)))
  d = exp_cells(3n,s,start,len,U32.log2(U32.from_nat(len)),F.one(),end)
  H.section([a,b,c,d],link)
