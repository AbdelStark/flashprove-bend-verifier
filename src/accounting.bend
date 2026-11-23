import Base
import ./accounting_catalog.bend as C
import ./plan_types.bend as P
import ./header.bend as Header
import ./plan_catalog.bend as Catalog
import ./hash_bytes.bend as H

def matches(xs: List<&2,U32>) -> Bool:
  match xs:
    case []: True{}
    case x <> tail: U32.is_eq(x,0) && matches(tail)

# Compare a little-endian integer to 2^bit, exactly, even at a rounding boundary.
def below(xs: List<&2,U32>,+bit: Nat,lower_zero: Bool,last: Bool) -> Bool:
  match xs last:
    case [] _: True{}
    case +x <> tail True{}:
      +limit = U32.shln(1,bit)
      matches(tail) && (U32.is_lt(x,limit) || (U32.is_eq(x,limit) && lower_zero))
    case x <> tail False{}:
      +next = Nat.sub(bit,32n)
      below(tail,next,lower_zero && U32.is_eq(x,0),Nat.is_lt(next,32n))

def below_power(xs: List<&2,U32>,+bit: Nat) -> Bool:
  below(xs,bit,True{},Nat.is_lt(bit,32n))

def bound(b: C.Bound,+target: Nat) -> Bool:
  C.Bound{+work,scale,words} = b
  +den = Nat.add(scale,work)
  Nat.is_le(work,32n) && Nat.is_ge(den,target) && below_power(words,Nat.sub(den,target))

def errors(xs: List<&2,C.Bound>,+target: Nat) -> Bool:
  match xs:
    case []: True{}
    case x <> tail: bound(x,target) && errors(tail,target)

def stage(s: C.Stage) -> Bool:
  match s:
    case C.Stage{+target,rounds,_,_,_,b <> bs}:
      Nat.is_ge(target,128n) && Nat.is_gt(rounds,0n) && bound(b,target) && errors(bs,target)
    case _: False{}

def admitted(xs: List<&2,C.Stage>) -> Bool:
  match xs:
    case [key,entry,proof]: stage(key) && stage(entry) && stage(proof)
    case _: False{}

def selected(opt: Maybe<&2,P.Profile>) -> IO(Unit):
  match opt:
    case Some{profile}: Header.require(admitted(C.stages(profile)),"NO: security-bits")
    case None{}: IO.die(Unit,1,"NO: unsupported-configuration")

def check(hash: H.Bytes) -> IO(Unit):
  selected(Catalog.select(H.u32s(hash)))
