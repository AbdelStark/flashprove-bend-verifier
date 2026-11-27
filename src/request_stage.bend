import Base
import ./lin_own.bend as Own
import ./lin_shared.bend as Shared
import ./lin_bridge.bend as Lin
import ./wire_item.bend as Item
import ./policy_statement.bend as S
import ./policy_config.bend as Config
import ./policy.bend as Policy
import ./header.bend as Header
import ./hash_bytes.bend as H
import ./wire_reader.bend as R
import ./plan.bend as P
import ./plan_types.bend as PT
import ./plan_catalog.bend as Catalog
import ./key_stage_walk.bend as W
import ./key_stage_openings.bend as K
import ./key_stage_codes.bend as Codes
import ./leaf_shape.bend as Shapes
import ./leaf_stage.bend as Leaf
import ./opening_bytes.bend as O
import ./merkle.bend as M
import ./request_geometry.bend as G
import ./request_walk.bend as RW
import ./segment_inputs.bend as Inputs
import ./segment_chain.bend as Chain
import ./key_stage_trace.bend as Events
import ./segment_stage.bend as Seg
import ./segment_geometry.bend as SG
import ./policy_tables.bend as Tables
import ./pow2.bend as P2

# The transcript stage returns evidence to the checkers of segment and fold
# claims. Only the whole-call verifier can issue a proof verdict.
type Trace is Data:
  Trace{slot: Nat, binding: M.Digest, first_seal: H.Bytes, shared_seal: H.Bytes, rho: H.Bytes, session: O.Session, forests: Seg.Groups}

type Geometry is Data:
  Geometry{depth: Nat, salt: Nat, finals: Codes.Finals}

type Context is Data:
  Context{cfg: M.Digest, profile: PT.Profile, dir: String, table: M.Digest, statement: H.Bytes, geometry: Geometry, record: H.Bytes}

def dimensions(raw: H.Bytes, finals: Codes.Finals) -> IO(Geometry):
  match raw:
    case [+depth,+salt]:
      do IO<Geometry>:
        ok : Unit <- Header.require(U32.is_le(depth,48) && U32.is_ge(salt,40) && U32.is_le(salt,64), "NO: request-binding-shape")
        return Geometry{U32.to_nat(depth),U32.to_nat(salt),finals}
    case _: IO.die(Geometry,1,"NO: request-binding-shape")

def geometry(+items: List<&2,P.Item>) -> IO(Geometry):
  do IO<Geometry>:
    raw : H.Bytes <- Codes.item(items,"codes")
    ws : H.Bytes <- R.words(H.u32s(raw))
    +cs : Shapes.Codes <- Shapes.codes(ws)
    # R12.14 ends in the stages of the last proximity test and its choices.
    shape : H.Bytes <- Codes.item(items,"request's shape")
    last : Codes.Final <- Codes.range_final(shape,cs)
    table : H.Bytes <- Codes.table_words(items)
    folded : Codes.Rest <- Codes.last(List.drop(&2,U32,table,50n),cs)
    finals : Codes.Finals <- Codes.omega(folded,cs,last)
    tree : H.Bytes <- Codes.item(items,"binding tree")
    w : H.Bytes <- R.words(H.u32s(tree))
    dimensions(w,finals)

def complete(pair: R.Reader & W.End, slot: Nat, binding: M.Digest, first: H.Bytes, shared: H.Bytes) -> IO(Trace):
  (r,W.End{_,session,_,rho}) = pair
  do IO<Trace>:
    done : Unit <- R.end_proof(r)
    return Trace{slot,binding,first,shared,rho,session,[]}

def finish_own(trace: R.Reader & W.Traced, adopted: Shared.Adopted, pending: Own.First) -> IO(R.Reader & W.End):
  (r,W.Traced{end,events,_}) = trace
  do IO<R.Reader & W.End>:
    ok : Unit <- Own.check(events,adopted,pending)
    return (r,end)

def check_own(trace: R.Reader & W.Traced, adopted: Shared.Adopted, pending: Maybe<&2,Own.First>) -> IO(R.Reader & W.End):
  match pending:
    case None{}: IO.pure(R.Reader & W.End,W.end_only(trace))
    case Some{p}: finish_own(trace,adopted,p)

