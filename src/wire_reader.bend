import Base
import ./hash_bytes.bend as H
import ./header.bend as Header
import ./commitment.bend as Commitment

# Hash each refill exactly once. Only the bytes returned from this handle
# can become a plan. The trusted catalog bounds every read before decoding.
def Hash() -> Data:
  Maybe<&2, H.Context>

type Reader is Type:
  Reader{file: File, left: U32, available: U32, bytes: H.Bytes, hash: Hash}

def open(path: String, size: U32) -> IO(Reader):
  do IO<Reader>:
    f : File <- IO.try(File, File.open(path, "r"))
    return Reader{f, size, 0, [], Some{H.start(169, 1)}}

def limit_file(pair: File & U32, cap: U32) -> IO(Reader):
  (f, +size) = pair
  do IO<Reader>:
    ok : Unit <- Header.require(U32.is_le(size, cap), "NO: file-too-long")
    return Reader{f, size, 0, [], None{}}

def proof_file(f: File, cap: U32) -> IO(Reader):
  do IO<Reader>:
    result : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
    sized : File & U32 <- Commitment.unpack(U32, result)
    limit_file(sized, cap)

def open_proof(path: String, cap: U32) -> IO(Reader):
  do IO<Reader>:
    f : File <- IO.try(File, File.open(path, "r"))
    proof_file(f,cap)

def absorb(hash: Hash, bytes: H.Bytes) -> Hash:
  match hash:
    case None{}: None{}
    case Some{ctx}: Some{H.update(ctx, bytes)}

def slice(f: File, left: U32, available: U32, +buf: H.Bytes, hash: Hash,
  +n: U32) -> Reader & H.Bytes:
  (Reader{f, left, U32.sub(available, n), List.drop(&2, U32, buf, U32.to_nat(n)), hash},
   H.take(buf,U32.to_nat(n)))

def pulled(pair: File & H.Bytes, left: U32, available: U32, buf: H.Bytes, hash: Hash,
  +size: U32, n: U32) -> IO(Reader & H.Bytes):
  (next, +xs) = pair
  do IO<Reader & H.Bytes>:
    check : Unit <- Header.require(Nat.is_eq(H.length(xs), U32.to_nat(size)), "NO: truncated-file")
    return slice(next, U32.sub(left, size), U32.add(available, size),
      H.cat([buf, xs]), absorb(hash, xs), n)

def pull(f: File, +left: U32, +available: U32, buf: H.Bytes, hash: Hash,
  +n: U32) -> IO(Reader & H.Bytes):
  +more = U32.sub(n, available)
  +size = U32.min(left, U32.max(more, 8192))
  do IO<Reader & H.Bytes>:
    check : Unit <- Header.require(U32.is_le(more, left), "NO: plan-length")
    read : File & Result<&1, &1, U32 & String, H.Bytes> <- File.read_bytes(f, size)
    pair : File & H.Bytes <- Commitment.unpack(H.Bytes, read)
    pulled(pair, left, available, buf, hash, size, n)

def take_from(enough: Bool, f: File, left: U32, available: U32, buf: H.Bytes, hash: Hash, n: U32) -> IO(Reader & H.Bytes):
  match enough:
    case True{}: IO.pure(Reader & H.Bytes, slice(f, left, available, buf, hash, n))
    case False{}: pull(f, left, available, buf, hash, n)

def take(r: Reader, +n: U32) -> IO(Reader & H.Bytes):
  Reader{f, left, +available, buf, hash} = r
  take_from(U32.is_le(n, available), f, left, available, buf, hash, n)

def ascii(bytes: H.Bytes) -> String:
  match bytes:
    case []: ""
    case h <> t: SCon{Chr{h}, ascii(t)}

# All lengths in the supported profiles fit in 32 bits. Check the high limb.
def words(xs: List<&2, U32>) -> IO(List<&2, U32>):
  match xs:
    case []: IO.pure(List<&2, U32>, [])
    case lo <> 0 <> tail:
      do IO<List<&2, U32>>:
        rest : List<&2, U32> <- words(tail)
        return lo <> rest
    case _: IO.die(List<&2, U32>, 1, "NO: plan-word")

def parsed_numbers(pair: Reader & H.Bytes) -> IO(Reader & H.Bytes):
  (r, bytes) = pair
  do IO<Reader & H.Bytes>:
    xs : H.Bytes <- words(H.u32s(bytes))
    return (r, xs)

def numbers(r: Reader, n: U32) -> IO(Reader & H.Bytes):
  do IO<Reader & H.Bytes>:
    pair : Reader & H.Bytes <- take(r, U32.shln(n, 3n))
    parsed_numbers(pair)

def count_words(r: Reader, xs: H.Bytes) -> IO(Reader & U32):
  match xs:
    case [n, 0]: IO.pure(Reader & U32, (r, n))
    case _: IO.die(Reader & U32, 1, "NO: plan-length")

def parsed_count(pair: Reader & H.Bytes) -> IO(Reader & U32):
  (r, raw) = pair
  count_words(r, H.u32s(raw))

def count(r: Reader) -> IO(Reader & U32):
  do IO<Reader & U32>:
    pair : Reader & H.Bytes <- take(r, 8)
    parsed_count(pair)

def make_text(pair: Reader & H.Bytes) -> Reader & String:
  (r, bytes) = pair
  (r, ascii(bytes))

def read_text(sized: Reader & U32) -> IO(Reader & String):
  (r, +n) = sized
  do IO<Reader & String>:
    ok : Unit <- Header.require(U32.is_le(n, 64), "NO: plan-name")
    pair : Reader & H.Bytes <- take(r, n)
    return make_text(pair)

def text(r: Reader) -> IO(Reader & String):
  do IO<Reader & String>:
    sized : Reader & U32 <- count(r)
    read_text(sized)

def equal(xs: H.Bytes, ys: H.Bytes) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case Con{x, xt} Con{y, yt}: U32.is_eq(x, y) && equal(xt, yt)
    case _ _: False{}

def exact_end(f: File, left: U32, buffered: U32) -> IO(Unit):
  do IO<Unit>:
    ok : Unit <- Header.require(U32.is_zero(U32.or(left, buffered)), "NO: trailing-data")
    next : File & Result<&1, &1, U32 & String, H.Bytes> <- File.read_bytes(f, 1)
    extra : H.Bytes <- Header.closed(H.Bytes, next)
    Header.require(List.is_empty(&2, U32, extra), "NO: trailing-data")

def end_proof(r: Reader) -> IO(Unit):
  Reader{f,left,buf,_,_} = r
  exact_end(f,left,buf)

def close(r: Reader) -> IO(Unit):
  Reader{f,_,_,_,_} = r
  File.close(f)

def check_hash(hash: Hash, expected: H.Bytes) -> IO(H.Bytes):
  match hash:
    case None{}: IO.die(H.Bytes, 1, "NO: plan-digest")
    case Some{ctx}:
      +digest = H.finish(ctx, 32)
      do IO<H.Bytes>:
        ok : Unit <- Header.require(equal(H.u32s(digest), expected), "NO: plan-digest")
        return digest

def finish(r: Reader, expected: H.Bytes) -> IO(H.Bytes):
  Reader{f, left, buffered, _, hash} = r
  do IO<H.Bytes>:
    ok : Unit <- exact_end(f, left, buffered)
    check_hash(hash, expected)
