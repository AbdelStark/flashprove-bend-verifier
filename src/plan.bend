import Base
import ./header.bend as Header
import ./hash_bytes.bend as H
import ./plan_types.bend as P
import ./plan_catalog.bend as Catalog
import ./wire_reader.bend as R

type Round is Data:
  Round{name: String, count: U32, work: U32, bytes: U32, roots: U32,
    answers: U32, elements: U32, nonzero: U32, positions: U32, depth: U32, trits: U32, rows: U32}

type Settings is Data:
  Settings{salt: U32, nonce: U32, position: U32, samples: U32, saved: U32}

type Item is Data:
  Item{name: String, bytes: H.Bytes}

type Plan is Data:
  Plan{digest: H.Bytes, settings: Settings, rounds: List<&2, Round>, items: List<&2, Item>}

def version_ok(raw: H.Bytes) -> Bool:
  match raw:
    case [72,56,50,49,0,0,0,0]: True{}
    case _: False{}

def named_body(pair: R.Reader & H.Bytes, name: String) -> R.Reader & Item:
  (r, data) = pair
  (r, Item{name, data})

def read_body(pair: R.Reader & U32, name: String) -> IO(R.Reader & Item):
  (r, n) = pair
  do IO<R.Reader & Item>:
    body : R.Reader & H.Bytes <- R.take(r, n)
    return named_body(body, name)

def read_size(named: R.Reader & String, expected: String) -> IO(R.Reader & Item):
  (r, +name) = named
  do IO<R.Reader & Item>:
    ok : Unit <- Header.require(String.eq(name, expected), "NO: plan-item")
    size : R.Reader & U32 <- R.count(r)
    read_body(size, name)

def item(r: R.Reader, expected: String) -> IO(R.Reader & Item):
  do IO<R.Reader & Item>:
    named : R.Reader & String <- R.text(r)
    read_size(named, expected)

def version(pair: R.Reader & Item) -> IO(R.Reader):
  (r, entry) = pair
  Item{_, bytes} = entry
  do IO<R.Reader>:
    ok : Unit <- Header.require(version_ok(bytes), "NO: plan-version")
    return r

def settings(xs: H.Bytes, expected: U32) -> IO(Settings):
  match xs:
    case [2,1,salt,nonce,position,samples,saved,count]:
      do IO<Settings>:
        ok : Unit <- Header.require(U32.is_eq(count, expected), "NO: plan-round-count")
        return Settings{salt, nonce, position, samples, saved}
    case _: IO.die(Settings, 1, "NO: plan-settings")

def make_round(xs: H.Bytes, name: String) -> IO(Round):
  match xs:
    case [n,w,m,roots,answers,e,nz,pos,depth,trits,rows]:
      IO.pure(Round, Round{name,n,w,m,roots,answers,e,nz,pos,depth,trits,rows})
    case _: IO.die(Round, 1, "NO: plan-round")

def push_round(pair: R.Reader & H.Bytes, name: String, acc: List<&2, Round>) -> IO(R.Reader & List<&2, Round>):
  (r, xs) = pair
  do IO<R.Reader & List<&2, Round>>:
    round : Round <- make_round(xs, name)
    return (r, round <> acc)

def read_fields(pair: R.Reader & String, acc: List<&2, Round>) -> IO(R.Reader & List<&2, Round>):
  (r, name) = pair
  do IO<R.Reader & List<&2, Round>>:
    fields : R.Reader & H.Bytes <- R.numbers(r, 11)
    push_round(fields, name, acc)

def read_rounds(n: Nat, state: R.Reader & List<&2, Round>) -> IO(R.Reader & List<&2, Round>):
  match n state:
    case 0n Tuple{r, acc}: IO.pure(R.Reader & List<&2, Round>, (r, List.reverse(&2, Round, acc)))
    case 1n+left Tuple{r, acc}:
      do IO<R.Reader & List<&2, Round>>:
        name : R.Reader & String <- R.text(r)
        next : R.Reader & List<&2, Round> <- read_fields(name, acc)
        read_rounds(left, next)

