import Base
import ./key_stage_batt.bend as Batt
import ./lin_own.bend as Own
import ./lin_shared.bend as LinShared
import ./lin_bridge.bend as Lin
import ./leaf_stage.bend as Leaf
import ./wire_item.bend as Item
import ./key_stage_geometry.bend as G
import ./key_stage_codes.bend as C
import ./key_stage_openings.bend as K
import ./key_stage_walk.bend as W
import ./opening_bytes.bend as O
import ./wire_reader.bend as R
import ./plan.bend as Plan
import ./plan_types.bend as Profile
import ./plan_catalog.bend as Catalog
import ./hash_bytes.bend as H
import ./merkle.bend as M
import ./commitment.bend as Commitment
import ./header.bend as Header

# R13.2-7. This evidence authenticates three transcripts and their openings.
# The protocol equations use the transcript as an input to the stage decision.
type AttestedKey is Data:
  AttestedKey{table: M.Digest, answers: H.Bytes, first_seal: H.Bytes, shared_seal: H.Bytes, rho: H.Bytes, session: O.Session}

type Table is Data:
  Table{root: M.Digest, record: H.Bytes, statement: H.Bytes}

type Context is Data:
  Context{profile: Profile.Profile, config: M.Digest, plans: String, table: Table, salt: U32, finals: C.Finals, pending: Own.First}

def table_item(items: List<&2,Plan.Item>) -> IO(H.Bytes):
  match items:
    case []: IO.die(H.Bytes,1,"NO: key-plan-item")
    case Plan.Item{id,bytes} <> tail:
      match id:
        case "the test on the table": IO.pure(H.Bytes,bytes)
        case _: table_item(tail)

def table_size(numbers: H.Bytes) -> IO(U32):
  match numbers:
    case [_,_,_,+v,1,_]:
      do IO<U32>:
        ok : Unit <- Header.require(U32.is_le(v,20),"NO: key-table-size")
        return U32.shln(24,U32.to_nat(v))
    case _: IO.die(U32,1,"NO: key-table-shape")

def size(items: List<&2,Plan.Item>) -> IO(U32):
  do IO<U32>:
    raw : H.Bytes <- table_item(items)
    words : H.Bytes <- R.words(H.u32s(List.take(&2,U32,raw,48n)))
    table_size(words)

def finish(pair: R.Reader & W.End, table: Table, first_seal: H.Bytes, shared_seal: H.Bytes) -> IO(AttestedKey):
  (r,ended) = pair
  W.End{_,session,_,rho} = ended
  Table{root,record,_} = table
  do IO<AttestedKey>:
    eof : Unit <- R.end_proof(r)
    return AttestedKey{root,record,first_seal,shared_seal,rho,session}

def table_root(table: Table) -> M.Digest:
  Table{root,_,_} = table
  root

def own_result(pair: R.Reader & W.Traced, adopted: LinShared.Adopted, first: Own.First) -> IO(R.Reader & W.End):
  (r,W.Traced{end,events,_}) = pair
  do IO<R.Reader & W.End>:
    complete : Unit <- Own.check(events,adopted,first)
    return (r,end)

def second(pair: R.Reader & Lin.Shared, ctx: Context, first_book: K.Book, +first_seal: H.Bytes) -> IO(AttestedKey):
  (r,Lin.Shared{W.End{book,session,+seal,_},adopted}) = pair
  Context{profile,+conf,plans,+table,_,C.Finals{_,_,_,own},pending} = ctx
  root = table_root(table)
  statement = H.cat([Item.item("the seal of an earlier chain",first_seal),Item.item("the seal of an earlier chain",seal)])
  do IO<AttestedKey>:
    omega : K.Root <- K.at(book,1n)
    plan : Plan.Plan <- Plan.load(O.digest_bytes(conf),Profile.KeySecond{},plans)
    random : R.Reader & H.Bytes <- R.take(r,32)
    trace : R.Reader & W.Traced <- W.begin_traced(random,1279872514n,plan,statement,conf,root,
      List.append(&2,K.Root,first_book,[omega]),session,G.schedule(profile,Profile.KeySecond{}),[own])
    last : R.Reader & W.End <- own_result(trace,adopted,pending)
    finish(last,table,first_seal,seal)

def shared(pair: R.Reader & H.Bytes, +ctx: Context, first_book: K.Book, session: O.Session, +seal: H.Bytes) -> IO(AttestedKey):
  (r,+binding) = pair
  Context{profile,+conf,plans,Table{+root,record,st},+salt,C.Finals{_,fold,omega,_},_} = ctx
  do IO<AttestedKey>:
    ok : Unit <- Header.require(R.equal(List.take(&2,U32,binding,8n),H.word(0)),"NO: key-binding-slot")
    +bound : M.Digest <- K.need(M.Digest,O.binding_root(0n,0n,conf,seal,
      List.drop(&2,U32,binding,8n),U32.to_nat(salt),[]),"NO: key-binding")
    +plan : Plan.Plan <- Plan.load(O.digest_bytes(conf),Profile.KeyShared{},plans)
    trace : R.Reader & W.Traced <- W.begin_traced((r,O.digest_bytes(bound)),1279872513n,plan,
      H.cat([st,Item.item("the binding tree's root",O.digest_bytes(bound))]),conf,root,[],session,G.schedule(profile,Profile.KeyShared{}),[fold,omega])
    end : R.Reader & Lin.Shared <- Lin.check(trace,plan,Leaf.Table{root,record},O.digest_bytes(conf))
    second(end,ctx,first_book,seal)

