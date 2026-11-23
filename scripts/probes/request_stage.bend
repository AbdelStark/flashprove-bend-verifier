import Base
import ./segment_projection.bend as Projection
import ./attention_projection.bend as Attention
import ./model_batch_projection.bend as Batch
import ./ff_lookup_projection.bend as GJoin
import ./ff_projection.bend as FeedForward
import ./head_projection.bend as Head
import ../../src/segment_local.bend as Local
import ../../src/plan_types.bend as PT
import ../../src/plan.bend as Plan
import ../../src/segment_inputs.bend as Inputs
import ../../src/wire_reader.bend as R
import ../../src/request_stage.bend as Q
import ../../src/policy_statement.bend as S
import ../../src/policy_config.bend as C
import ../../src/header.bend as Header
import ../../src/key_stage.bend as Key
import ../../src/leaf_stage.bend as Leaf
import ../../src/hash_bytes.bend as H
import ../../src/opening_bytes.bend as O

def print_trace(trace: Q.Trace) -> IO(Unit):
  Q.Trace{slot,root,first,shared,rho,_,forests} = trace
  do IO<Unit>:
    ok : Unit <- Projection.groups(forests)
    IO.print(Nat.show(slot) ++ " " ++ H.hex(O.digest_bytes(root)) ++ " " ++ H.hex(first) ++ " " ++ H.hex(shared) ++ " " ++ H.hex(rho))

def profile(s: Q.FirstData) -> PT.Profile:
  Q.FirstData{_,_,Q.Context{_,p,_,_,_,_,_},_,_} = s
  p

def models(r: R.Reader & Q.FirstData,cfg: C.Configured) -> IO(Q.Trace):
  (reader,+first) = r
  C.Configured{_,Plan.Plan{_,_,_,items}} = cfg
  do IO<Q.Trace>:
    checked : Q.Trace <- Q.continue_first((reader,first))
    +batches : Inputs.Batches <- Q.family_inputs(first)
    ctx : Local.Context <- Local.context(items,profile(first))
    ok : Unit <- Attention.groups(batches)
    done : Unit <- Batch.groups(batches,ctx)
    joined : Unit <- GJoin.groups(batches,profile(first))
    feed_forward : Unit <- FeedForward.groups(batches,profile(first))
    head : Unit <- Head.groups(batches,profile(first))
    return checked

def proof(trace: Leaf.Trace, +cfg: C.Configured, stmt: S.Statement, path: String, copy: U32, plans: String) -> IO(Unit):
  Leaf.Trace{_,_,checked,_,session,_} = trace
  do IO<Unit>:
    saved : R.Reader & Q.FirstData <- Q.first_data(path,copy,stmt,cfg,plans,checked,session)
    checked : Q.Trace <- models(saved,cfg)
    print_trace(checked)

def entry(key: Key.AttestedKey, +cfg: C.Configured, stmt: S.Statement, +ivk: String, +path: String, +plans: String) -> IO(Unit):
  Key.AttestedKey{root,answers,_,_,_,session} = key
  C.Configured{digest,_} = cfg
  do IO<Unit>:
    h : H.Bytes <- Header.bytes(path,12)
    +copy : U32 <- Header.leaf_index(h)
    data : Leaf.Trace <- Leaf.inspect(ivk ++ "/leaf/" ++ U32.show(copy) ++ ".bin",digest,plans,Leaf.Table{root,answers},session)
    proof(data,cfg,stmt,path,copy,plans)

def digest(cfg: C.Configured) -> H.Bytes:
  C.Configured{d,_} = cfg
  d

def stage(+folder: String, path: String, r: String, y: String, tables: String, +plans: String, named: Maybe<&2,String>) -> IO(Unit):
  +config = folder ++ "/config"
  +ivk = folder ++ "/ivk"
  do IO<Unit>:
    +stmt : S.Statement <- S.load(config,r,y,tables,named)
    +cfg : C.Configured <- C.load(stmt,config,plans)
    key : Key.AttestedKey <- Key.check_transcript(ivk ++ "/key.bin",digest(cfg),plans)
    entry(key,cfg,stmt,ivk,path,plans)

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,folder,path,r,y,tables,plans]: stage(folder,path,r,y,tables,plans,None{})
    case [_,folder,path,r,y,tables,plans,named]: stage(folder,path,r,y,tables,plans,Some{named})
    case _: IO.die(Unit,2,"usage: request_stage EXAMPLE PROOF REQUEST Y TABLES PLANS [POLICY]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