def second(shared: R.Reader & Lin.Shared, ctx: Context, slot: Nat, binding: M.Digest, book: K.Book, +first: H.Bytes, pending: Maybe<&2,Own.First>) -> IO(Trace):
  (r,Lin.Shared{W.End{published,session,+seal,_},adopted}) = shared
  Context{+cfg,profile,dir,table,_,Geometry{_,_,Codes.Finals{_,_,_,own}},_} = ctx
  stmt = H.cat([Item.item("the seal of an earlier chain",first),Item.item("the seal of an earlier chain",seal)])
  do IO<Trace>:
    # R14.10. Omega occupies place 1 in the split shared chain and keeps its
    # original tree number and run when appended to the first chain's book.
    omega : K.Root <- K.at(published,1n)
    plan : P.Plan <- P.load(O.digest_bytes(cfg),PT.RequestSecond{},dir)
    rb : R.Reader & H.Bytes <- R.take(r,32)
    traced : R.Reader & W.Traced <- W.begin_traced(rb,1179798788n,plan,stmt,cfg,table,
      List.append(&2,K.Root,book,[omega]),session,G.schedule(profile,PT.RequestSecond{}),[own])
    result : R.Reader & W.End <- check_own(traced,adopted,pending)
    complete(result,slot,binding,first,seal)

def slot_number(lo: U32, +hi: U32) -> IO(Nat):
  do IO<Nat>:
    ok : Unit <- Header.require(U32.is_lt(hi,65536),"NO: request-binding-slot")
    return Nat.add(U32.to_nat(lo),Nat.mul(U32.to_nat(hi),P2.pow2(32n)))

def slot(raw: H.Bytes) -> IO(Nat):
  match raw:
    case [lo,hi]: slot_number(lo,hi)
    case _: IO.die(Nat,1,"NO: request-binding-slot")

def shared(pair: R.Reader & H.Bytes, +ctx: Context, book: K.Book, session: O.Session, +seal: H.Bytes, pending: Maybe<&2,Own.First>) -> IO(Trace):
  (r,+path) = pair
  Context{+cfg,profile,dir,+table,st,Geometry{+depth,+salt,Codes.Finals{_,fold,omega,_}},record} = ctx
  do IO<Trace>:
    +number : Nat <- slot(H.u32s(List.take(&2,U32,path,8n)))
    +root : M.Digest <- K.need(M.Digest,O.binding_root(depth,number,cfg,seal,
      List.take(&2,U32,List.drop(&2,U32,path,8n),salt),salt,
      O.digests(H.u32s(List.drop(&2,U32,path,Nat.add(8n,salt))))),"NO: request-binding-slot")
    opened : O.Opened <- K.need(O.Opened,O.binding_record(depth,number,cfg,root,salt,
      H.cat([seal,List.drop(&2,U32,path,8n)]),session),"NO: request-binding-vertex")
    +plan : P.Plan <- P.load(O.digest_bytes(cfg),PT.RequestShared{},dir)
    trace : R.Reader & W.Traced <- W.begin_traced((r,O.digest_bytes(root)),1179798787n,plan,
      H.cat([st,Item.item("the binding tree's root",O.digest_bytes(root))]),cfg,table,[],O.retained(opened),
      G.schedule(profile,PT.RequestShared{}),[fold,omega])
    result : R.Reader & Lin.Shared <- Lin.check(trace,plan,Leaf.Table{table,record},O.digest_bytes(cfg))
    second(result,ctx,number,root,book,seal,pending)

def binding_result(pair: R.Reader & W.End, +ctx: Context, pending: Maybe<&2,Own.First>) -> IO(Trace):
  (r,W.End{book,session,seal,_}) = pair
  Context{_,_,_,_,_,Geometry{depth,salt,_},_} = ctx
  do IO<Trace>:
    path : R.Reader & H.Bytes <- R.take(r,U32.from_nat(Nat.add(8n,Nat.add(salt,Nat.mul(32n,depth)))))
    shared(path,ctx,book,session,seal,pending)

# The transcript inspection entry point captures the second chain before its request equation is supplied.
def binding(pair: R.Reader & W.End, ctx: Context) -> IO(Trace): binding_result(pair,ctx,None{})

def binding_checked(pair: R.Reader & W.End, ctx: Context, first: Own.First) -> IO(Trace):
  binding_result(pair,ctx,Some{first})

def results(trace: Trace, forests: Seg.Groups) -> Trace:
  Trace{slot,root,first,shared,rho,session,_} = trace
  Trace{slot,root,first,shared,rho,session,forests}

type FirstData is Data:
  FirstData{end: W.End, events: Events.Events, context: Context, forests: Seg.Groups, statement: S.Statement}

