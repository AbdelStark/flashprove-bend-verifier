import Base
import ./u3_series.bend as U
import ./base_check.bend as B
import ./extension.bend as X
import ./fold.bend as F
import ./sumcheck.bend as E
import ./segment_model.bend as M
import ./smallness_geometry.bend as G
import ./oracle_sample.bend as Sample
import ./transcript.bend as T

# §13.9 events 4–8. A product over every index in [0,n) is nonzero
# precisely when each endpoint selected by at least one such index is.
def prefix(fs: F.Factors,+limit: Nat,pow: Nat) -> Bool:
  match fs:
    case []: True{}
    case +f <> tail:
      lo = F.at_bit(f,False{})
      hi = F.at_bit(f,True{})
      +p = pow
      Bool.not(T.is_zero(lo)) && (Nat.is_le(limit,p) || Bool.not(T.is_zero(hi))) && prefix(tail,limit,Nat.mul(2n,p))

def packed_rows(shapes: List<&2,G.Matrix>,acc: Nat) -> Nat:
  match shapes:
    case []: acc
    case G.Matrix{_,_,m,_} <> tail: packed_rows(tail,Nat.max(acc,Nat.div(Nat.add(m,2n),3n)))

# For nonzero z the powers 1..z^(n-1) are distinct iff z^j != 1 for
# every 1 <= j < n. All matrices share z, so the largest covers them.
def distinct(n: Nat,+z: X.E3,current: X.E3) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +v = current
      Bool.not(B.equal(v,F.one())) && distinct(k,z,E.mul(z,v))

def order(step: X.E3,n: Nat) -> Bool:
  +v = step
  Bool.not(T.is_zero(v)) && distinct(Nat.sub(n,1n),v,v)

def all(n: Nat,values: List<X.E3>) -> Bool:
  match n values:
    case 0n _: True{}
    case 1n+k x <> rest: Bool.not(T.is_zero(x)) && all(k,rest)
    case _ _: False{}

def form(+terms: F.Form,+length: Nat) -> Bool:
  +bits = Sample.row_bits(length)
  F.fits(terms,bits) && all(length,Array.to_list(X.E3,F.populate(terms,Array.new(X.E3,bits,F.zero()))))

def column(axis: String) -> Bool: String.eq(axis,"U3")

def u3(xs: List<&2,M.Read>,acc: F.Form) -> F.Form:
  match xs:
    case []: acc
    case M.U3Run{_,s} <> tail: u3(tail,List.reverse.go(&2,F.Term,U.expand(s),acc))
    case M.Read{_,name,terms} <> tail:
      +prev = acc
      more = Bool.pick(F.Form,column(name),List.reverse.go(&2,F.Term,terms,prev),prev)
      u3(tail,more)
