import Base
import ./header.bend as Header

def Lines() -> Data:
  List<&2, String>

# Strict decimal syntax from FORMAT §§8.6 and 14.3.
def spelling(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && Nat.is_le(String.length(s), 10n) &&
    (Bool.not(String.starts_with(s, "0")) || String.eq(s, "0")) &&
    List.all(&2, Char, Char.is_digit, String.to_list(s))

def number(+s: String) -> IO(U32):
  do IO<U32>:
    ok : Unit <- Header.require(spelling(s), "NO: policy-line-form")
    Header.decimal(Nat.read(s))

def scan(lines: Lines, +prefix: String) -> IO(U32):
  match lines:
    case []: IO.die(U32, 1, "NO: policy-line-form")
    case +line <> tail:
      action = Bool.pick(Unit -> IO(U32), String.starts_with(line, prefix),
        _ => number(String.drop(line, String.length(prefix))), _ => scan(tail, prefix))
      action(Unit{})

def field(lines: Lines, name: String) -> IO(U32):
  scan(lines, name ++ " ")

type Claim is Data:
  Claim{limit: U32, theta: U32, cap: U32, s: U32, sh: U32, sT: U32, family: U32}

def parse(+lines: Lines) -> IO(Claim):
  do IO<Claim>:
    c : U32 <- field(lines, "C")
    th : U32 <- field(lines, "theta")
    cap : U32 <- field(lines, "cap")
    s : U32 <- field(lines, "s")
    sh : U32 <- field(lines, "sh")
    st : U32 <- field(lines, "sT")
    fam : U32 <- field(lines, "F")
    return Claim{c, th, cap, s, sh, st, fam}

def valid_parts(parts: Lines) -> Bool:
  match parts:
    case [+kind, c, th, cap, s, sh]:
      (String.eq(kind, "exact-match") || String.eq(kind, "clipped-gap")) &&
        List.all(&2, String, x => spelling(x), [c,th,cap,s,sh])
    case _: False{}

def option_valid(text: String) -> Bool:
  valid_parts(String.split(text, ','))

def kind_name(exact: Bool) -> String:
  match exact:
    case True{}: "exact-match"
    case False{}: "clipped-gap"

def matched(named: Maybe<&2, String>, name: String, exact: Bool, +count: U32, substantive: Bool) -> Bool:
  match named:
    case Some{text}: String.eq(text, name) && substantive
    case None{}: exact || U32.is_zero(count)

# R15.2 and §13.7 condition 11. count excludes the separately checked next token.
def held(claim: Claim, named: Maybe<&2, String>, length: U32, +count: U32) -> Bool:
  Claim{+c,+th,+cap,+s,+sh,st,fam} = claim
  +unit = U32.shln(1, U32.to_nat(U32.min(sh,8)))
  +exact = U32.is_eq(c, unit) && U32.is_eq(th, unit) && U32.is_zero(cap)
  kind = kind_name(exact)
  name = String.join([kind, U32.show(c), U32.show(th), U32.show(cap), U32.show(s), U32.show(sh)], ",")
  substantive = U32.is_ge(th, unit) && (U32.is_ne(th, c) || U32.is_zero(count) || U32.is_lt(cap, count))
  (U32.is_eq(sh, 7) || U32.is_eq(sh, 8)) && U32.is_eq(st, U32.sub(sh, 4)) &&
    U32.is_le(th, c) && U32.is_le(cap, length) && U32.is_lt(cap, 65536) &&
    U32.is_eq(fam, 24) && U32.is_le(s, 63) && matched(named, name, exact, count, substantive)

def ascii(bytes: List<&2,U32>) -> String:
  match bytes:
    case []: ""
    case x <> tail: SCon{Char.from_u32(x), ascii(tail)}

def text_byte(+x: U32) -> Bool:
  U32.is_eq(x,10) || (U32.is_ge(x,32) && U32.is_le(x,126))

def document(path: String) -> IO(Lines):
  do IO<Lines>:
    # §8.1 allows 32 frame lines with at most 32 15-digit values each.
    # §8.6 caps scalar words at ten digits and each of the 8+12+6 call
    # lines at 1,023 bytes. Even these simultaneous maxima fit in 64 KiB.
    +raw : List<&2,U32> <- Header.bytes(path, 65537)
    ok : Unit <- Header.require(Nat.is_le(List.length(&2,U32,raw),65536n), "NO: policy-length")
    ok : Unit <- Header.require(List.all(&2,U32,x => text_byte(x),raw), "NO: policy-line-form")
    +text : String = ascii(raw)
    ok : Unit <- Header.require(String.ends_with(text,"\n"), "NO: parameter-line-missing")
    return String.lines(text)

def count_covered(xs: List<&2,U32>, +length: U32) -> IO(U32):
  match xs:
    case [a,b,c,d,f,g,h,i]:
      +first = Header.le32(a,b,c,d)
      +end = Header.le32(f,g,h,i)
      do IO<U32>:
        valid : Unit <- Header.require(U32.is_lt(first,end) && U32.is_le(end,length), "NO: statement-range")
        # first <= T-1. End is exclusive and the next-token position is T-1.
        return U32.sub(U32.min(end, U32.sub(length, 1)), first)
    case _: IO.die(U32, 1, "NO: statement-range")

def first(pair: U32 & U32) -> U32:
  (length, _) = pair
  length
