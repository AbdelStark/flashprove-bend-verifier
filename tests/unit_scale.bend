import Base
import ../src/extension.bend as X
import ../src/sumcheck.bend as E
import ../src/base_check.bend as B
import ../src/fold.bend as F

# by(unit(s),s,w) must equal mul(s,w) for one, minus one and any other s,
# including operands with zero and maximal coefficients.
def operands() -> List<&2,X.E3>:
  [F.zero(),F.one(),E.negate(F.one()),X.E3{0,0,0,7,0,0},X.E3{4294967295,0,4294967295,0,4294967294,4294967295},
   X.E3{0,5,1,2,3,4},X.E3{17,0,0,0,0,9}]

def all(xs: List<&2,X.E3>, +s: X.E3) -> Bool:
  match xs:
    case []: True{}
    case +w <> tail: B.equal(E.by(E.unit(s),s,w),E.mul(s,w)) && all(tail,s)

def each(ss: List<&2,X.E3>) -> Bool:
  match ss:
    case []: True{}
    case s <> tail: all(operands(),s) && each(tail)

def main() -> IO(Unit):
  +m = E.negate(F.one())
  IO.print(Bool.show(each(operands())) ++ " " ++ U32.show(E.unit(F.one())) ++ U32.show(E.unit(m)) ++ U32.show(E.unit(X.E3{0,1,0,0,0,1})) ++ U32.show(E.unit(X.E3{4294967295,0,0,1,0,0})))

#|True 1200
