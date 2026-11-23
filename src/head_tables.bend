import Base
import ./head_types.bend as G
import ./head_catalog.bend as C
import ./head_rounds.bend as R
import ./head_coverage.bend as V
import ./segment_model.bend as M
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./segment_planes.bend as Planes
import ./row_tensor.bend as T
import ./fold.bend as F
import ./extension.bend as X
import ./base_check.bend as B

def eq(low: B.Elements) -> F.Form: [F.Term{F.one(),T.eq(low)}]

def append(xs: F.Form, +more: F.Factors) -> F.Form:
  match xs:
    case []: []
    case F.Term{w,fs} <> tail: F.Term{w,F.cat(F.Factor,fs,more)} <> append(tail,more)

def ones(n: Nat) -> F.Factors: List.replicate(F.Factor,n,F.Factor{F.one(),F.one()})

def partitions(sizes: List<&2,Nat>, +len: Nat, +form: F.Form, matrix: Nat, offset: Nat) -> M.Functionals:
  match sizes:
    case []: []
    case n <> tail:
      +m = matrix
      +o = offset
      M.Functional{m,len,form,o} <> partitions(tail,len,form,1n+m,Nat.add(o,n))

def cells(t: G.Table, form: F.Form) -> M.Functionals:
  G.Table{m,len,off,sizes} = t
  partitions(sizes,len,form,m,off)

def all(forms: List<&2,F.Form>, +s: G.Shape, i: Nat) -> M.Functionals:
  match forms:
    case []: []
    case fs <> rest:
      +j = i
      F.cat(M.Functional,cells(G.table(s,j),fs),all(rest,s,1n+j))

def functions(+s: G.Shape,k: R.Keys,h: R.Heard,+cov: V.Covered) -> M.Functionals:
  R.Keys{_,+leaf,+tok} = k
  R.Heard{pv,_,_,sqrt,_,_,row,+norm,logits} = h
  +ls = C.ls(s)
  +lt = C.lt(s)
  +la = Nat.add(ls,lt)
  +nt = A.rev(P.point(norm))
  +covered = V.window(cov,T.eq(A.rev(tok)))
  phi = append(covered,ones(ls))
  yn = F.cat(X.E3,nt,A.slice(leaf,lt,ls))
  # The third and fourth functionals refer to the previous G link's stream.
  forms: List<&2,F.Form> = [eq(F.take(X.E3,leaf,la)),phi,eq(F.take(X.E3,A.rev(P.point(sqrt)),la)),
    eq(yn),eq(A.rev(tok)),eq(A.rev(F.take(X.E3,P.point(logits),lt))),eq(A.rev(tok)),eq(A.rev(pv)),
    eq(A.rev(P.point(row))),eq(nt),covered,V.window(cov,ones(lt))]
  all(forms,s,0n)
