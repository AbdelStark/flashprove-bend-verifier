import Base
import ./header.bend as Header
import ./hash_bytes.bend as H
import ./policy.bend as P
import ./policy_hash.bend as K

type Table is Data:
  Table{words: H.Bytes, digest: H.Bytes}
type Tables is Data:
  Tables{silu: Table, sigmoid: Table, rotary: Table, softmax: Table}

def expected(+n: Nat, +prefix: String, +lines: P.Lines) -> IO(H.Bytes):
  match n:
    case 0n: IO.pure(H.Bytes, [])
    case 1n+p:
      do IO<H.Bytes>:
        rest : H.Bytes <- expected(p, prefix, lines)
        word : U32 <- P.field(lines, prefix ++ Nat.show(p))
        return List.append(&2, U32, rest, [word])

def same(left: H.Bytes, right: H.Bytes) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{x,xs} Con{y,ys}: U32.is_eq(x,y) && same(xs,ys)
    case _ _: False{}

def read(path: String, +length: U32, digest: H.Bytes, error: String) -> IO(Table):
  do IO<Table>:
    +bytes : H.Bytes <- Header.bytes(path, U32.add(U32.shln(length, 2n), 1))
    ok : Unit <- Header.require(Nat.is_eq(List.length(&2, U32, bytes), Nat.mul(4n, U32.to_nat(length))), "NO: public-table-length")
    +words : H.Bytes = H.u32s(bytes)
    +computed : H.Bytes = K.k(72, words)
    ok : Unit <- Header.require(same(computed, digest), error)
    return Table{words, computed}

def optional(lines: P.Lines, +name: String, fallback: U32) -> IO(U32):
  match lines:
    case []: IO.pure(U32, fallback)
    case +line <> tail:
      +prefix = name ++ " "
      action = Bool.pick(Unit -> IO(U32), String.starts_with(line, prefix),
        _ => P.number(String.drop(line, String.length(prefix))), _ => optional(tail, name, fallback))
      action(Unit{})

# R15.3 admits public tables as data. The same words that pass K(72) are
# returned to the segment verifier. The supported geometries pin their sizes.
def load(+lines: P.Lines, +dir: String) -> IO(Tables):
  do IO<Tables>:
    eg : U32 <- optional(lines, "eg", 8)
    smax : U32 <- optional(lines, "smax", 4095)
    gcl : U32 <- optional(lines, "gcl", 0)
    experts : U32 <- P.field(lines, "NE")
    S : U32 <- P.field(lines, "S")
    rx : U32 <- P.field(lines, "rx")
    +lt : U32 <- P.field(lines, "lt")
    dh : U32 <- P.field(lines, "dh")
    cs : U32 <- P.field(lines, "cs")
    +theta : U32 <- P.field(lines, "theta0_lo")
    hi : U32 <- P.field(lines, "theta0_hi")
    ok : Unit <- Header.require(U32.is_eq(eg, 8) && U32.is_eq(smax, 4095) && U32.is_eq(gcl, 1) &&
      U32.is_ne(experts, 0) && U32.is_eq(S, 12) && U32.is_eq(rx, 8) && U32.is_eq(cs, 12) &&
      U32.is_eq(dh, 128) && U32.is_zero(hi) && ((U32.is_eq(lt, 6) && U32.is_eq(theta, 10000)) ||
      (U32.is_eq(lt, 10) && U32.is_eq(theta, 500000))), "NO: unsupported public table geometry")
    hs : H.Bytes <- expected(8n, "tsilu", lines)
    hg : H.Bytes <- expected(8n, "tsig", lines)
    hr : H.Bytes <- expected(8n, "trope", lines)
    he : H.Bytes <- expected(8n, "texp", lines)
    silu : Table <- read(dir ++ "/silu-8-4095.bin", 65536, hs, "NO: table-digest-silu")
    sig : Table <- read(dir ++ "/sigmoid-1.bin", 65536, hg, "NO: table-digest-sigmoid")
    rot : Table <- read(dir ++ "/rotary-" ++ U32.show(lt) ++ "-128-12-" ++ U32.show(theta) ++ ".bin",
      U32.shln(128, U32.to_nat(lt)), hr, "NO: table-digest-rotary")
    soft : Table <- read(dir ++ "/softmax-12-8.bin", 2307, he, "NO: table-digest-softmax")
    return Tables{silu, sig, rot, soft}
