import Base
import ./fold.bend as F
import ./row_tensor.bend as T
import ./extension.bend as X
import ./sumcheck.bend as E
import ./pow2.bend as P2

# An affine read already names an integer cell. Keep that address through BAT
# instead of constructing one Low/High factor per bit and decoding them at placement.
# Carry the common BAT-sigma scale once for the whole list.
type Cell is Data:
  Cell{index: Nat, weight: X.E3}
type Points is Data:
  Points{cells: List<&2,Cell>, bits: Nat, scale: X.E3}

def scaled(p: Points,s: X.E3) -> Points:
  Points{xs,bits,w} = p
  Points{xs,bits,E.mul(w,s)}

def width(p: Points,b: Nat) -> Bool:
  Points{_,bits,_} = p
  Nat.is_eq(bits,b)

def terms(xs: List<&2,Cell>,+bits: Nat,+s: X.E3,out: F.Form) -> F.Form:
  match xs:
    case []: out
    case Cell{i,w} <> rest: terms(rest,bits,s,F.Term{F.times(w,s),T.choice(bits,i)} <> out)

def expand(p: Points) -> F.Form:
  Points{xs,bits,s} = p
  terms(xs,bits,s,[])

# Tensor.choice(bits, i) uses exactly the low bits, even when two addresses alias.
# Add to the existing slot so repeated reads can cancel. The caller tests the
# final sum at every genuine cell after all reads have been deposited.
def scatter(xs: List<&2,Cell>,+mask: U32,+s: X.E3,buf: Array<X.E3>) -> Array<X.E3>:
  match xs:
    case []: buf
    case Cell{i,w} <> rest:
      +at = U32.and(U32.from_nat(i),mask)
      scatter(rest,mask,s,F.summed(Array.get(X.E3,buf,at),at,F.times(w,s)))

def write(p: Points,buf: Array<X.E3>) -> Array<X.E3>:
  Points{xs,bits,s} = p
  scatter(xs,U32.from_nat(Nat.sub(P2.pow2(bits),1n)),s,buf)
