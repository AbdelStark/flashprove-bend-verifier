import Base
import ./leaf_walk.bend as W
import ./leaf_shape.bend as S
import ./wire_item.bend as Item
import ./key_stage_openings.bend as K
import ./plan_types.bend as Profile
import ./plan.bend as P
import ./opening_bytes.bend as O
import ./hash_bytes.bend as H
import ./wire_reader.bend as R
import ./merkle.bend as M
import ./commitment.bend as Commitment
import ./header.bend as Header
import ./transcript.bend as T

type Table is Data:
  Table{root: M.Digest, record: H.Bytes}

type Trace is Data:
  Trace{shape: S.Shape, anchor: Table, leaf: Table, rounds: List<&2,W.EntryRound>, session: O.Session, rho: H.Bytes}

def table_bytes(table: Table) -> H.Bytes:
  Table{root,+answers} = table
  H.cat([Item.blob(O.digest_bytes(root)),H.word(U32.from_nat(Nat.div(List.length(&2,U32,answers),24n))),answers])

def finish(pair: R.Reader & W.Cursor, shape: S.Shape, anchor: Table, leaf: Table) -> IO(Trace):
  (r,W.Cursor{T.State{_,_,rho},session,book,next,stages,_,events}) = pair
  do IO<Trace>:
    closed : Unit <- Header.require(List.is_empty(&2,S.Stage,stages) && Nat.is_eq(List.length(&2,K.Root,book),next),"NO: leaf-unopened-tree")
    eof : Unit <- R.end_proof(r)
    return Trace{shape,anchor,leaf,List.reverse(&2,W.EntryRound,events),session,rho}

def start(opened: T.Start, r: R.Reader, cfg: M.Digest, salt: U32, +shape: S.Shape, anchor: Table, leaf: Table,
  first: M.Digest, second: M.Digest, stages: List<&2,S.Stage>, rounds: List<&2,P.Round>, session: O.Session) -> IO(Trace):
  T.Start{state,run} = opened
  match rounds:
    case P.Round{"RECORD",1,_,_,_,_,_,_,_,_,_,_} <> tail:
      do IO<Trace>:
        bytes : H.Bytes <- K.need(H.Bytes,run,"NO: leaf-run")
        id : M.Digest <- K.digest(bytes)
        out : R.Reader & W.Cursor <- W.walk(tail,W.Context{cfg,first,second,id,shape,U32.to_nat(salt)},(r,W.Cursor{state,session,[],0n,stages,None{},[]}))
        finish(out,shape,anchor,leaf)
    case _: IO.die(Trace,1,"NO: leaf-record-plan")

def walk(random: R.Reader & H.Bytes, cfg: M.Digest, plan: P.Plan, +shape: S.Shape, +anchor: Table, +leaf: Table, session: O.Session) -> IO(Trace):
  (r,seed) = random
  P.Plan{digest,P.Settings{salt,_,_,_,_},rounds,_} = plan
  S.Shape{_,_,_,_,_,_,_,_,_,stages} = shape
  Table{first,_} = anchor
  Table{second,_} = leaf
  statement = H.cat([Item.item("the first table",table_bytes(anchor)),Item.item("the further table",table_bytes(leaf))])
  do IO<Trace>:
    opened : T.Start <- K.need(T.Start,T.begin(1280199425n,digest,statement,Some{seed}),"NO: leaf-chain")
    start(opened,r,cfg,salt,shape,anchor,leaf,first,second,stages,rounds,session)

def read_record(pair: R.Reader & H.Bytes, root: M.Digest, cfg: M.Digest, plan: P.Plan, shape: S.Shape, anchor: Table, session: O.Session) -> IO(Trace):
  (r,+answers) = pair
  do IO<Trace>:
    ok : Unit <- Header.require(Commitment.canonical(H.u32s(answers)),"NO: leaf-record")
    random : R.Reader & H.Bytes <- R.take(r,32)
    walk(random,cfg,plan,shape,anchor,Table{root,answers},session)

def head(pair: R.Reader & H.Bytes, cfg: M.Digest, plan: P.Plan, +shape: S.Shape, anchor: Table, session: O.Session) -> IO(Trace):
  (r,+bytes) = pair
  S.Shape{_,_,_,v,count,_,_,_,_,_} = shape
  do IO<Trace>:
    ok : Unit <- Header.require(Header.leaf_head(List.take(&2,U32,bytes,8n)),"NO: leaf-header")
    root : M.Digest <- K.digest(List.drop(&2,U32,bytes,8n))
    data : R.Reader & H.Bytes <- R.take(r,U32.shln(U32.mul(24,count),U32.to_nat(v)))
    read_record(data,root,cfg,plan,shape,anchor,session)

def items(plan: P.Plan) -> List<&2,P.Item>:
  P.Plan{_,_,_,xs} = plan
  xs

def inspect(path: String, +config: H.Bytes, plans: String, anchor: Table, session: O.Session) -> IO(Trace):
  do IO<Trace>:
    cfg : M.Digest <- K.digest(config)
    +plan : P.Plan <- P.load(config,Profile.Entry{},plans)
    +shape : S.Shape <- S.from_items(items(plan))
    r : R.Reader <- R.open_proof(path,4294967295)
    data : R.Reader & H.Bytes <- R.take(r,40)
    head(data,cfg,plan,shape,anchor,session)
