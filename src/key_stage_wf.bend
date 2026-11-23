import Base
import ./key_stage_lookup.bend as Arg
import ./key_stage_lookup_plan.bend as M
import ./key_stage_lookup_rows.bend as L
import ./hash_bytes.bend as H
import ./transcript.bend as T
import ./plan.bend as P
import ./header.bend as Header

type Stage is Data:
  Skip{}
  Collect{plan: M.Metadata, reverse: L.Events}
  Rows{plan: M.Metadata, rows: List<&2,L.Row>, pending: List<&2,Arg.Pending>, mask_slots: Nat, index_slots: Nat}

def select(fits: Bool, items: List<&2,P.Item>) -> IO(Stage):
  match fits:
    case True{}:
      do IO<Stage>:
        ms : M.Metadata <- M.load(items)
        return Collect{ms,[]}
    case _: IO.pure(Stage,Skip{})

def start(label: Nat, items: List<&2,P.Item>) -> IO(Stage):
  select(Nat.is_eq(label,1179798786n),items)

def completed(out: Arg.Output, meta: M.Metadata, expected: U32) -> IO(Stage):
  Arg.Output{pending,L.Tape{unused,ms,ix,+rows}} = out
  do IO<Stage>:
    ok : Unit <- Header.require(List.is_empty(&2,L.AlgebraRound,unused) &&
      Nat.is_eq(1n+List.length(&2,L.Row,rows),U32.to_nat(expected)),"NO: key-range-batch-rows")
    return Rows{meta,List.reverse(&2,L.Row,rows),List.reverse(&2,Arg.Pending,pending),ms,ix}

def batch(+meta: M.Metadata, previous: L.Events, count: U32) -> IO(Stage):
  M.Metadata{lookups,cols,_,_,_} = meta
  do IO<Stage>:
    out : Arg.Output <- Arg.run(lookups,cols,0n,Arg.Output{[],L.Tape{List.reverse(&2,L.AlgebraRound,previous),0n,0n,[]}})
    completed(out,meta,count)

def record(stage: Stage, round: P.Round, message: H.Bytes, stream: T.Stream) -> IO(Stage):
  match stage round:
    case Collect{+meta,acc} P.Round{"BAT",_,_,_,_,_,_,_,_,_,_,count}: batch(meta,acc,count)
    case Collect{meta,acc} P.Round{"SEND seed",_,_,_,_,_,_,_,_,_,_,_}: IO.pure(Stage,Collect{meta,acc})
    case Collect{meta,acc} P.Round{"SEND answer",_,_,_,_,_,_,_,_,_,_,_}: IO.pure(Stage,Collect{meta,acc})
    case Collect{meta,acc} P.Round{name,_,_,_,_,_,n,nz,_,_,_,_}:
      IO.pure(Stage,Collect{meta,L.event(name,message,stream,n,nz) <> acc})
    case other _: IO.pure(Stage,other)

def finished(stage: Stage) -> Bool:
  match stage:
    case Collect{_,_}: False{}
    case _: True{}