# R4.9 and sections 12-14. Item ordering is part of the canonical chain parameters.
def item_names(chain: P.Chain) -> List<String>:
  match chain:
    case P.KeyOnce{}: ["index-mask message","ranges","binding tree","codes","the test on the table"]
    case P.KeyShared{}: ["codes","the test on the table"]
    case P.KeySecond{}: []
    case P.Entry{}: ["codes","the link"]
    case P.RequestFirst{}: ["codes","the test on the table","request's shape","layout","links' identifiers","pending rows","binding tree"]
    case P.RequestShared{}: ["codes","the test on the table"]
    case P.RequestSecond{}: []

def push_item(pair: R.Reader & Item, acc: List<&2, Item>) -> R.Reader & List<&2, Item>:
  (r, entry) = pair
  (r, entry <> acc)

def read_items(names: List<String>, state: R.Reader & List<&2, Item>) -> IO(R.Reader & List<&2, Item>):
  match names state:
    case [] Tuple{r, acc}: IO.pure(R.Reader & List<&2, Item>, (r, List.reverse(&2, Item, acc)))
    case name <> tail Tuple{r, acc}:
      do IO<R.Reader & List<&2, Item>>:
        entry : R.Reader & Item <- item(r, name)
        read_items(tail, push_item(entry, acc))

def complete(pair: R.Reader & List<&2, Item>, expected: H.Bytes, settings: Settings, rounds: List<&2, Round>) -> IO(Plan):
  (r, items) = pair
  do IO<Plan>:
    digest : H.Bytes <- R.finish(r, expected)
    return Plan{digest, settings, rounds, items}

def configured(pair: R.Reader & Item, config: H.Bytes, chain: P.Chain, digest: H.Bytes,
  settings: Settings, rounds: List<&2, Round>) -> IO(Plan):
  (r, entry) = pair
  Item{_, bytes} = entry
  do IO<Plan>:
    ok : Unit <- Header.require(R.equal(bytes, config), "NO: plan-configuration")
    rest : R.Reader & List<&2, Item> <- read_items(item_names(chain), (r, []))
    complete(rest, digest, settings, rounds)

def after_rounds(pair: R.Reader & List<&2, Round>, config: H.Bytes, chain: P.Chain,
  digest: H.Bytes, settings: Settings) -> IO(Plan):
  (r, rounds) = pair
  do IO<Plan>:
    entry : R.Reader & Item <- item(r, "configuration")
    configured(entry, config, chain, digest, settings, rounds)

def parse_head(pair: R.Reader & H.Bytes, config: H.Bytes, chain: P.Chain, +count: U32, digest: H.Bytes) -> IO(Plan):
  (r, head) = pair
  do IO<Plan>:
    setup : Settings <- settings(head, count)
    rows : R.Reader & List<&2, Round> <- read_rounds(U32.to_nat(count), (r, []))
    after_rounds(rows, config, chain, digest, setup)

def at_path(path: String, config: H.Bytes, chain: P.Chain, pin: P.Pin) -> IO(Plan):
  P.Pin{size, count, digest} = pin
  do IO<Plan>:
    r : R.Reader <- R.open(path, size)
    tag : R.Reader & Item <- item(r, "the format's version")
    checked : R.Reader <- version(tag)
    head : R.Reader & H.Bytes <- R.numbers(checked, 8)
    parse_head(head, config, chain, count, digest)

def selected(profile: Maybe<&2, P.Profile>, config: H.Bytes, +chain: P.Chain, dir: String) -> IO(Plan):
  match profile:
    case None{}: IO.die(Plan, 1, "NO: unsupported-configuration")
    case Some{+p}:
      at_path(dir ++ "/" ++ P.folder(p) ++ "/" ++ P.stem(chain) ++ ".parameters",
        config, chain, Catalog.pin(p, chain))

def load(+config: H.Bytes, chain: P.Chain, dir: String) -> IO(Plan):
  selected(Catalog.select(H.u32s(config)), config, chain, dir)
