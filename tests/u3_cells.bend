import Base
import ../src/u3_cells.bend as C
import ../src/extension.bend as X
import ../src/fold.bend as F
import ../src/segment_coverage.bend as Cover
import ../src/sumcheck.bend as E
import ../src/base_check.bend as B

def same(a: List<X.E3>,b: List<X.E3>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x,xs} Con{y,ys}: B.equal(x,y) && same(xs,ys)
    case _ _: False{}

def compare(+p: C.Points) -> Bool:
  direct = C.write(p,Array.new(X.E3,2n,F.zero()))
  terms = F.populate(C.expand(p),Array.new(X.E3,2n,F.zero()))
  same(Array.to_list(X.E3,direct),Array.to_list(X.E3,terms))

def main() -> IO(Unit):
  # Fixed addresses at 1 and 5 have the same two low bits. A cancellation
  # there must still fail the check on the final batched coefficients.
  +x : X.E3 = X.E3{0,5,0,3,0,11}
  +ps : C.Points = C.Points{[C.Cell{0n,F.one()},C.Cell{1n,x},C.Cell{5n,E.negate(x)},
    C.Cell{2n,F.one()},C.Cell{3n,x}],2n,F.one()}
  +scaled = C.scaled(ps,x)
  direct = C.write(scaled,Array.new(X.E3,2n,F.zero()))
  IO.print(Bool.show(C.width(ps,2n) && Bool.not(C.width(ps,3n)) && compare(scaled) &&
    Bool.not(Cover.all(4n,Array.to_list(X.E3,direct)))))

#|True
