import Base
import ../src/segment_model.bend as M
import ../src/segment_u3.bend as Dense
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

def unrelated(xs: List<&2,M.Read>) -> Bool:
  match xs:
    case [M.Read{4n,"ZZ",[]}]: True{}
    case _: False{}

# Three genuine cells occupy a four-cell envelope. A symbolic contribution
# cancels a sparse one at index 1; the zero in padding cannot affect coverage.
def mixed() -> Bool:
  points: C.Points = C.Points{[C.Cell{0n,F.one()},C.Cell{Nat.add(4294967295n,2n),F.one()},C.Cell{2n,F.one()}],2n,F.one()}
  +cells: M.Read = M.U3Cells{4n,points}
  tensor: M.Read = M.Read{4n,"U3",[F.Term{E.negate(F.one()),[F.High{},F.Low{}]}]}
  +rs: List<&2,M.Read> = [cells,tensor,M.Read{4n,"ZZ",[]}]
  +ref = Cover.u3(rs,[])
  direct = Dense.populate(rs,Array.new(X.E3,2n,F.zero()))
  expanded = F.populate(ref,Array.new(X.E3,2n,F.zero()))
  Dense.local(rs,4n,2n,3n) && Bool.not(Dense.local(rs,5n,2n,3n)) &&
    Bool.not(Dense.local(rs,4n,3n,3n)) && unrelated(Dense.others(rs)) &&
    same(Array.to_list(X.E3,direct),Array.to_list(X.E3,expanded)) &&
    Cover.form(Cover.u3([cells],[]),3n) && Bool.not(Cover.form(ref,3n)) &&
    Bool.not(Cover.form(Cover.u3([cells],[]),5n))

def main() -> IO(Unit):
  # Fixed addresses at 1 and 5 have the same two low bits. A cancellation
  # there must still fail the check on the final batched coefficients.
  +x : X.E3 = X.E3{0,5,0,3,0,11}
  +ps : C.Points = C.Points{[C.Cell{0n,F.one()},C.Cell{1n,x},C.Cell{5n,E.negate(x)},
    C.Cell{2n,F.one()},C.Cell{3n,x}],2n,F.one()}
  +scaled = C.scaled(ps,x)
  direct = C.write(scaled,Array.new(X.E3,2n,F.zero()))
  values = Array.to_list(X.E3,direct)
  # (5 + 3X + 11X²)² = 157 + 272X + 119X² in X³ = 2.
  expected: List<X.E3> = [x,F.zero(),x,X.E3{0,157,0,272,0,119}]
  IO.print(Bool.show(same(values,expected) && C.width(ps,2n) && Bool.not(C.width(ps,3n)) && compare(scaled) && mixed()))

#|True
