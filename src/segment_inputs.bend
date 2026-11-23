import Base
import ./segment_model.bend as M
import ./segment_stage.bend as Stage
import ./segment_forest.bend as Forest
import ./segment_geometry.bend as G
import ./segment_tables.bend as S
import ./key_stage_trace.bend as Trace
import ./plan.bend as P
import ./policy_statement.bend as Statement

def Batches() -> Data: List<&2,M.Inputs>
def Shapes() -> Data: List<&2,S.Forest>

def shapes(actions: G.Actions) -> Shapes:
  match actions:
    case []: []
    case G.Forest{_,_,_,_,s} <> rest: s <> shapes(rest)
    case G.TermsCoin{_} <> rest: shapes(rest)

def match_name(name: String) -> U32:
  match name:
    case "LKP shift": 1
    case "BAT": 2
    case _: 0

def code(e: Trace.Observed) -> U32:
  Trace.Observed{P.Round{name,_,_,_,_,_,_,_,_,_,_,_},_,_,_,_} = e
  match_name(name)

type Slice is Data:
  Slice{local: Trace.Events, later: Trace.Events}

def collect(events: Trace.Events, +started: Bool, +rev: Trace.Events) -> IO(Slice):
  match events:
    case []: IO.die(Slice,1,"NO: missing-segment-BAT")
    case +round <> +tail:
      +k = code(round)
      +on = started || U32.is_eq(k,1)
      run = Bool.pick(Unit -> IO(Slice),on && U32.is_eq(k,2),
        _ => IO.pure(Slice,Slice{List.reverse(&2,Trace.Observed,rev),tail}),
        _ => collect(tail,on,Bool.pick(Trace.Events,on,round <> rev,rev)))
      run(Unit{})

type Next is Data:
  Next{input: M.Inputs, later: Trace.Events}

def input(slice: Slice, link: Nat, a: Forest.Claims, b: Forest.Claims, st: Statement.Statement, main: S.Forest, digits: S.Forest) -> Next:
  Slice{events,rest} = slice
  Next{M.Inputs{link,a,b,events,st,main,digits},rest}

def one(data: Next) -> M.Inputs:
  Next{i,_} = data
  i

def remaining(data: Next) -> Trace.Events:
  Next{_,r} = data
  r

def batches(shapes: Shapes, forests: Stage.Groups, link: Nat, +st: Statement.Statement, events: Trace.Events, acc: Batches) -> IO(Batches):
  match shapes forests:
    case Nil{} Nil{}: IO.pure(Batches,List.reverse(&2,M.Inputs,acc))
    case Con{s,Con{t,ss}} Con{a,Con{b,tail}}:
      +j = link
      do IO<Batches>:
        got : Slice <- collect(events,False{},[])
        +next : Next = input(got,j,a,b,st,s,t)
        batches(ss,tail,1n+j,st,remaining(next),one(next) <> acc)
    case _ _: IO.die(Batches,1,"NO: segment-forest-pairs")
