import Base
import ./header.bend as Header
import ./policy.bend as P
import ./pow2.bend as P2

def Words() -> Data:
  List<&2, U32>

type Frame is Data:
  Frame{security: U32, slots: U32, salt: U32, work: List<&2, Words>, groups: List<&2, Words>,
    stages: List<&2, Words>, ranges: U32, b: U32, n: U32, i: U32, m: U32, w: U32}

# Each frame numeral admitted by the verifier fits U32. Canonical decimal is
# the same spelling for a 15-digit frame input as for a model word.
def numbers(tokens: P.Lines) -> IO(Words):
  match tokens:
    case []: IO.pure(Words, [])
    case s <> tail:
      do IO<Words>:
        w : U32 <- P.number(s)
        ws : Words <- numbers(tail)
        return w <> ws

def values(+line: String, name: String) -> IO(Words):
  +prefix = name ++ " "
  do IO<Words>:
    ok : Unit <- Header.require(String.starts_with(line, prefix), "NO: parameter-line-order")
    numbers(String.split(String.drop(line, String.length(prefix)), ' '))

def single(ws: Words) -> IO(U32):
  match ws:
    case [x]: IO.pure(U32, x)
    case _: IO.die(U32, 1, "NO: parameter-line-values")

def scalar(line: String, name: String) -> IO(U32):
  do IO<U32>:
    xs : Words <- values(line,name)
    single(xs)

def within(+x: U32, low: U32, high: U32) -> Bool:
  U32.is_ge(x,low) && U32.is_le(x,high)

def work_ok(xs: Words, +bits: U32) -> Bool:
  match xs:
    case [+a,+b,+c]: U32.is_lt(a,bits) && U32.is_lt(b,bits) && U32.is_lt(c,bits) &&
      U32.is_le(a,32) && U32.is_le(b,32) && U32.is_le(c,32)
    case _: False{}

def group_ok(xs: Words) -> Bool:
  match xs:
    case [1,+n,l,+nz,lz]: U32.is_le(n,32) && U32.is_lt(l,n) && U32.is_le(nz,n) && U32.is_lt(lz,nz)
    case _: False{}

def stages_ok(xs: Words) -> Bool:
  match xs:
    case [0,0,+n,nz]: U32.is_le(n,32) && U32.is_le(nz,n)
    case +k <> h <> +n <> nz <> tail:
      within(k,1,8) && U32.is_le(h,k) && U32.is_le(n,32) && U32.is_le(nz,n) && stages_ok(tail)
    case _: False{}

def main_code(xs: Words) -> U32 & U32:
  match xs:
    case [_,n,l,_,_]: (n,l)
    case _: (0,0)

def mask_code(xs: Words) -> U32 & U32:
  match xs:
    case [_,_,_,n,l]: (n,l)
    case _: (0,0)

def pair_eq(x: U32 & U32, y: U32 & U32) -> Bool:
  (a,b) = x
  (c,d) = y
  U32.is_eq(a,c) && U32.is_eq(b,d)

def compatible(xs: List<&2, Words>) -> Bool:
  match xs:
    case [_,f,+o,own,f1,+o1,own1,_]:
      pair_eq(main_code(o),main_code(own)) && pair_eq(main_code(o1),main_code(own1)) &&
        pair_eq(mask_code(f),mask_code(o)) && pair_eq(mask_code(f1),mask_code(o1))
    case _: False{}

type Groups is Data:
  Groups{groups: List<&2,Words>, stages: List<&2,Words>, rest: P.Lines}

def prepend_code(code: Words, stage: Words, x: Groups) -> Groups:
  Groups{gs,ss,tail} = x
  Groups{code <> gs, stage <> ss, tail}

