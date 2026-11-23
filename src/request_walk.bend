import Base
import ./hash_bytes.bend as H
import ./wire_reader.bend as R
import ./header.bend as Header
import ./plan.bend as P
import ./key_stage_wf.bend as WF
import ./key_stage_trace.bend as Trace
import ./round_io.bend as Round
import ./transcript.bend as T
import ./merkle.bend as M
import ./key_stage_walk.bend as W
import ./key_stage_openings.bend as K
import ./key_stage_base.bend as B
import ./key_stage_codes.bend as Codes
import ./key_stage_geometry.bend as Geometry
import ./opening_bytes.bend as O

def Rounds() -> Data:
  List<&2,P.Round>

type Split is Data:
  Split{before: Rounds, at: P.Round, after: Rounds}

def split(xs: Rounds, +target: String, +before: Rounds) -> IO(Split):
  match xs:
    case []: IO.die(Split,1,"NO: request-round-plan")
    case +round <> +tail:
      P.Round{name,_,_,_,_,_,_,_,_,_,_,_} = round
      action = Bool.pick(Unit -> IO(Split),String.eq(name,target),
        _ => IO.pure(Split,Split{List.reverse(&2,P.Round,before),round,tail}),
        _ => split(tail,target,round <> before))
      action(Unit{})

def token(raw: H.Bytes, +vocab: U32) -> IO(U32):
  match raw:
    case [+y,0,0,0,0,0]:
      do IO<U32>:
        ok : Unit <- Header.require(U32.is_lt(y,vocab),"NO: header-y")
        return y
    case _: IO.die(U32,1,"NO: header-y")

def after_reply(pair: R.Reader & Round.Step, world: W.World, round: P.Round,
    book: K.Book, session: O.Session, groups: Geometry.Schedule, seal: H.Bytes,
    base: B.State, wf: WF.Stage, events: Trace.Events, vocab: U32) -> IO((R.Reader & W.Cursor) & U32):
  (r,+step) = pair
  Round.Step{msg,_,_} = step
  do IO<(R.Reader & W.Cursor) & U32>:
    y : U32 <- token(H.u32s(msg),vocab)
    next : R.Reader & W.Cursor <- W.after((r,step),round,world,book,session,groups,seal,base,wf,events)
    return (next,y)

def reply(pair: R.Reader & W.Cursor, +round: P.Round, world: W.World, vocab: U32) -> IO((R.Reader & W.Cursor) & U32):
  (r,W.Cursor{state,book,session,groups,seal,base,wf,events}) = pair
  do IO<(R.Reader & W.Cursor) & U32>:
    step : R.Reader & Round.Step <- Round.advance(r,state,round)
    after_reply(step,world,round,book,session,groups,seal,base,wf,events,vocab)

def head(pair: (R.Reader & W.Cursor) & U32, +world: W.World, finish: Split, expected: U32) -> IO(R.Reader & W.Traced):
  (state,token) = pair
  Split{before,base,tail} = finish
  do IO<R.Reader & W.Traced>:
    checked : R.Reader & W.Cursor <- W.walk(List.append(&2,P.Round,before,[base]),world,state)
    ok : Unit <- Header.require(U32.is_eq(token,expected),"NO: reply-differs")
    last : R.Reader & W.Cursor <- W.walk(tail,world,checked)
    W.finish_traced(last)

def first_rounds(split_at: Split, +world: W.World, state: R.Reader & W.Cursor, y: U32, vocab: U32) -> IO(R.Reader & W.Traced):
  Split{before,mid,tail} = split_at
  do IO<R.Reader & W.Traced>:
    start : R.Reader & W.Cursor <- W.walk(before,world,state)
    with_token : (R.Reader & W.Cursor) & U32 <- reply(start,mid,world,vocab)
    finish : Split <- split(tail,"BASE",[])
    head(with_token,world,finish,y)

def opened(begin: T.Start, r: R.Reader, config: M.Digest, table: M.Digest, rounds: Rounds,
    session: O.Session, groups: Geometry.Schedule, last: Codes.Final, y: U32, vocab: U32) -> IO(R.Reader & W.Traced):
  T.Start{state,run} = begin
  do IO<R.Reader & W.Traced>:
    raw : H.Bytes <- K.need(H.Bytes,run,"NO: request-chain-randomness")
    id : M.Digest <- K.digest(raw)
    xs : Split <- split(rounds,"REPLY",[])
    first_rounds(xs,W.World{config,table,id},(r,W.initial_cursor(state,[],session,groups,[last])),y,vocab)

def first(pair: R.Reader & H.Bytes, plan: P.Plan, statement: H.Bytes, config: M.Digest, table: M.Digest,
    session: O.Session, groups: Geometry.Schedule, last: Codes.Final, y: U32, vocab: U32) -> IO(R.Reader & W.Traced):
  (r,bytes) = pair
  P.Plan{digest,_,rounds,_} = plan
  do IO<R.Reader & W.Traced>:
    init : T.Start <- K.need(T.Start,T.begin(1179798785n,digest,statement,Some{bytes}),"NO: request-first")
    opened(init,r,config,table,rounds,session,groups,last,y,vocab)
