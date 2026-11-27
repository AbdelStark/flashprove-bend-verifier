import Base
import ./u3_series.bend as U
import ./segment_coverage.bend as Cover
import ./base_check.bend as B
import ./extension.bend as X
import ./fold.bend as F
import ./sumcheck.bend as E
import ./row_tensor.bend as Tensor
import ./smallness_columns.bend as C
import ./smallness_matrix.bend as Mat
import ./smallness_geometry.bend as G
import ./smallness_form.bend as SF
import ./smallness_packing.bend as Pack
import ./segment_model.bend as M
import ./segment_layout.bend as Layout
import ./key_stage_lookup.bend as K
import ./oracle_sample.bend as Sample
import ./header.bend as Header
import ./pow2.bend as P2

# Once a read at ordinal j has entered BAT-sigma, chi^j cancels the
# chi^(-j) in leadF. Consecutive row segments of a single functional
# therefore have the geometric progression (chi^128)^sg without division.
type Sums is Data:
  Sums{reads: List<&2,M.Read>, rhs: X.E3, count: Nat, entries: Nat, power: X.E3, matrix_weights: F.Form}

def with_high(rows: F.Form,+high: F.Factors) -> F.Form:
  match rows:
    case []: []
    case F.Term{w,f} <> rest: F.Term{w,Layout.cat(f,high)} <> with_high(rest,high)

def after(s: Pack.Sum) -> X.E3:
  Pack.Sum{v,_} = s
  v

def sum(s: Pack.Sum) -> X.E3:
  Pack.Sum{_,v} = s
  v

def read(fn_: M.Functional, mat: Mat.Matrix, world: Mat.World, state: Sums) -> IO(Sums):
  M.Functional{_,+length,+phi,at} = fn_
  Mat.Matrix{G.Matrix{_,_,+rows,k},gam,off,_} = mat
  Mat.World{+link,mz,bits,_,_,+step,axis,sum_u} = world
  Sums{fs,rhs,n,entries,+lead,test} = state
  +segments = Nat.div(rows,Nat.max(1n,length))
  +high = K.powers(Sample.row_bits(segments),step)
  +progression = Pack.geometric(32n,segments,step)
  +delta = E.mul(lead,E.mul(K.small(131072n),E.mul(sum_u,SF.total(phi,F.zero()))))
  +weights = with_high(phi,high)
  zz = SF.digits(weights,axis,rows,off,mz,lead)
  u3: U.Series = U.Series{gam,segments,at,bits,step,E.negate(lead)}
  do IO<Sums>:
    valid : Unit <- Header.require(Nat.is_eq(P2.pow2(Sample.row_bits(length)),length) &&
      Nat.is_eq(Nat.mul(length,segments),rows) && F.fits(phi,Sample.row_bits(length)),"NO: segment-functional-shape")
    return Sums{M.U3Run{link,u3} <> M.Read{link,"ZZ",zz} <> fs,E.add(rhs,E.mul(delta,sum(progression))),
      Nat.add(n,segments),Nat.add(entries,Nat.mul(k,segments)),E.mul(lead,after(progression)),Tensor.scale(weights,lead,test)}

def matrix(fn_: M.Functional) -> Nat:
  M.Functional{x,_,_,_} = fn_
  x

def for_matrix(fns: M.Functionals,+mu: Nat,+mat: Mat.Matrix,+world: Mat.World,+state: Sums) -> IO(Sums):
  match fns:
    case []: IO.pure(Sums,state)
    case +fn_ <> +rest:
      run = Bool.pick(Unit -> IO(Sums),Nat.is_eq(matrix(fn_),mu),
        _ => read(fn_,mat,world,state),_ => IO.pure(Sums,state))
      do IO<Sums>:
        next : Sums <- run(Unit{})
        for_matrix(rest,mu,mat,world,next)

def nonzero(xs: B.Elements) -> Bool:
  match xs:
    case []: True{}
    case x <> tail: Bool.not(B.equal(x,F.zero())) && nonzero(tail)

def valid_gamma(mat: Mat.Matrix) -> Bool:
  Mat.Matrix{_,g,_,_} = mat
  nonzero(g)

def uses(fns: M.Functionals,+mu: Nat) -> Bool:
  match fns:
    case []: False{}
    case f <> tail: Nat.is_eq(matrix(f),mu) || uses(tail,mu)

def bound(s: Sums,m: Mat.Matrix) -> IO(Sums):
  Sums{reads,rhs,n,entries,p,weights} = s
  Mat.Matrix{sh,_,_,_} = m
  do IO<Sums>:
    ok : Unit <- Header.require(Cover.form(weights,Mat.rows(sh)),"NO: segment-zero-ZZ-read")
    return Sums{reads,rhs,n,entries,p,[]}

def values(ms: List<&2,Mat.Matrix>,+fns: M.Functionals,mu: Nat,+world: Mat.World,state: Sums) -> IO(Sums):
  match ms:
    case []: IO.pure(Sums,state)
    case +m <> rest:
      +i = mu
      do IO<Sums>:
        valid : Unit <- Header.require(Bool.not(uses(fns,i)) || valid_gamma(m),"NO: segment-smallness-zero-column")
        next : Sums <- for_matrix(fns,i,m,world,state)
        checked : Sums <- bound(next,m)
        values(rest,fns,1n+i,world,checked)
