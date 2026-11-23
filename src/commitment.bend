import Base
import ./header.bend as Header
import ./hash_bytes.bend as H
import ./record_seeds.bend as Seeds

def unpack(-A: Type, pair: File & Result<&1, &1, U32 & String, A>) -> IO(File & A):
  (f, res) = pair
  do IO<File & A>:
    value : A <- IO.pass(A, res)
    return (f, value)

def read_chunk(pair: File & H.Bytes, ctx: H.Context, wanted: Nat) -> IO(File & H.Context):
  (f, +xs) = pair
  do IO<File & H.Context>:
    checked : Unit <- Header.require(Nat.is_eq(List.length(&2, U32, xs), wanted), "short configuration file")
    return (f, H.update(ctx, xs))

def next_chunk(pair: File & H.Context, +wanted: Nat) -> IO(File & H.Context):
  (f, ctx) = pair
  do IO<File & H.Context>:
    r : File & Result<&1, &1, U32 & String, H.Bytes> <- File.read_bytes(f, U32.from_nat(wanted))
    xs : File & H.Bytes <- unpack(H.Bytes, r)
    read_chunk(xs, ctx, wanted)

def end_file(pair: File & H.Context) -> IO(H.Context):
  (f, ctx) = pair
  do IO<H.Context>:
    done : Unit <- File.close(f)
    return ctx

def chunks(count: Nat, pair: File & H.Context, last: Nat) -> IO(H.Context):
  match count:
    case 0n:
      do IO<H.Context>:
        end : File & H.Context <- next_chunk(pair, last)
        end_file(end)
    case 1n+p:
      do IO<H.Context>:
        next : File & H.Context <- next_chunk(pair, 8192n)
        chunks(p, next, last)

def sized_file(pair: File & U32, +ctx: H.Context) -> IO(H.Context):
  (f, +length) = pair
  +n = U32.to_nat(length)
  do IO<H.Context>:
    # R2.3 bound includes all file lengths and data; H.size already includes the label.
    checked : Unit <- Header.require(
      Nat.is_le(Nat.add(H.size(ctx), Nat.add(8n, n)), 4294967168n), "configuration too long")
    chunks(Nat.div(n, 8192n), (f, H.update(ctx, H.word(length))), Nat.mod(n, 8192n))

def add_file(path: String, ctx: H.Context) -> IO(H.Context):
  do IO<H.Context>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
    sized : File & U32 <- unpack(U32, r)
    sized_file(sized, ctx)

def config_start() -> H.Context:
  label = H.cat([H.word(169), H.word(2), H.word(3)])
  H.Context{H.initial(H.u32s(H.zero(32n)), 32), label, 0}

def configuration(+config: String) -> IO(H.Bytes):
  do IO<H.Bytes>:
    pol : H.Context <- add_file(config ++ "/policy.txt", config_start())
    layout : H.Context <- add_file(config ++ "/layout.txt", pol)
    scales : H.Context <- add_file(config ++ "/KL.bin", layout)
    return H.finish(scales, 32)

type Shape is Data:
  Shape{rows_log: U32, code_log: U32, message: U32, random: U32, salt: U32}

def table(line: Maybe<&2, String>) -> IO(List<&2, String>):
  match line:
    case Some{text}: IO.pure(List<&2, String>, String.split(text, ' '))
    case None{}: IO.die(List<&2, String>, 1, "policy-table")

def shape(values: List<&2, String>, salt: U32) -> IO(Shape):
  match values:
    case [_, b, n, i, m, e, w]:
      do IO<Shape>:
        +rows : U32 <- Header.decimal(Nat.read(b))
        +bits : U32 <- Header.decimal(Nat.read(n))
        +message : U32 <- Header.decimal(Nat.read(i))
        random : U32 <- Header.decimal(Nat.read(m))
        checked : Unit <- Header.require(
          U32.is_le(rows, 20) && U32.is_le(bits, 32) && U32.is_ne(message, 0), "policy-table")
        return Shape{rows, bits, message, random, salt}
    case _: IO.die(Shape, 1, "policy-table")

def parse_shape(+lines: List<&2, String>) -> IO(Shape):
  do IO<Shape>:
    salt : U32 <- Header.field(List.find(String, line => String.starts_with(line, "salt "), lines), 5n)
    answers : U32 <- Header.field(List.find(String, line => String.starts_with(line, "answers "), lines), 8n)
    check : Unit <- Header.require(U32.is_eq(answers, 1), "policy-answers")
    values : List<&2, String> <- table(List.find(String, line => String.starts_with(line, "table "), lines))
    shape(values, salt)

def key_shape(config: String) -> IO(Shape):
  do IO<Shape>:
    f : File <- IO.try(File, File.open(config ++ "/policy.txt", "r"))
    r : File & Result<&1, &1, U32 & String, String> <- File.read(f, 32768)
    text : String <- Header.closed(String, r)
    parse_shape(String.lines(text))

def canonical(xs: List<&2, U32>) -> Bool:
  match xs:
    case []: True{}
    case 0 <> 4294967295 <> tail: canonical(tail)
    case lo <> 4294967295 <> tail: False{}
    case lo <> hi <> tail: canonical(tail)
    case _: False{}

def variables(+message: U32) -> Nat:
  match message:
    case 1: 0n
    case _: Nat.add(U32.log2(U32.sub(message, 1)), 1n)

def published(shape: Shape, +key: H.Bytes, +config: H.Bytes) -> IO(String):
  Shape{+b,n,+i,m,salt} = shape
  +rows = U32.shln(1, U32.to_nat(b))
  +record = List.drop(&2, U32, key, 40n)
  root = List.take(&2, U32, List.drop(&2, U32, key, 8n), 32n)
  +name = H.cat([root, config, H.word(n), H.word(i), H.word(m), H.word(b), H.word(1), H.word(salt)])
  +coordinates = variables(i)
  do IO<String>:
    check : Unit <- Header.require(Header.key_head(List.take(&2, U32, key, 8n)), "cp-key-head")
    check : Unit <- Header.require(
      Nat.is_eq(List.length(&2, U32, record), Nat.mul(24n, U32.to_nat(rows))) &&
      canonical(H.u32s(record)), "invalid anchor record")
    return H.hex(H.plain(179, 0, H.cat([config, H.word(112), name,
      H.word(U32.from_nat(Nat.add(coordinates, 1n))), Seeds.sample(name, coordinates),
      H.word(rows), record, H.word(0)])))

def prefix_length(shape: Shape) -> U32:
  Shape{b,_,_,_,_} = shape
  U32.add(40, U32.mul(24, U32.shln(1, U32.to_nat(b))))

def compute(+config: String, ivk: String) -> IO(String):
  do IO<String>:
    +shape : Shape <- key_shape(config)
    digest : H.Bytes <- configuration(config)
    key : H.Bytes <- Header.bytes(ivk ++ "/key.bin", prefix_length(shape))
    published(shape, key, digest)
