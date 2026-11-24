import Base
import ./segment_workers.bend as Workers
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

# Input slices have already contributed to the sequential transcript.
# Keep the authenticated order and the slots and forest id of each action.
type Job is Data:
  Draw{events: Trace.Events}
  Check{events: Trace.Events, n: Nat, slot: Nat, slots: Nat, id: Nat, shape: S.Forest}

def jobs(actions: G.Actions,events: Trace.Events,id: Nat,acc: List<&2,Job>) -> List<&2,Job>:
  match actions:
    case []: List.reverse(&2,Job,acc)
    case G.TermsCoin{skip} <> tail:
      +at = List.drop(&2,Trace.Observed,events,skip)
      jobs(tail,List.drop(&2,Trace.Observed,at,1n),id,Draw{at} <> acc)
    case G.Forest{skip,+n,slot,slots,s} <> tail:
      +at = List.drop(&2,Trace.Observed,events,skip)
      +j = id
      jobs(tail,List.drop(&2,Trace.Observed,at,n),1n+j,Check{at,n,slot,slots,j,s} <> acc)

def finish(piece: Slice,+slot: Nat,slots: Nat,id: Nat,s: S.Forest,tables: T.Tables) -> IO(Forest.Claims):
  Slice{events,_} = piece
  Forest.compute(L.Tape{events,slot,0n,[]},s,id,tables,Nat.add(slot,slots))

def serial(xs: List<&2,Job>,+tables: T.Tables,acc: Groups) -> IO(Groups):
  match xs:
    case []: IO.pure(Groups,List.reverse(&2,Forest.Claims,acc))
    case Draw{ev} <> tail:
      do IO<Groups>:
        rest : Trace.Events <- coin(ev)
        serial(tail,tables,acc)
    case Check{ev,n,+slot,slots,id,s} <> tail:
      do IO<Groups>:
        got : Slice <- slice(n,ev,[])
        row : Forest.Claims <- finish(got,slot,slots,id,s,tables)
        serial(tail,tables,row <> acc)

def join(left: IO.OP<Groups>,right: IO.OP<Groups>) -> IO.OP<Groups>:
  match left right:
    case Emit{a} Emit{b}: Emit{F.cat(Forest.Claims,a,b)}
    case Halt{code,msg} _: Halt{code,msg}
    case Exit{code} _: Exit{code}
    case Emit{_} r: r

# At most eight subtrees are live; each batch owns its cursors and consumes
# its rounds sequentially. Only immutable public tables cross a fork.
def tree(depth: Nat,xs: List<&2,Job>,n: Nat,tables: T.Tables) -> IO.OP<Groups>:
  match depth n:
    case 1n+d 2n+m:
      +all: Nat = 2n+m
      +half = Nat.div(all,2n)
      +tasks = xs
      +t = tables
      +level = d
      left right = tree(level,List.take(&2,Job,tasks,half),half,t) tree(level,List.drop(&2,Job,tasks,half),Nat.sub(all,half),t)
      join(left,right)
    case _ _: Workers.observe(Groups,serial(xs,tables,[]))

def checks(actions: G.Actions,events: Trace.Events,id: Nat,tables: T.Tables,done: Groups) -> IO(Groups):
  +xs = jobs(actions,events,id,[])
  do IO<Groups>:
    result : Groups <- Workers.result(Groups,tree(3n,xs,F.count(Job,xs,0n),tables))
    return List.reverse.go(&2,Forest.Claims,done,result)
