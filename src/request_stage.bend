import Base
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

# The transcript stage returns evidence to the checkers of segment and fold
# claims. Only the whole-call verifier can issue a proof verdict.
type Trace is Data:
  Trace{slot: Nat, binding: M.Digest, first_seal: H.Bytes, shared_seal: H.Bytes, rho: H.Bytes, session: O.Session}

type Geometry is Data:
  Geometry{depth: Nat, salt: Nat, finals: Codes.Finals}

type Context is Data:
  Context{cfg: M.Digest, profile: PT.Profile, dir: String, table: M.Digest, statement: H.Bytes, geometry: Geometry}

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
    return Trace{slot,binding,first,shared,rho,session}

def second(shared: R.Reader & W.End, ctx: Context, slot: Nat, binding: M.Digest, book: K.Book, +first: H.Bytes) -> IO(Trace):
  (r,W.End{published,session,+seal,_}) = shared
  Context{+cfg,profile,dir,table,_,Geometry{_,_,Codes.Finals{_,_,_,own}}} = ctx
  stmt = H.cat([Item.item("the seal of an earlier chain",first),Item.item("the seal of an earlier chain",seal)])
  do IO<Trace>:
    # R14.10. Omega occupies place 1 in the split shared chain and keeps its
    # original tree number and run when appended to the first chain's book.
    omega : K.Root <- K.at(published,1n)
    plan : P.Plan <- P.load(O.digest_bytes(cfg),PT.RequestSecond{},dir)
    rb : R.Reader & H.Bytes <- R.take(r,32)
    result : R.Reader & W.End <- W.begin(rb,1179798788n,plan,stmt,cfg,table,
      List.append(&2,K.Root,book,[omega]),session,G.schedule(profile,PT.RequestSecond{}),[own])
    complete(result,slot,binding,first,seal)

def slot_number(lo: U32, +hi: U32) -> IO(Nat):
  do IO<Nat>:
    ok : Unit <- Header.require(U32.is_lt(hi,65536),"NO: request-binding-slot")
    return Nat.add(U32.to_nat(lo),Nat.mul(U32.to_nat(hi),Nat.pow(2n,32n)))

def slot(raw: H.Bytes) -> IO(Nat):
  match raw:
    case [lo,hi]: slot_number(lo,hi)
    case _: IO.die(Nat,1,"NO: request-binding-slot")

def shared(pair: R.Reader & H.Bytes, +ctx: Context, book: K.Book, session: O.Session, +seal: H.Bytes) -> IO(Trace):
  (r,+path) = pair
  Context{+cfg,profile,dir,table,st,Geometry{+depth,+salt,Codes.Finals{_,fold,omega,_}}} = ctx
  do IO<Trace>:
    +number : Nat <- slot(H.u32s(List.take(&2,U32,path,8n)))
    +root : M.Digest <- K.need(M.Digest,O.binding_root(depth,number,cfg,seal,
      List.take(&2,U32,List.drop(&2,U32,path,8n),salt),salt,
      O.digests(H.u32s(List.drop(&2,U32,path,Nat.add(8n,salt))))),"NO: request-binding-slot")
    plan : P.Plan <- P.load(O.digest_bytes(cfg),PT.RequestShared{},dir)
    result : R.Reader & W.End <- W.begin((r,O.digest_bytes(root)),1179798787n,plan,
      H.cat([st,Item.item("the binding tree's root",O.digest_bytes(root))]),cfg,table,[],session,
      G.schedule(profile,PT.RequestShared{}),[fold,omega])
    second(result,ctx,number,root,book,seal)

def binding(pair: R.Reader & W.End, +ctx: Context) -> IO(Trace):
  (r,W.End{book,session,seal,_}) = pair
  Context{_,_,_,_,_,Geometry{depth,salt,_}} = ctx
  do IO<Trace>:
    path : R.Reader & H.Bytes <- R.take(r,U32.from_nat(Nat.add(8n,Nat.add(salt,Nat.mul(32n,depth)))))
    shared(path,ctx,book,session,seal)

def first(pair: R.Reader & H.Bytes, expected: U32, st: S.Statement, +plan: P.Plan, +ctx: Context, session: O.Session) -> IO(Trace):
  (r,header) = pair
  S.Statement{words,req,y,_,_,_,_,lines} = st
  Context{cfg,profile,_,table,table_item,Geometry{_,_,Codes.Finals{last,_,_,_}}} = ctx
  do IO<Trace>:
    +copy : U32 <- Header.leaf_index(header)
    ok : Unit <- Header.require(U32.is_eq(copy,expected),"NO: request-stored-copy")
    vocab : U32 <- Policy.field(lines,"V")
    statement : H.Bytes = H.cat([table_item,Item.item("stored copy",H.word(copy)),
      Item.item("request",Item.blob(Config.word_bytes(words))),Item.item("the request file's words",Item.blob(Config.word_bytes(req)))])
    rb : R.Reader & H.Bytes <- R.take(r,32)
    done : R.Reader & W.End <- RW.first(rb,plan,statement,cfg,table,session,G.schedule(profile,PT.RequestFirst{}),last,y,vocab)
    binding(done,ctx)

def inspect(path: String, expected_copy: U32, st: S.Statement, cfg: Config.Configured,
    plans_dir: String, +leaf: Leaf.Table, session: O.Session) -> IO(Trace):
  Config.Configured{+bytes,+plan} = cfg
  Leaf.Table{root,_} = leaf
  do IO<Trace>:
    profile : PT.Profile <- K.need(PT.Profile,Catalog.select(H.u32s(bytes)),"NO: unsupported-configuration")
    digest : M.Digest <- K.digest(bytes)
    geom : Geometry <- geometry(Leaf.items(plan))
    r : R.Reader <- R.open_proof(path,4294967295)
    head : R.Reader & H.Bytes <- R.take(r,12)
    first(head,expected_copy,st,plan,Context{digest,profile,plans_dir,root,Item.item("table",Leaf.table_bytes(leaf)),geom},session)
