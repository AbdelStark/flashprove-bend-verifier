import Base
import ./key_stage_trace.bend as Tr
import ./leaf_walk.bend as W
import ./plan.bend as P
import ./transcript.bend as T
import ./hash_bytes.bend as H
import ./key_stage_openings.bend as K
import ./header.bend as Header
import ./opening_bytes.bend as O
import ./fold_verify.bend as FV
import ./fold_open.bend as Open
import ./fold.bend as F
import ./fold_cs.bend as CS
import ./leaf_shape.bend as S
import ./base_check.bend as B
import ./extension.bend as Ext

def name(e: Tr.Observed) -> String:
  Tr.Observed{P.Round{s,_,_,_,_,_,_,_,_,_,_,_},_,_,_,_} = e
  s

def draws(e: Tr.Observed) -> O.Places:
  Tr.Observed{_,_,_,xs,_} = e
  xs

def stream(e: Tr.Observed) -> T.Stream:
  Tr.Observed{_,_,s,_,_} = e
  s

def message(e: Tr.Observed) -> H.Bytes:
  Tr.Observed{_,m,_,_,_} = e
  m

def trees(opens: Tr.Openings) -> List<&2,O.Columns>:
  match opens:
    case []: []
    case Tr.Opening{_,cols} <> rest: cols <> trees(rest)

def columns(e: Tr.Observed) -> List<&2,O.Columns>:
  Tr.Observed{_,_,_,_,o} = e
  trees(o)

def head(xs: List<&2,O.Columns>) -> O.Columns:
  Maybe.default(&2,O.Columns,List.head(&2,O.Columns,xs),[])

def round(+e: Tr.Observed) -> W.EntryRound:
  Tr.Observed{P.Round{+n,_,_,_,roots,_,_,_,_,_,_,_},+m,s,xs,opens} = e
  # Omega sends its fresh mask root with FOLD epsilon. The walk has already
  # absorbed and registered each root. The fold consumes the hiding sum.
  body = Bool.pick(H.Bytes,String.eq(n,"FOLD epsilon"),List.drop(&2,U32,m,Nat.mul(32n,U32.to_nat(roots))),m)
  W.EntryRound{n,body,s,xs,head(trees(opens)),[]}

type Group is Data:
  Group{theta: Ext.E3, rounds: FV.Events, columns: List<&2,O.Columns>, rest: Tr.Events}

def observe(previous: Maybe<&2,List<&2,O.Columns>>, name: String, all: List<&2,O.Columns>) -> Maybe<&2,List<&2,O.Columns>>:
  match previous:
    case Some{p}: Some{p}
    case None{}: Bool.pick(Maybe<&2,List<&2,O.Columns>>,String.eq(name,"CS"),Some{all},None{})

def done(tail: Tr.Events, theta: Ext.E3, trace: FV.Events, first: Maybe<&2,List<&2,O.Columns>>) -> IO(Group):
  do IO<Group>:
    cols : List<&2,O.Columns> <- K.need(List<&2,O.Columns>,first,"NO: lin-cs-missing")
    return Group{theta,List.reverse(&2,W.EntryRound,trace),cols,tail}

def scan(events: Tr.Events, +theta: Ext.E3, acc: FV.Events, first: Maybe<&2,List<&2,O.Columns>>) -> IO(Group):
  match events:
    case []: IO.die(Group,1,"NO: lin-base-missing")
    case +e <> +tail:
      +n = name(e)
      +trace : FV.Events = round(e) <> acc
      +opens = columns(e)
      +next = observe(first,n,opens)
      Bool.pick(IO(Group),String.eq(n,"BASE"),done(tail,theta,trace,next),scan(tail,theta,trace,next))

def group(events: Tr.Events) -> IO(Group):
  match events:
    case +e <> tail:
      do IO<Group>:
        ok : Unit <- Header.require(String.eq(name(e),"BAT"),"NO: lin-bat-missing")
        scan(tail,FV.first(stream(e)),[],None{})
    case _: IO.die(Group,1,"NO: lin-bat-missing")

def callback(group: Open.KeyGroup, cols: List<&2,O.Columns>, stage: S.Stage, gs: B.Elements, xs: O.Places, left: O.Columns, right: O.Columns) -> Maybe<&2,CS.Draws>:
  Open.key(group,stage,gs,xs,cols)

def reason(layout: Open.KeyGroup) -> String:
  match layout:
    case Open.Folded{_}: "NO: lin-folded-proximity"
    case Open.Omega{_}: "NO: lin-omega-proximity"
    case _: "NO: lin-own-proximity"

def verify(group: Group, +layout: Open.KeyGroup, stages: List<&2,S.Stage>, claim: F.Claim) -> IO(Tr.Events):
  Group{_,rounds,cols,rest} = group
  do IO<Tr.Events>:
    ok : Unit <- Header.require(FV.custom(claim,stages,rounds,callback(layout,cols)),reason(layout))
    return rest

def theta(group: Group) -> Ext.E3:
  Group{t,_,_,_} = group
  t