def family_inputs(data: FirstData) -> IO(Inputs.Batches):
  FirstData{_,events,Context{_,profile,_,_,_,_,_},rows,st} = data
  Inputs.batches(Inputs.shapes(SG.select(profile)),rows,0n,st,events,[])

def model(pair: R.Reader & W.Traced,+ctx: Context,+st: S.Statement) -> IO(R.Reader & FirstData):
  (r,W.Traced{end,+events,_}) = pair
  Context{_,profile,_,_,_,_,_} = ctx
  S.Statement{_,_,_,tables,_,_,_,_} = st
  do IO<R.Reader & FirstData>:
    rows : Seg.Groups <- Seg.checks(SG.select(profile),events,0n,tables,[])
    return (r,FirstData{end,events,ctx,rows,st})

def continue_first(pair: R.Reader & FirstData) -> IO(Trace):
  (r,FirstData{end,_,ctx,rows,_}) = pair
  do IO<Trace>:
    result : Trace <- binding((r,end),ctx)
    return results(result,rows)

def first(pair: R.Reader & H.Bytes, expected: U32, +st: S.Statement, +plan: P.Plan, +ctx: Context, session: O.Session) -> IO(R.Reader & FirstData):
  (r,header) = pair
  S.Statement{words,req,y,tables,_,_,_,lines} = st
  Context{cfg,+profile,_,table,table_item,Geometry{_,_,Codes.Finals{last,_,_,_}},_} = ctx
  do IO<R.Reader & FirstData>:
    +copy : U32 <- Header.leaf_index(header)
    ok : Unit <- Header.require(U32.is_eq(copy,expected),"NO: request-stored-copy")
    vocab : U32 <- Policy.field(lines,"V")
    statement : H.Bytes = H.cat([table_item,Item.item("stored copy",H.word(copy)),
      Item.item("request",Item.blob(Config.word_bytes(words))),Item.item("the request file's words",Item.blob(Config.word_bytes(req)))])
    rb : R.Reader & H.Bytes <- R.take(r,32)
    done : R.Reader & W.Traced <- RW.first(rb,plan,statement,cfg,table,session,G.schedule(profile,PT.RequestFirst{}),last,y,vocab)
    model(done,ctx,st)

def first_data(path: String, expected_copy: U32, st: S.Statement, cfg: Config.Configured,
    plans_dir: String, +leaf: Leaf.Table, session: O.Session) -> IO(R.Reader & FirstData):
  Config.Configured{+bytes,+plan} = cfg
  Leaf.Table{root,record} = leaf
  do IO<R.Reader & FirstData>:
    profile : PT.Profile <- K.need(PT.Profile,Catalog.select(H.u32s(bytes)),"NO: unsupported-configuration")
    digest : M.Digest <- K.digest(bytes)
    geom : Geometry <- geometry(Leaf.items(plan))
    r : R.Reader <- R.open_proof(path,4294967295)
    head : R.Reader & H.Bytes <- R.take(r,12)
    first(head,expected_copy,st,plan,Context{digest,profile,plans_dir,root,Item.item("table",Leaf.table_bytes(leaf)),geom,record},session)

def inspect(path: String, expected_copy: U32, st: S.Statement, cfg: Config.Configured,
    plans_dir: String, leaf: Leaf.Table, session: O.Session) -> IO(Trace):
  do IO<Trace>:
    saved : R.Reader & FirstData <- first_data(path,expected_copy,st,cfg,plans_dir,leaf,session)
    continue_first(saved)

def close_verified(pair: R.Reader & FirstData,items: List<&2,P.Item>) -> IO(Trace):
  (reader,FirstData{end,+events,+ctx,+forests,st}) = pair
  Context{_,+profile,_,_,_,_,_} = ctx
  do IO<Trace>:
    inputs : Inputs.Batches <- Inputs.batches(Inputs.shapes(SG.select(profile)),forests,0n,st,events,[])
    claim : Own.First <- Chain.verify(inputs,events,items,profile)
    result : Trace <- binding_checked((reader,end),ctx,claim)
    return results(result,forests)

def verify(path: String, expected_copy: U32, st: S.Statement, +cfg: Config.Configured,
    plans_dir: String, leaf: Leaf.Table, session: O.Session) -> IO(Trace):
  Config.Configured{_,plan} = cfg
  do IO<Trace>:
    saved : R.Reader & FirstData <- first_data(path,expected_copy,st,cfg,plans_dir,leaf,session)
    close_verified(saved,Leaf.items(plan))
