import Base
import ./base_check.bend as B
import ./extension.bend as E
import ./fold.bend as F
import ./fold_cs.bend as CS
import ./fold_verify.bend as FV
import ./leaf_walk.bend as W
import ./leaf_shape.bend as S
import ./row_tensor.bend as X
import ./segment_projection.bend as Project

# A stage observes the initial main form only through its width and final
# BASE. All intermediate target, mask, sample, and epsilon operations are
# replayed by FV.custom. Collect the very same low-bit coordinates here.
def gammas(events: FV.Events, rev: B.Elements) -> B.Elements:
  match events:
    case []: List.reverse(&2,E.E3,rev)
    case W.EntryRound{"FOLD round",_,s,_,_,_} <> tail: gammas(tail,FV.first(s) <> rev)
    case _ <> tail: gammas(tail,rev)

def base_width(stages: List<&2,S.Stage>) -> Nat:
  match stages:
    case [S.Stage{B.Code{_,n,_},_,_,_}]: CS.bits(n)
    case _ <> tail: base_width(tail)
    case []: 0n

type Basis is Data:
  Basis{places: F.Chunks, rows: F.Chunks, base_bits: Nat}

# A weight term arrives as [low place, surviving place, member row].
# Fold the two disjoint slices; deposit only the surviving place factors.
def write(high: F.Factors, row: F.Term, buf: Array<E.E3>) -> Array<E.E3>:
  F.Term{v,_} = row
  F.deposit(List.reverse(&2,F.Factor,high),0,v,buf)

def row(t: F.Term, r: F.Chunks, +n: Nat, buf: Array<E.E3>) -> Array<E.E3>:
  F.Term{w,+fs} = t
  v = F.project(r,F.Term{w,List.drop(&2,F.Factor,fs,n)})
  write(List.take(&2,F.Factor,fs,n),v,buf)

def deposit(xs: F.Form, +basis: Basis, buf: Array<E.E3>) -> Array<E.E3>:
  match xs:
    case []: buf
    case t <> tail:
      Basis{p,r,n} = basis
      deposit(tail,basis,row(F.project(p,t),r,n,buf))

def scaled(xs: List<&1,E.E3>, +s: E.E3, rev: B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,E.E3,rev)
    case v <> rest: scaled(rest,s,F.times(v,s) <> rev)

# Group coordinates are [row, prefix, place]. Every weight belongs to the
# same aligned member, so the prefix scales the completed table just once.
def project(weights: F.Form, +gs: B.Elements, +r: Nat, +k: Nat, +n: Nat, off: Nat) -> F.Form:
  row = List.take(&2,E.E3,gs,r)
  prefix = List.take(&2,E.E3,List.drop(&2,E.E3,gs,r),Nat.sub(k,r))
  scale = X.entry(X.eq(prefix),Nat.div(off,CS.size(r)),F.one())
  p = F.prepare(List.drop(&2,E.E3,gs,k))
  values = deposit(weights,Basis{p,F.prepare(row),n},Array.new(E.E3,n,F.zero()))
  basis: Project.Basis = Project.Basis{[],F.count(E.E3,gs,0n),n}
  Project.lift(basis,scaled(Array.to_list(E.E3,values),scale,[]))

def fits(weights: F.Form, +r: Nat, +places: Nat, +k: Nat, +n: Nat, fixed: Nat) -> Bool:
  Nat.is_le(r,k) && Nat.is_le(n,places) && Nat.is_eq(Nat.add(fixed,n),Nat.add(k,places)) &&
    F.fits(weights,Nat.add(places,r))
