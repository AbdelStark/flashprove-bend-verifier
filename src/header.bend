import Base

def require(ok: Bool, reason: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, reason)

def closed(-A: Type, pair: File & Result<&1, &1, U32 & String, A>) -> IO(A):
  (f, result) = pair
  do IO<A>:
    done : Unit <- File.close(f)
    IO.pass(A, result)

def bytes(path: String, limit: U32) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, limit)
    closed(List<&2, U32>, pair)

def le32(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

# R13.1 and R14.2. The read limits are exactly the sizes of the headers.
def key_head(xs: List<&2, U32>) -> Bool:
  match xs:
    case [67, 80, 73, 75, 72, 56, 50, 49]: True{}
    case _: False{}

def leaf_head(xs: List<&2, U32>) -> Bool:
  match xs:
    case [67, 80, 69, 78, 72, 56, 50, 49]: True{}
    case _: False{}

def leaf_index(xs: List<&2, U32>) -> IO(U32):
  match xs:
    case [67, 80, 80, 70, 72, 56, 50, 49, a, b, c, d]:
      IO.pure(U32, le32(a, b, c, d))
    case _: IO.die(U32, 1, "NO: cp-proof-head")

def token_word(xs: List<&2, U32>) -> IO(U32):
  match xs:
    case [a,b,c,d]: IO.pure(U32, le32(a,b,c,d))
    case _: IO.die(U32, 1, "NO: statement-range")

type RequestStatus is Data:
  Valid{}
  RangeError{}
  TokenError{}

def verdict(bounds: Bool, tokens: Bool) -> RequestStatus:
  match bounds tokens:
    case True{} True{}: Valid{}
    case True{} False{}: TokenError{}
    case False{} _: RangeError{}

# FORMAT section 12.2. Check bounds before reporting a token error. The last
# two words must also end the file.
def request_status(xs: List<&2, U32>, +seen: U32, +length: U32, +vocab: U32,
  +y: U32, tokens_ok: Bool) -> RequestStatus:
  match xs:
    case [a,b,c,d,f,g,h,i]:
      +start = le32(a,b,c,d)
      +end = le32(f,g,h,i)
      bounds = U32.is_eq(seen, length) && U32.is_lt(start, end) &&
        U32.is_le(end, length) && (U32.is_eq(end, length) || U32.is_zero(y))
      verdict(bounds, tokens_ok && U32.is_lt(y, vocab))
    case a <> b <> c <> d <> tail:
      request_status(tail, U32.add(seen, 1), length, vocab, y,
        tokens_ok && U32.is_lt(le32(a,b,c,d), vocab))
    case _: RangeError{}

def request_result(status: RequestStatus) -> IO(Unit):
  match status:
    case Valid{}: IO.pure(Unit, Unit{})
    case RangeError{}: IO.die(Unit, 1, "NO: statement-range")
    case TokenError{}: IO.die(Unit, 1, "NO: token-range")

def decimal(n: Maybe<&2, Nat>) -> IO(U32):
  match n:
    case Some{+k}:
      do IO<U32>:
        checked : Unit <- require(Nat.is_le(k, 4294967295n), "NO: policy-range")
        IO.pure(U32, U32.from_nat(k))
    case None{}: IO.die(U32, 1, "NO: policy-number")

def field(value: Maybe<&2, String>, offset: Nat) -> IO(U32):
  match value:
    case Some{line}: decimal(Nat.read(String.drop(line, offset)))
    case None{}: IO.die(U32, 1, "NO: policy-field")

def policy_fields(lines: List<&2, String>) -> IO(U32 & U32):
  match lines:
    case first <> +tail:
      do IO<U32 & U32>:
        checked : Unit <- require(String.eq(first, "version H821"), "NO: version-unknown (policy)")
        +lt : U32 <- field(List.find(String, line => String.starts_with(line, "lt "), tail), 3n)
        +vocab : U32 <- field(List.find(String, line => String.starts_with(line, "V "), tail), 2n)
        checked : Unit <- require(U32.is_ge(lt, 4) && U32.is_le(lt, 16), "NO: shape-words")
        checked : Unit <- require(U32.is_ge(vocab, 2) && U32.is_le(vocab, 16777216), "NO: shape-V")
        IO.pure(U32 & U32, (U32.shln(1, U32.to_nat(lt)), vocab))
    case _: IO.die(U32 & U32, 1, "NO: policy-empty")