def bind(pair: R.Reader & W.End, +ctx: Context) -> IO(AttestedKey):
  (r,ended) = pair
  W.End{book,session,seal,_} = ended
  Context{_,_,_,_,salt,_,_} = ctx
  do IO<AttestedKey>:
    slot : R.Reader & H.Bytes <- R.take(r,U32.add(8,salt))
    shared(slot,ctx,book,session,seal)

def range_code(finals: C.Finals) -> List<&2,C.Final>:
  C.Finals{r,_,_,_} = finals
  [r]

# A verified one-time chain and its public context, just before the binding tree and two LIN chains.
type FirstChain is Data:
  FirstChain{trace: W.Traced, profile: Profile.Profile, config: M.Digest, table: Table, salt: U32, finals: C.Finals}

def bind_claim(r: R.Reader, input: FirstChain, plans: String, pending: Own.First) -> IO(AttestedKey):
  FirstChain{W.Traced{ended,_,_},profile,conf,table,salt,finals} = input
  bind((r,ended),Context{profile,conf,plans,table,salt,finals,pending})

def matrix(input: FirstChain) -> IO(Own.First):
  FirstChain{W.Traced{_,events,ranges},_,_,_,_,_} = input
  do IO<Own.First>:
    derived : Batt.Sealed <- Batt.combine(ranges,events)
    Batt.lin(derived)

def continue_once(pair: R.Reader & FirstChain, plans: String) -> IO(AttestedKey):
  (r,+input) = pair
  do IO<AttestedKey>:
    pending : Own.First <- matrix(input)
    bind_claim(r,input,plans,pending)

def first_chain(pair: R.Reader & W.Traced, profile: Profile.Profile, conf: M.Digest, table: Table,
  salt: U32, finals: C.Finals) -> R.Reader & FirstChain:
  (next,trace) = pair
  (next,FirstChain{trace,profile,conf,table,salt,finals})

def one(pair: R.Reader & H.Bytes, +profile: Profile.Profile, +conf: M.Digest,
  +plan: Plan.Plan, +table: M.Digest, n: U32) -> IO(R.Reader & FirstChain):
  (r,+record) = pair
  Plan.Plan{_,Plan.Settings{salt,_,_,_,_},_,items} = plan
  +st = Item.item("table",H.cat([Item.blob(O.digest_bytes(table)),H.word(U32.div(n,24)),record]))
  do IO<R.Reader & FirstChain>:
    ok : Unit <- Header.require(Commitment.canonical(H.u32s(record)),"NO: key-record")
    rb : R.Reader & H.Bytes <- R.take(r,32)
    +finals : C.Finals <- C.load(items)
    first : R.Reader & W.Traced <- W.begin_traced(rb,1179798786n,plan,st,conf,table,[],O.empty_session(),G.schedule(profile,Profile.KeyOnce{}),range_code(finals))
    return first_chain(first,profile,conf,Table{table,record,st},salt,finals)

def start(pair: R.Reader & H.Bytes, profile: Profile.Profile, conf: M.Digest, +plan: Plan.Plan) -> IO(R.Reader & FirstChain):
  (r,+head) = pair
  Plan.Plan{_,_,_,items} = plan
  do IO<R.Reader & FirstChain>:
    ok : Unit <- Header.require(Header.key_head(List.take(&2,U32,head,8n)),"NO: key-header")
    root : M.Digest <- K.digest(List.drop(&2,U32,head,8n))
    +n : U32 <- size(items)
    record : R.Reader & H.Bytes <- R.take(r,n)
    one(record,profile,conf,plan,root,n)

def open_once(path: String, +config: H.Bytes, plans_dir: String) -> IO(R.Reader & FirstChain):
  do IO<R.Reader & FirstChain>:
    profile : Profile.Profile <- K.need(Profile.Profile,Catalog.select(H.u32s(config)),"NO: key-configuration")
    cfg : M.Digest <- K.digest(config)
    first : Plan.Plan <- Plan.load(config,Profile.KeyOnce{},plans_dir)
    r : R.Reader <- R.open_proof(path,4294967295)
    head : R.Reader & H.Bytes <- R.take(r,40)
    start(head,profile,cfg,first)

def check_transcript(path: String, config: H.Bytes, +plans_dir: String) -> IO(AttestedKey):
  do IO<AttestedKey>:
    once : R.Reader & FirstChain <- open_once(path,config,plans_dir)
    continue_once(once,plans_dir)
