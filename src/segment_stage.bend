import Base
import ./key_stage_trace.bend as Trace
import ./key_stage_lookup_rows.bend as L
import ./key_stage_openings.bend as K
import ./plan.bend as P
import ./extension.bend as X
import ./base_check.bend as B
import ./fold.bend as F
import ./segment_geometry.bend as G
import ./segment_tables.bend as S
import ./segment_forest.bend as Forest
import ./policy_tables.bend as T
import ./transcript.bend as TR
import ./header.bend as Header

def Groups() -> Data: List<&2,Forest.Claims>

type Slice is Data:
  Slice{taken: L.Events, tail: Trace.Events}

def slice(n: Nat, events: Trace.Events, acc: L.Events) -> IO(Slice):
  match n events:
    case 0n rest: IO.pure(Slice,Slice{List.reverse(&2,L.AlgebraRound,acc),rest})
    case 1n+m Trace.Observed{P.Round{name,_,_,_,_,_,e,nz,_,_,_,_},msg,stream,_,_} <> tail:
      slice(m,tail,L.event(name,msg,stream,e,nz) <> acc)
    case _ _: IO.die(Slice,1,"NO: short-segment-forest")

def coin(events: Trace.Events) -> IO(Trace.Events):
  match events:
    case Trace.Observed{P.Round{"PSC epsilon",_,_,_,_,_,1,0,_,_,_,_},_,stream,_,_} <> tail:
      do IO<Trace.Events>:
        ok : Unit <- Header.require(Bool.not(B.equal(TR.value(X.E3,TR.element(stream)),F.zero())),"NO: coin-zero")
        return tail
    case _: IO.die(Trace.Events,1,"NO: segment-terms-round")

type Computed is Data:
  Computed{claims: Forest.Claims, tail: Trace.Events}

def remaining(c: Computed) -> Trace.Events:
  Computed{_,xs} = c
  xs

def claims(c: Computed) -> Forest.Claims:
  Computed{cs,_} = c
  cs

def form(piece: Slice, shape: S.Forest, slot: Nat, slots: Nat, id: Nat, tables: T.Tables) -> IO(Computed):
  Slice{xs,rest} = piece
  +s = slot
  do IO<Computed>:
    cs : Forest.Claims <- Forest.compute(L.Tape{xs,s,0n,[]},shape,id,tables,Nat.add(s,slots))
    return Computed{cs,rest}

def checks(actions: G.Actions, events: Trace.Events, id: Nat, +tables: T.Tables, done: Groups) -> IO(Groups):
  match actions:
    case []: IO.pure(Groups,List.reverse(&2,Forest.Claims,done))
    case G.TermsCoin{skip} <> tail:
      do IO<Groups>:
        rest : Trace.Events <- coin(List.drop(&2,Trace.Observed,events,skip))
        checks(tail,rest,id,tables,done)
    case G.Forest{skip,n,slot,slots,s} <> tail:
      +j = id
      do IO<Groups>:
        got : Slice <- slice(n,List.drop(&2,Trace.Observed,events,skip),[])
        +out : Computed <- form(got,s,slot,slots,j,tables)
        checks(tail,remaining(out),1n+j,tables,claims(out) <> done)