def pair_lines(names: P.Lines, lines: P.Lines) -> IO(Groups):
  match names lines:
    case Nil{} tail: IO.pure(Groups, Groups{[],[],tail})
    case Con{+name,ns} g <> s <> tail:
      do IO<Groups>:
        +code : Words <- values(g, "group " ++ name)
        +st : Words <- values(s, "stages " ++ name)
        ok : Unit <- Header.require(group_ok(code), "NO: parameter-group-shape")
        ok : Unit <- Header.require(Nat.is_le(List.length(&2,U32,st),32n) && stages_ok(st), "NO: parameter-stages-shape")
        rest : Groups <- pair_lines(ns, tail)
        return prepend_code(code, st, rest)
    case _ _: IO.die(Groups, 1, "NO: parameter-line-missing")


def make_table(ws: Words, sec: U32, slots: U32, salt: U32, work: List<&2, Words>,
    groups: List<&2, Words>, stages: List<&2, Words>, ranges: U32) -> IO(Frame):
  match ws:
    case [+b,+n,+i,+m,0,+w]:
      do IO<Frame>:
        ok : Unit <- Header.require(U32.is_le(b,20) && U32.is_le(n,32) && U32.is_ne(i,0) &&
          Nat.is_lt(Nat.add(U32.to_nat(i),U32.to_nat(m)),P2.pow2(U32.to_nat(U32.min(n,32)))) &&
          U32.is_le(b,w) && U32.is_le(w,40), "NO: parameter-table-shape")
        ok : Unit <- Header.require(within(w,1,20), "NO: w-shape-lk")
        return Frame{sec,slots,salt,work,groups,stages,ranges,b,n,i,m,w}
    case _: IO.die(Frame, 1, "NO: parameter-table-shape")

def end_frame(grouped: Groups, sec: U32, slots: U32, salt: U32, work: List<&2, Words>) -> IO(Frame):
  match grouped:
    case Groups{+gs,ss,ranges <> table <> _}:
      do IO<Frame>:
        +r : U32 <- scalar(ranges,"ranges-part")
        ws : Words <- values(table,"table")
        ok : Unit <- Header.require(within(r,1,40) && compatible(gs), "NO: parameter-group-shape")
        make_table(ws,sec,slots,salt,work,gs,ss,r)
    case _: IO.die(Frame, 1, "NO: parameter-line-missing")

def parse(lines: P.Lines) -> IO(Frame):
  match lines:
    case version <> sl <> reading <> cost <> slots <> answers <> record <> a <> b <> c <> d <> e <> salt <> listed <> tail:
      do IO<Frame>:
        ok : Unit <- Header.require(String.eq(version,"version H821") && String.eq(reading,"reading 1") &&
          String.eq(cost,"rowcost 1") && String.eq(answers,"answers 1") && String.eq(record,"record 1") &&
          String.eq(listed,"listed 0"), "NO: parameter-range")
        +sec : U32 <- scalar(sl,"sec")
        +slots_n : U32 <- scalar(slots,"slots")
        +y : U32 <- scalar(salt,"salt")
        ok : Unit <- Header.require(within(sec,1,256) && within(slots_n,1,256) &&
          U32.is_zero(U32.and(slots_n,U32.sub(slots_n,1))) && within(y,40,64) &&
          U32.is_zero(U32.and(y,7)), "NO: parameter-range")
        +wa : Words <- values(a, "work field")
        +wb : Words <- values(b, "work sample")
        +wc : Words <- values(c, "work closeness")
        +wd : Words <- values(d, "work positions")
        +we : Words <- values(e, "work smallness")
        ok : Unit <- Header.require(work_ok(wa,sec) && work_ok(wb,sec) && work_ok(wc,sec) &&
          work_ok(wd,sec) && work_ok(we,sec), "NO: policy-work-most")
        gs : Groups <- pair_lines(["link","folded","omega","own","once-folded","once-omega","once-own","once-ranges"],tail)
        end_frame(gs,sec,slots_n,y,[wa,wb,wc,wd,we])
    case _: IO.die(Frame, 1, "NO: parameter-line-order")
