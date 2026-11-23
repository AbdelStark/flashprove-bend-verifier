import Base
import ./key_stage_geometry.bend as G
import ./key_stage_trace.bend as Trace
import ./key_stage_wf.bend as WF
import ./key_stage_base.bend as B
import ./key_stage_codes.bend as Code
import ./key_stage_openings.bend as K
import ./opening_bytes.bend as O
import ./round_io.bend as RoundIO
import ./wire_reader.bend as R
import ./hash_bytes.bend as H
import ./transcript.bend as T
import ./plan.bend as P
import ./merkle.bend as M
import ./header.bend as Header

type World is Data:
  World{config: M.Digest, table: M.Digest, run: M.Digest}

type Cursor is Data:
  Cursor{state: T.State, book: K.Book, session: O.Session, groups: G.Schedule, seal: H.Bytes, base: B.State, wf: WF.Stage, events: Trace.Events}

def sampled(name: String, stream: T.Stream, previous: H.Bytes) -> H.Bytes:
  match name:
    case "SEAL": T.seal(stream)
    case _: previous

def with_openings(pair: R.Reader & K.Group, state: T.State, book: K.Book,
  groups: G.Schedule, seal: H.Bytes, base: B.State, wf: WF.Stage, events: Trace.Events,
  round: P.Round, raw: H.Bytes, stream: T.Stream, positions: O.Places) -> R.Reader & Cursor:
  (r,g) = pair
  K.Group{session,opened} = g
  event: Trace.Observed = Trace.Observed{round,raw,stream,positions,opened}
  (r,Cursor{state,book,session,groups,seal,base,wf,event <> events})

def positions(n: U32, depth: U32, +stream: T.Stream, world: World, state: T.State,
  +book: K.Book, session: O.Session, groups: G.Schedule, seal: H.Bytes, r: R.Reader, step: B.Step, wf: WF.Stage,
  events: Trace.Events, round: P.Round, raw: H.Bytes) -> IO(R.Reader & Cursor):
  match n world groups step:
    case 0 _ rest B.Step{base,_}:
      event: Trace.Observed = Trace.Observed{round,raw,stream,[],[]}
      IO.pure(R.Reader & Cursor,(r,Cursor{state,book,session,rest,seal,base,wf,event <> events}))
    case _ _ Nil{} _: IO.die(R.Reader & Cursor,1,"NO: key-opening-schedule")
    case pos World{cfg,table,_} Con{trees,tail} B.Step{base,mode}:
      +xs = T.value(O.Places,T.draws(U32.to_nat(pos),U32.to_nat(depth),stream))
      do IO<R.Reader & Cursor>:
        opened : R.Reader & K.Group <- K.open_group(trees,cfg,table,book,xs,mode,(r,K.Group{session,[]}))
        return with_openings(opened,state,book,tail,seal,base,wf,events,round,raw,stream,xs)

def after(pair: R.Reader & RoundIO.Step, +round: P.Round, +world: World,
  +book: K.Book, session: O.Session, groups: G.Schedule, previous: H.Bytes, base: B.State, wf: WF.Stage, events: Trace.Events) -> IO(R.Reader & Cursor):
  (r,step) = pair
  RoundIO.Step{+raw,state,+stream} = step
  P.Round{+name,_,_,_,roots,_,_,_,pos,depth,_,_} = round
  World{_,_,run} = world
  do IO<R.Reader & Cursor>:
    known : K.Book <- K.add(U32.to_nat(roots),raw,run,book,List.length(&2,K.Root,book))
    prepared : B.Step <- B.prepare(name,raw,stream,base)
    ranges : WF.Stage <- WF.record(wf,round,raw,stream)
    positions(pos,depth,stream,world,state,known,session,groups,sampled(name,stream,previous),r,prepared,ranges,events,round,raw)

