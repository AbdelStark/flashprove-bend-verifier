import Base
import ../../src/request_stage.bend as Req
import ../../src/segment_local.bend as L
import ../../src/segment_chain.bend as Chain
import ../../src/segment_inputs.bend as Inputs
import ../../src/segment_model.bend as M
import ../../src/fold_request_shape.bend as Q
import ../../src/fold_request.bend as Fold
import ../../src/fold_frame.bend as Fm
import ../../src/fold.bend as F
import ../../src/base_check.bend as B
import ../../src/extension.bend as X
import ../../src/sumcheck.bend as E
import ../../src/lin_own.bend as Own
import ../../src/plan_types.bend as PT
import ../../src/plan.bend as P
import ../../src/key_stage_trace.bend as Tr
import ../../src/leaf_shape.bend as S
import ../../src/wire_reader.bend as R
import ../../src/policy_statement.bend as Statement
import ../../src/policy_config.bend as C
import ../../src/header.bend as H
import ../../src/hash_bytes.bend as Hash
import ../../src/key_stage.bend as Key
import ../../src/leaf_stage.bend as Leaf

# Inject into the derived obligation of the first G only. The key, leaf,
# request files, Fiat–Shamir messages, nonce checks and openings remain real.
type Mode is Data:
  Honest{}
  Bat{}
  Folded{}
  Merged{}
  Weight{}

def changed_bound(m: Own.Pending) -> Own.Pending:
  Own.Pending{terms,point,ms,y} = m
  Own.Pending{terms,point,ms,E.add(y,F.one())}

def changed_weight(m: Own.Pending) -> Own.Pending:
  match m:
    case Own.Pending{F.Term{w,fs} <> rest,p,ms,y}:
      Own.Pending{F.Term{E.add(w,F.one()),fs} <> rest,p,ms,y}
    case x: x

def change(mode: Mode,local: L.Local) -> L.Local:
  match mode local:
    case Bat{} L.Local{Fm.Equation{terms,y},p}: L.Local{Fm.Equation{terms,E.add(y,F.one())},p}
    case Merged{} L.Local{eq,Some{p}}: L.Local{eq,Some{changed_bound(p)}}
    case Weight{} L.Local{eq,Some{p}}: L.Local{eq,Some{changed_weight(p)}}
    case _ r: r

def folded(mode: Mode,state: Chain.State) -> Chain.State:
  match mode state:
    case Folded{} Chain.State{Fold.Cursor{events,Fold.Past{ms,stage,Fm.Closed{F.Single{terms,d,f,y},ks},g,k},alive},ps}:
      after: Fm.Closed = Fm.Closed{F.Single{terms,d,f,E.add(y,F.one())},ks}
      Chain.State{Fold.Cursor{events,Fold.Past{ms,stage,after,g,k},alive},ps}
    case _ s: s

def finish(own: Own.First,pair: R.Reader & Req.FirstData) -> IO(Unit):
  (r,Req.FirstData{end,_,ctx,_,_}) = pair
  do IO<Unit>:
    t : Req.Trace <- Req.binding_checked((r,end),ctx,own)
    IO.print("checked")

def start(ctx: L.Context,ms: Inputs.Batches,events: Tr.Events,items: List<&2,P.Item>,+mode: Mode) -> IO(Own.First):
  match ctx ms:
    case L.Context{book,Q.Shape{+c,+m,Con{+link,+links},+later},geo,p} Con{+g,rest}:
      +context: L.Context = L.Context{book,Q.Shape{c,m,link <> links,later},geo,p}
      +ev = events
      do IO<Own.First>:
        row : L.Logical <- L.at_feed(g,context)
        raw : L.Local <- L.physical(0n,context,row)
        one : Chain.State <- Chain.step(link,change(mode,raw),c,m,Chain.State{Fold.Cursor{ev,Fold.Start{},[]},[]},True{})
        st : Chain.State <- Chain.walk(rest,links,context,c,m,folded(mode,one),1n)
        Chain.finish(st,c,m,later,ev,items)
    case _ _: IO.die(Own.First,1,"fixture needs a first G segment")

def stage(pair: R.Reader & Req.FirstData,+items: List<&2,P.Item>,mode: Mode) -> IO(Unit):
  (reader,+data) = pair
  Req.FirstData{_,ev,Req.Context{_,profile,_,_,_,_,_},_,_} = data
  do IO<Unit>:
    ctx : L.Context <- L.context(items,profile)
    inputs : Inputs.Batches <- Req.family_inputs(data)
    own : Own.First <- start(ctx,inputs,ev,items,mode)
    finish(own,(reader,data))

def verify(mode: Mode,leaf: Leaf.Trace,+cfg: C.Configured,st: Statement.Statement,path: String,copy: U32,plans: String) -> IO(Unit):
  Leaf.Trace{_,_,table,_,session,_} = leaf
  C.Configured{_,P.Plan{_,_,_,items}} = cfg
  do IO<Unit>:
    r : R.Reader & Req.FirstData <- Req.first_data(path,copy,st,cfg,plans,table,session)
    stage(r,items,mode)

def key(mode: Mode,attested: Key.AttestedKey,+cfg: C.Configured,st: Statement.Statement,+folder: String,+plans: String) -> IO(Unit):
  Key.AttestedKey{anchor,ans,_,_,_,session} = attested
  C.Configured{digest,_} = cfg
  +path = folder ++ "/example.proof"
  do IO<Unit>:
    bytes : Hash.Bytes <- H.bytes(path,12)
    +copy : U32 <- H.leaf_index(bytes)
    leaf : Leaf.Trace <- Leaf.inspect(folder ++ "/ivk/leaf/" ++ U32.show(copy) ++ ".bin",digest,plans,Leaf.Table{anchor,ans},session)
    verify(mode,leaf,cfg,st,path,copy,plans)

def parsed(name: String) -> IO(Mode):
  match name:
    case "honest": IO.pure(Mode,Honest{})
    case "bat": IO.pure(Mode,Bat{})
    case "fold": IO.pure(Mode,Folded{})
    case "merge": IO.pure(Mode,Merged{})
    case "weight": IO.pure(Mode,Weight{})
    case _: IO.die(Mode,2,"unknown mutation")

def digest(c: C.Configured) -> Hash.Bytes:
  C.Configured{d,_} = c
  d

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,mode,+folder,tables,+plans]:
      +config = folder ++ "/config"
      do IO<Unit>:
        how : Mode <- parsed(mode)
        +st : Statement.Statement <- Statement.load(config,folder ++ "/example.req",folder ++ "/example.y",tables,None{})
        +cfg : C.Configured <- C.load(st,config,plans)
        a : Key.AttestedKey <- Key.check_transcript(folder ++ "/ivk/key.bin",digest(cfg),plans)
        key(how,a,cfg,st,folder,plans)
    case _: IO.die(Unit,2,"usage: request_claims MODE EXAMPLE TABLES PLANS")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
