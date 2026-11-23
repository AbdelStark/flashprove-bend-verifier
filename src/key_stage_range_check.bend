import Base
import ./opening_bytes.bend as OB
import ./key_stage_range_batch.bend as Bat
import ./key_stage_lookup_plan.bend as M
import ./key_stage_lookup_rows.bend as L
import ./key_stage_openings.bend as K
import ./key_stage_trace.bend as Trace
import ./key_stage_wf.bend as WF
import ./fold.bend as F
import ./fold_verify.bend as FV
import ./fold_open.bend as FO
import ./leaf_walk.bend as W
import ./plan.bend as P
import ./extension.bend as E
import ./transcript.bend as T
import ./oracle_sample.bend as Sample
import ./header.bend as Header

type Cut is Data:
  Cut{theta: E.E3, remaining: Trace.Events}

def at_bat(events: Trace.Events) -> IO(Cut):
  match events:
    case Trace.Observed{P.Round{"BAT",_,_,_,_,_,_,_,_,_,_,_},_,s,_,_} <> tail:
      IO.pure(Cut,Cut{T.value(E.E3,T.element(s)),tail})
    case _ <> tail: at_bat(tail)
    case _: IO.die(Cut,1,"NO: key-range-bat")

type Parsed is Data:
  Parsed{last: Bool, event: W.EntryRound}

def columns(opens: Trace.Openings) -> IO(OB.Columns):
  match opens:
    case []: IO.pure(OB.Columns,[])
    case [Trace.Opening{_,cols}]: IO.pure(OB.Columns,cols)
    case _: IO.die(OB.Columns,1,"NO: key-range-opening-order")

def parsed(e: Trace.Observed) -> IO(Parsed):
  Trace.Observed{P.Round{+name,_,_,_,_,_,_,_,_,_,_,_},raw,s,xs,opens} = e
  do IO<Parsed>:
    c : OB.Columns <- columns(opens)
    return Parsed{String.eq(name,"BASE"),W.EntryRound{name,raw,s,xs,c,[]}}

def push(p: Parsed, acc: FV.Events) -> Bool & FV.Events:
  Parsed{last,e} = p
  (last,e <> acc)

def group(events: Trace.Events, state: Bool & FV.Events) -> IO(FV.Events):
  match events state:
    case _ Tuple{True{},acc}: IO.pure(FV.Events,List.reverse(&2,W.EntryRound,acc))
    case Con{e,tail} Tuple{False{},acc}:
      do IO<FV.Events>:
        p : Parsed <- parsed(e)
        group(tail,push(p,acc))
    case _ _: IO.die(FV.Events,1,"NO: key-range-opening-order")

def run(cut: Cut, +meta: M.Metadata, rows: List<&2,L.Row>, slots: Nat, seed: Sample.Seed, answer: E.E3) -> IO(Unit):
  Cut{x,tail} = cut
  M.Metadata{_,_,_,main,mask,ss} = meta
  +n = U32.to_nat(main)
  +m = U32.to_nat(mask)
  do IO<Unit>:
    claim : F.Claim <- Bat.bat(meta,rows,seed,answer,x,slots)
    events : FV.Events <- group(tail,(False{},[]))
    Header.require(FV.custom(claim,ss,events,FO.ranges(n,m)),"NO: key-range-proximity")

def range(events: Trace.Events, meta: M.Metadata, rows: List<&2,L.Row>, slots: Nat) -> IO(Unit):
  match events:
    case _ <> _ <> Trace.Observed{P.Round{"SEND seed",_,_,_,_,_,n,1,_,_,_,_},_,s,_,_} <> Trace.Observed{P.Round{"SEND answer",_,_,_,_,_,_,_,_,_,_,_},msg,_,_,_} <> tail:
      do IO<Unit>:
        answer : E.E3 <- K.need(E.E3,FV.value(msg),"NO: key-range-answer")
        cut : Cut <- at_bat(tail)
        run(cut,meta,rows,slots,Sample.point(Nat.sub(U32.to_nat(n),1n),s,[]),answer)
    case _: IO.die(Unit,1,"NO: key-range-sample")

def verify(stage: WF.Stage, events: Trace.Events) -> IO(Unit):
  match stage:
    case WF.Skip{}: IO.pure(Unit,Unit{})
    case WF.Rows{meta,rows,_,slots,_}: range(events,meta,rows,slots)
    case _: IO.die(Unit,1,"NO: key-range-incomplete")
