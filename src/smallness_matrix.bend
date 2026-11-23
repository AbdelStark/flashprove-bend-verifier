import Base
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F
import ./key_stage_lookup.bend as KL
import ./key_stage_psc.bend as PSC
import ./smallness_geometry.bend as G
import ./smallness_columns.bend as C
import ./smallness_packing.bend as P
import ./smallness_form.bend as SF
import ./segment_model.bend as M
import ./row_tensor.bend as Tensor
import ./oracle_sample.bend as Sample
import ./transcript.bend as T
import ./header.bend as Header

# One column gamma is shared by all reads on its source matrix. These are
# the field-valued folds of the genuine 128 ternary challenges per column.
type Matrix is Data:
  Matrix{shape: G.Matrix, gamma: B.Elements, row_offset: Nat, first: Nat}
type State is Data:
  State{matrices: List<&2,Matrix>, stream: T.Stream, rows: Nat, columns: Nat, next: Nat}
type World is Data:
  World{link: Nat, mz: Nat, u3_bits: Nat, chi: X.E3, start: Nat, step: X.E3, u_axis: F.Factors, total_u: X.E3}

def rows(m: G.Matrix) -> Nat:
  G.Matrix{_,_,n,_} = m
  n

def cols(m: G.Matrix) -> Nat:
  G.Matrix{_,_,_,n} = m
  n

def prepare(shapes: List<&2,G.Matrix>, +powers: B.Elements, state: State) -> State:
  match shapes state:
    case [] State{ms,s,r,c,f}: State{List.reverse(&2,Matrix,ms),s,r,c,f}
    case +g <> rest State{ms,s,+r,c,+f}:
      +m = rows(g)
      +k = cols(g)
      +got = C.columns(k,powers,s,[])
      sym = Nat.div(Nat.add(m,2n),3n)
      span = Nat.mul(128n,Nat.pow(2n,Sample.row_bits(sym)))
      next: State = State{Matrix{g,T.value(B.Elements,got),r,f} <> ms,T.after(B.Elements,got),Nat.add(r,m),Nat.add(c,k),Nat.add(f,span)}
      prepare(rest,powers,next)

def lead(world: World, ordinal: Nat, first: Nat) -> X.E3:
  World{_,_,_,chi,all,_,_,_} = world
  KL.power(48n,Nat.add(Nat.sub(all,ordinal),first),chi,F.one())

def make_world(link: Nat, mz: Nat, bits: Nat, +chi: X.E3, start: Nat, powers: B.Elements) -> World:
  World{link,mz,bits,chi,start,KL.power(8n,128n,chi,F.one()),KL.powers(7n,chi),PSC.sum(powers,F.zero())}

def step(w: World) -> X.E3:
  World{_,_,_,_,_,z,_,_} = w
  z

def tie_parts(weights: F.Form, mat: Matrix, world: World, power: X.E3) -> M.Aff:
  Matrix{G.Matrix{owner,name,+m,k},gam,offset,_} = mat
  World{link,mz,_,_,_,+step,axis,sum} = world
  +sc = power
  right = SF.dense(gam,KL.powers(Sample.row_bits(Nat.div(Nat.add(m,2n),3n)),step),Sample.row_bits(k),0n,E.negate(sc),[])
  left = SF.digits(weights,axis,m,offset,mz,sc)
  target = E.mul(sc,E.mul(KL.small(131072n),E.mul(sum,P.total(m,step))))
  M.Aff{[M.Read{link,"ZZ",left},M.Read{owner,name,right}],[],target}

def tie(+mat: Matrix, +world: World, n: Nat) -> IO(M.Aff):
  Matrix{G.Matrix{_,_,m,_},_,_,first} = mat
  World{_,_,_,_,_,step,_,_} = world
  do IO<M.Aff>:
    weights : F.Form <- P.left(Sample.row_bits(m),step)
    return tie_parts(weights,mat,world,lead(world,n,first))

def ties(ms: List<&2,Matrix>, +world: World, ordinal: Nat, rev: M.Equations) -> IO(M.Equations):
  match ms:
    case []: IO.pure(M.Equations,List.reverse(&2,M.Aff,rev))
    case m <> rest:
      +n = ordinal
      do IO<M.Equations>:
        row : M.Aff <- tie(m,world,0n)
        ties(rest,world,1n+n,row <> rev)
