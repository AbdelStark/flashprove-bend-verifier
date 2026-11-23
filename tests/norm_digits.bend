import Base
import ../src/norm_digits.bend as D
import ../src/segment_attention_aff.bend as A
import ../src/extension.bend as X
import ../src/sumcheck.bend as E
import ../src/fold.bend as F
import ../src/base_check.bend as B

# R11.2, "A norm's row of digits": the stored cells are unsigned digits
# minus 128. Carry 1 occupies six little-endian digits with bias 2^47.
# The first convolution equation sets W0 = digit[0] + 256*carry[1].
def raw(i:Nat,+changed:Bool) -> Nat:
  match i:
    case 0n: 5n
    case 10n: Bool.pick(Nat,changed,4n,3n)
    case 15n: 128n
    case 80n: 1n
    case 82n: 2n
    case 85n: 3n
    case _: 0n

def eval(cs:List<&2,A.Cell>,+changed:Bool,acc:X.E3) -> X.E3:
  match cs:
    case []: acc
    case A.Cell{i,w} <> tail:
      v = F.sub(A.nat(raw(i,changed)),A.nat(128n))
      eval(tail,changed,E.add(acc,E.mul(w,v)))

def value(a:A.Aff,changed:Bool) -> X.E3:
  A.Aff{cs,_,x} = a
  eval(cs,changed,x)
def held(cs:A.Equations,changed:Bool) -> Bool:
  match cs:
    case [a]: B.equal(value(a,changed),F.zero())
    case _: False{}

def main() -> IO(Unit):
  +cs = D.carries(0n,[A.Value{A.nat(773n),0n,F.one()}],1n,0n)
  do IO<Unit>:
    IO.print(Bool.show(held(cs,False{})))
    IO.print(Bool.show(held(cs,True{})))
    IO.print(Bool.show(B.equal(value(D.recip(0n),False{}),X.E3{768,131073,0,0,0,0})))
#|True
#|False
#|True
