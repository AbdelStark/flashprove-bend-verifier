import Base
import ../src/u3_series.bend as U
import ../src/base_check.bend as B
import ../src/fold.bend as F
import ../src/extension.bend as X
import ../src/key_stage_lookup.bend as K

# R13.4. The independent logical-row evaluator expresses this sequence as
# shifted separable factors. Compare all 32 cells, including an unaligned
# start, a non-power-of-two segment count, overlap and untouched padding.
def equal(a: List<X.E3>,b: List<X.E3>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x,xs} Con{y,ys}: B.equal(x,y) && equal(xs,ys)
    case _ _: False{}

def same(+a: U.Series,+b: U.Series) -> Bool:
  direct = U.write(b,U.write(a,Array.new(X.E3,5n,F.zero())))
  syms = F.cat(F.Term,U.expand(a),U.expand(b))
  symbols = F.populate(syms,Array.new(X.E3,5n,F.zero()))
  equal(Array.to_list(X.E3,direct),Array.to_list(X.E3,symbols))

def main() -> IO(Unit):
  +a: U.Series = U.Series{[K.small(7n),K.small(11n),K.small(13n)],5n,3n,5n,X.E3{0,3,0,4,0,7},K.small(17n)}
  b: U.Series = U.Series{[K.small(5n),F.zero()],3n,12n,5n,F.one(),K.small(23n)}
  point: U.Series = U.Series{[F.zero(),F.one()],1n,23n,5n,F.zero(),F.one()}
  IO.print(Bool.show(U.fits(a,5n,18n) && Bool.not(U.fits(a,5n,17n)) &&
    Bool.not(U.fits(a,4n,32n)) && same(a,b) && same(a,point)))

#|True
