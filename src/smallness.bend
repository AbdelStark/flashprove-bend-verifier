import Base
import ./segment_coverage.bend as Cover
import ./smallness_columns.bend as C
import ./smallness_geometry.bend as G
import ./smallness_matrix.bend as Mat
import ./smallness_reads.bend as R
import ./segment_digits.bend as D
import ./segment_model.bend as M
import ./base_check.bend as B
import ./extension.bend as X
import ./fold.bend as F
import ./transcript.bend as T
import ./key_stage_openings.bend as K
import ./oracle_sample.bend as O
import ./header.bend as Header

# Ordinary digit equations occupy consecutive positions after the model
# prefix. The tie and read contributions already include BAT-sigma's powers,
# which cancel the ordinal in leadF (R11.1, “The equations”).
type Contribution is Data:
  Contribution{digits: M.Equations, ties: M.Equations, reads: M.Aff, listed: Nat, chi: X.E3}

type Span is Data:
  Span{at: Nat, length: Nat}

def own(sh: G.Matrix,fn_: M.Functional) -> IO(Span):
  G.Matrix{_,_,+rows,columns} = sh
  M.Functional{_,+n,_,offset} = fn_
  do IO<Span>:
    ok : Unit <- Header.require(Nat.is_lt(0n,n) && Nat.is_eq(Nat.mod(rows,Nat.max(1n,n)),0n),"NO: segment-functional-rows")
    return Span{offset,Nat.mul(columns,Nat.div(rows,Nat.max(1n,n)))}

def spans(fns: M.Functionals,+mats: List<&2,G.Matrix>,out: List<&2,Span>) -> IO(List<&2,Span>):
  match fns:
    case []: IO.pure(List<&2,Span>,out)
    case +fn_ <> tail:
      do IO<List<&2,Span>>:
        sh : G.Matrix <- K.need(G.Matrix,List.get(&2,G.Matrix,mats,R.matrix(fn_)),"NO: segment-functional-matrix")
        s : Span <- own(sh,fn_)
        spans(tail,mats,s <> out)

type MapOf is Data:
  MapOf{sizes: Map<&2,Nat>, count: Nat}

def map_of(xs: List<&2,Span>,state: MapOf) -> MapOf:
  match xs state:
    case [] s: s
    case Span{at,len} <> rest MapOf{m,n}: map_of(rest,MapOf{Map.set(&2,Nat,m,Nat.show(at),len),1n+n})

def first(pair: Map<&2,Nat> & Nat) -> Nat:
  (_,v) = pair
  v

def tiled(fuel: Nat,+map_: Map<&2,Nat>,+pos: Nat,+length: Nat) -> Bool:
  match fuel:
    case 0n: Nat.is_eq(pos,length)
    case 1n+k:
      +n = first(Map.get(Nat,0n,map_,Nat.show(pos)))
      Nat.is_lt(0n,n) && Nat.is_le(Nat.add(pos,n),length) && tiled(k,map_,Nat.add(pos,n),length)

def tiling(segments: MapOf,length: Nat) -> Bool:
  MapOf{m,n} = segments
  tiled(n,m,0n,length)

def check(spans_: List<&2,Span>,length: Nat) -> Bool:
  tiling(map_of(spans_,MapOf{Map.new(&2,Nat),0n}),length)

def end(result: R.Sums,+ds: M.Equations,+ts: M.Equations,chi: X.E3,want: Nat,
  start: Nat,first: Nat,entries: Nat,suffix: Nat) -> IO(Contribution):
  R.Sums{rs,y,+n,k,_,_} = result
  +d = List.length(&2,M.Aff,ds)
  +t = List.length(&2,M.Aff,ts)
  +inclusive = Nat.add(d,Nat.add(t,n))
  +listed = Nat.add(start,Nat.add(inclusive,suffix))
  do IO<Contribution>:
    valid : Unit <- Header.require(Nat.is_eq(k,entries) && Nat.is_eq(want,Nat.add(listed,Nat.add(first,Nat.mul(128n,n)))),"NO: segment-smallness-equation-count")
    return Contribution{ds,ts,M.Aff{rs,[],y},inclusive,chi}

def read_count(s: R.Sums) -> Nat:
  R.Sums{_,_,n,_,_,_} = s
  n

def from_matrices(prepared: Mat.State,+world: Mat.World,fns: M.Functionals,+ds: M.Equations,coins: C.Coins,
  +linear: Nat,+start: Nat,+suffix: Nat,mz: Nat,length: Nat) -> IO(Contribution):
  Mat.State{+ms,_,rows,columns,+first} = prepared
  C.Coins{_,n,chi,want} = coins
  do IO<Contribution>:
    shape : Unit <- Header.require(Nat.is_eq(mz,rows) && Nat.is_eq(n,Nat.mul(128n,columns)),"NO: segment-smallness-rng-size")
    +ts : M.Equations <- Mat.ties(ms,world,0n,[])
    +got : R.Sums <- R.values(ms,fns,0n,world,R.Sums{[],F.zero(),0n,0n,Mat.lead(world,0n,first),[]})
    len : Unit <- Header.require(Nat.is_eq(linear,Nat.add(start,Nat.add(suffix,Nat.add(List.length(&2,M.Aff,ds),
      Nat.add(List.length(&2,M.Aff,ts),read_count(got)))))),"NO: segment-linear-count")
    end(got,ds,ts,chi,want,start,first,length,suffix)

def load(+coins: C.Coins,shape: G.Segment,+fns: M.Functionals,ds: M.Equations,link: Nat,
  +len: Nat,start: Nat,suffix: Nat) -> IO(Contribution):
  C.Coins{s,_,+chi,_} = coins
  G.Segment{+linear,+mz,_,+mats} = shape
  +ps = C.powers(128n,chi,F.one())
  +w = Mat.make_world(link,mz,O.row_bits(len),chi,linear,ps)
  do IO<Contribution>:
    good : Unit <- Header.require(Cover.order(Mat.step(w),Cover.packed_rows(mats,0n)),"NO: segment-smallness-row-powers")
    ss : List<&2,Span> <- spans(fns,mats,[])
    ok : Unit <- Header.require(check(ss,len),"NO: segment-functional-coverage")
    from_matrices(Mat.prepare(mats,ps,Mat.State{[],s,0n,0n,0n}),w,fns,ds,coins,linear,start,suffix,mz,len)

def size(shape: G.Segment) -> Nat:
  G.Segment{_,n,_,_} = shape
  n

def compute(input: M.Inputs,+geometry: G.Segment,fns: M.Functionals,u3: Nat,prefix_rows: Nat,suffix_rows: Nat) -> IO(Contribution):
  M.Inputs{+link,_,digit,events,_,_,shape} = input
  do IO<Contribution>:
    coins : C.Coins <- C.find(events,C.Found{None{},0n,None{},0n})
    ordinary : M.Equations <- D.build(digit,shape,link,size(geometry))
    load(coins,geometry,fns,ordinary,link,u3,prefix_rows,suffix_rows)
