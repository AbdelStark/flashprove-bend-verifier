import Base
import ./hash_bytes.bend as H
import ./header.bend as Header
import ./commitment.bend as C
import ./layout.bend as Layout
import ./plan.bend as Plan
import ./plan_types.bend as PT
import ./policy.bend as Policy
import ./policy_frame.bend as Frame
import ./policy_statement.bend as S

type Snapshot is Data:
  Snapshot{digest: H.Bytes, layout: H.Bytes}

def word_bytes(words: H.Bytes) -> H.Bytes:
  match words:
    case []: []
    case x <> tail: H.cat([H.le(x),word_bytes(tail)])

def sized(ctx: H.Context, +raw: H.Bytes) -> H.Context:
  H.update(H.update(ctx,H.word(U32.from_nat(List.length(&2,U32,raw)))),raw)

def snapshot(st: S.Statement, +layout: H.Bytes) -> Snapshot:
  S.Statement{_,_,_,_,scales,_,_,lines} = st
  policy = Layout.chars(String.join(lines,"\n"))
  h = sized(sized(sized(C.config_start(),policy),layout),word_bytes(scales))
  Snapshot{H.finish(h,32),layout}

def read_layout(config: String) -> IO(H.Bytes):
  do IO<H.Bytes>:
    # The longest layout among the released configuration profiles is 224975
    # bytes. A larger input cannot match a configuration digest in the catalog.
    +raw : H.Bytes <- Header.bytes(config ++ "/layout.txt",224976)
    ok : Unit <- Header.require(Nat.is_le(List.length(&2,U32,raw),224975n),"NO: unsupported-configuration")
    return raw

def width(codes: List<&2,Frame.Words>) -> IO(Nat):
  match codes:
    case [_,_,bits,_,_] <> _: IO.pure(Nat,Nat.pow(2n,U32.to_nat(bits)))
    case _: IO.die(Nat,1,"NO: parameter-group-shape")

def verify_config(st: S.Statement, snap: Snapshot, plan: Plan.Plan) -> IO(Unit):
  S.Statement{_,_,_,_,_,Frame.Frame{_,_,_,_,codes,_,_,_,_,_,_,_},_,+lines} = st
  Snapshot{_,layout} = snap
  Plan.Plan{_,_,_,items} = plan
  do IO<Unit>:
    l : U32 <- Policy.field(lines,"L")
    ll : U32 <- Policy.field(lines,"ll")
    +af : U32 <- Policy.field(lines,"NAf")
    +ad : U32 <- Policy.field(lines,"NAd")
    +sa : U32 <- Policy.field(lines,"NAs")
    +hf : U32 <- Policy.field(lines,"NHf")
    ok : Unit <- Header.require(Frame.within(af,1,64) && Frame.within(ad,1,64) &&
      Frame.within(sa,1,64) && Frame.within(hf,1,64), "NO: plan-layout")
    places : Nat <- width(codes)
    model : Layout.Model = Layout.Model{U32.add(1,U32.mul(2,U32.shrn(l,U32.to_nat(ll)))),
      U32.add(2,U32.add(af,ad)),U32.add(sa,3),U32.add(hf,3)}
    Layout.check(layout,model,places,items)


type Configured is Data:
  Configured{digest: H.Bytes, request_plan: Plan.Plan}

def authenticated(+st: S.Statement, +snap: Snapshot, plans_dir: String) -> IO(Configured):
  Snapshot{+digest,_} = snap
  do IO<Configured>:
    +plan : Plan.Plan <- Plan.load(digest,PT.RequestFirst{},plans_dir)
    ok : Unit <- verify_config(st,snap,plan)
    return Configured{digest,plan}

def use(+st: S.Statement, raw: H.Bytes, plans_dir: String) -> IO(Configured):
  authenticated(st,snapshot(st,raw),plans_dir)

def load(st: S.Statement, config: String, plans_dir: String) -> IO(Configured):
  do IO<Configured>:
    raw : H.Bytes <- read_layout(config)
    use(st,raw,plans_dir)


def key_shape(st: S.Statement) -> C.Shape:
  S.Statement{_,_,_,_,_,Frame.Frame{_,_,salt,_,_,_,_,b,n,i,m,_},_,_} = st
  C.Shape{b,n,i,m,salt}