def advance(name: String, +round: P.Round, +world: World, pair: R.Reader & Cursor) -> IO(R.Reader & Cursor):
  match name pair:
    case "RECORD" x: IO.pure(R.Reader & Cursor,x)
    case _ Tuple{r,Cursor{state,book,session,groups,previous,base,wf,events}}:
      do IO<R.Reader & Cursor>:
        step : R.Reader & RoundIO.Step <- RoundIO.advance(r,state,round)
        after(step,round,world,book,session,groups,previous,base,wf,events)

def walk(rounds: List<&2,P.Round>, +world: World, pair: R.Reader & Cursor) -> IO(R.Reader & Cursor):
  match rounds:
    case []: IO.pure(R.Reader & Cursor,pair)
    case +round <> tail:
      P.Round{name,_,_,_,_,_,_,_,_,_,_,_} = round
      do IO<R.Reader & Cursor>:
        next : R.Reader & Cursor <- advance(name,round,world,pair)
        walk(tail,world,next)

type End is Data:
  End{book: K.Book, session: O.Session, seal: H.Bytes, rho: H.Bytes}

type Traced is Data:
  Traced{result: End, events: Trace.Events, ranges: WF.Stage}

def initial_cursor(state: T.State, book: K.Book, session: O.Session, groups: G.Schedule, finals: List<&2,Code.Final>) -> Cursor:
  Cursor{state,book,session,groups,[],B.State{finals,None{}},WF.Skip{},[]}

def finish_traced(pair: R.Reader & Cursor) -> IO(R.Reader & Traced):
  (r,cur) = pair
  Cursor{T.State{_,_,rho},book,session,groups,seal,base,+wf,events} = cur
  do IO<R.Reader & Traced>:
    ok : Unit <- Header.require(List.is_empty(&2,List<&2,G.Tree>,groups),"NO: unfinished-key-openings")
    done : Unit <- Header.require(B.complete(base) && WF.finished(wf),"NO: unfinished-key-base")
    return (r,Traced{End{book,session,seal,rho},List.reverse(&2,Trace.Observed,events),wf})

def start(first: T.Start, r: R.Reader, config: M.Digest, table: M.Digest, rounds: List<&2,P.Round>,
  book: K.Book, session: O.Session, groups: G.Schedule, finals: List<&2,Code.Final>, wf: WF.Stage) -> IO(R.Reader & Traced):
  T.Start{state,run} = first
  do IO<R.Reader & Traced>:
    raw : H.Bytes <- K.need(H.Bytes,run,"NO: key-chain-randomness")
    run_id : M.Digest <- K.digest(raw)
    walked : R.Reader & Cursor <- walk(rounds,World{config,table,run_id},(r,Cursor{state,book,session,groups,[],B.State{finals,None{}},wf,[]}))
    finish_traced(walked)

def begin_traced(pair: R.Reader & H.Bytes, +label: Nat, plan: P.Plan, statement: H.Bytes, config: M.Digest,
  table: M.Digest, book: K.Book, session: O.Session, groups: G.Schedule, finals: List<&2,Code.Final>) -> IO(R.Reader & Traced):
  (r,random) = pair
  P.Plan{digest,_,rounds,items} = plan
  do IO<R.Reader & Traced>:
    first : T.Start <- K.need(T.Start,T.begin(label,digest,statement,Some{random}),"NO: key-chain-start")
    wf : WF.Stage <- WF.start(label,items)
    start(first,r,config,table,rounds,book,session,groups,finals,wf)


def end_only(pair: R.Reader & Traced) -> R.Reader & End:
  (r,t) = pair
  Traced{e,_,_} = t
  (r,e)

def finish(pair: R.Reader & Cursor) -> IO(R.Reader & End):
  do IO<R.Reader & End>:
    out : R.Reader & Traced <- finish_traced(pair)
    return end_only(out)

def begin(pair: R.Reader & H.Bytes, label: Nat, plan: P.Plan, statement: H.Bytes, config: M.Digest,
  table: M.Digest, book: K.Book, session: O.Session, groups: G.Schedule, finals: List<&2,Code.Final>) -> IO(R.Reader & End):
  do IO<R.Reader & End>:
    out : R.Reader & Traced <- begin_traced(pair,label,plan,statement,config,table,book,session,groups,finals)
    return end_only(out)
