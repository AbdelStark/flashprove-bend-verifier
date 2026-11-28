import Base
import ./header.bend as Header
import ./hash_bytes.bend as H
import ./record_seeds.bend as Seeds
import ./pow2.bend as P2

def unpack(-A: Type, pair: File & Result<&1, &1, U32 & String, A>) -> IO(File & A):
  (f, res) = pair
  do IO<File & A>:
    value : A <- IO.pass(A, res)
    return (f, value)

def canonical(xs: List<&2, U32>) -> Bool:
  match xs:
    case []: True{}
    case 0 <> 4294967295 <> tail: canonical(tail)
    case lo <> 4294967295 <> tail: False{}
    case lo <> hi <> tail: canonical(tail)
    case _: False{}

def record_chunk(record: Bool, xs: H.Bytes) -> Bool:
  match record:
    case True{}: canonical(H.u32s(xs))
    case False{}: True{}

def read_chunk(pair: File & H.Bytes, ctx: H.Context, wanted: Nat, record: Bool) -> IO(File & H.Context):
  (f, +xs) = pair
  do IO<File & H.Context>:
    checked : Unit <- Header.require(Nat.is_eq(List.length(&2, U32, xs), wanted), "NO: short file")
    checked : Unit <- Header.require(record_chunk(record, xs), "NO: key-refused")
    return (f, H.update(ctx, xs))

def next_chunk(pair: File & H.Context, +wanted: Nat, record: Bool) -> IO(File & H.Context):
  (f, ctx) = pair
  do IO<File & H.Context>:
    r : File & Result<&1, &1, U32 & String, H.Bytes> <- File.read_bytes(f, U32.from_nat(wanted))
    xs : File & H.Bytes <- unpack(H.Bytes, r)
    read_chunk(xs, ctx, wanted, record)

def end_file(pair: File & H.Context) -> IO(H.Context):
  (f, ctx) = pair
  do IO<H.Context>:
    done : Unit <- File.close(f)
    return ctx

def chunks(count: Nat, pair: File & H.Context, last: Nat, +record: Bool) -> IO(H.Context):
  match count:
    case 0n:
      do IO<H.Context>:
        end : File & H.Context <- next_chunk(pair, last, record)
        end_file(end)
    case 1n+p:
      do IO<H.Context>:
        next : File & H.Context <- next_chunk(pair, 8192n, record)
        chunks(p, next, last, record)

def sized_file(pair: File & U32, +ctx: H.Context) -> IO(H.Context):
  (f, +length) = pair
  +n = U32.to_nat(length)
  do IO<H.Context>:
    # R2.3 bound includes all file lengths and data; H.size already includes the label.
    checked : Unit <- Header.require(
      Nat.is_le(Nat.add(H.size(ctx), Nat.add(8n, n)), 4294967168n), "configuration too long")
    chunks(Nat.div(n, 8192n), (f, H.update(ctx, H.word(length))), Nat.mod(n, 8192n), False{})

def add_file(path: String, ctx: H.Context) -> IO(H.Context):
  do IO<H.Context>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
    sized : File & U32 <- unpack(U32, r)
    sized_file(sized, ctx)

def config_start() -> H.Context:
  H.update(H.start(169, 2), H.word(3))

def configuration(+config: String) -> IO(H.Bytes):
  do IO<H.Bytes>:
    pol : H.Context <- add_file(config ++ "/policy.txt", config_start())
    layout : H.Context <- add_file(config ++ "/layout.txt", pol)
    scales : H.Context <- add_file(config ++ "/KL.bin", layout)
    return H.finish(scales, 32)

type Shape is Data:
  Shape{rows_log: U32, code_log: U32, message: U32, random: U32, salt: U32}

def variables(+message: U32) -> Nat:
  match message:
    case 1: 0n
    case _: Nat.add(U32.log2(U32.sub(message, 1)), 1n)

def record_start(shape: Shape, root: H.Bytes, +config: H.Bytes) -> H.Context:
  Shape{+b,n,+i,m,salt} = shape
  rows = U32.shln(1,U32.to_nat(b))
  +name = H.cat([root,config,H.word(n),H.word(i),H.word(m),H.word(b),H.word(1),H.word(salt)])
  +coordinates = variables(i)
  H.update(H.start(179,0),H.cat([config,H.word(112),name,H.word(U32.from_nat(1n+coordinates)),
    Seeds.sample(name,coordinates),H.word(rows)]))

def record_finish(ctx: H.Context) -> String:
  H.hex(H.finish(H.update(ctx,H.word(0)),32))

def record_length(shape: Shape) -> Nat:
  Shape{b,_,_,_,_} = shape
  Nat.mul(24n,P2.pow2(U32.to_nat(b)))

# R4.11 uses precisely the root and record consumed by the validated key.
def from_record(+shape: Shape, +root: H.Bytes, +record: H.Bytes, config: H.Bytes) -> IO(String):
  do IO<String>:
    ok : Unit <- Header.require(Nat.is_eq(H.length(root),32n) && Nat.is_eq(H.length(record),record_length(shape)) &&
      canonical(H.u32s(record)), "NO: commitment-record")
    return record_finish(H.update(record_start(shape,root,config),record))
