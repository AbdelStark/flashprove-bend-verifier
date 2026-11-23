import Base
import ./header.bend as Header
import ./policy.bend as P
import ./policy_frame.bend as Fr

type Parts is Data:
  Parts{base: Fr.Words, ff: Fr.Words, attention: Fr.Words, head: Fr.Words, calls: P.Lines}

def base_names() -> String:
  "prof lt L ll d H G dh f fe NE V eps1_lo eps1_hi eps2_lo eps2_hi cs theta0_lo theta0_hi hq hv ho hgD huD hdD hr ut"

def ff_names() -> String:
  "la nmin D tau lmaf NAf lmad NAd lmar lmb lmq lmx wb_qk wb_v wb_o wb_g wb_u wb_gs wb_us wb_gr wb_ur wb_dn wb_dnr wb_r iota_0 iota_1 iota_2 iota_3 iota_4 iota_5 iota_6 iota_7 seed_lo seed_hi"

def attention_names() -> String:
  "lB S rx kFM kFD lmS NAs lmh lmo lmbA iotaA_0"

def head_names() -> String:
  "MF KF epsF_lo epsF_hi toksrc lmhf NHf lmhd lmhr lmbH wb_emb wb_head iotaH_0 iotaH_1 iotaH_2 iotaH_3 iotaH_4 iotaH_5 C theta cap s sh sT F"

type Parsed is Data:
  Parsed{words: Fr.Words, tail: P.Lines}

def prepend(w: U32, parsed: Parsed) -> Parsed:
  Parsed{xs,tail} = parsed
  Parsed{w <> xs,tail}

def scalars(names: P.Lines, lines: P.Lines) -> IO(Parsed):
  match names lines:
    case Nil{} tail: IO.pure(Parsed, Parsed{[],tail})
    case +name <> ns +line <> ls:
      +prefix = name ++ " "
      do IO<Parsed>:
        ok : Unit <- Header.require(String.starts_with(line,prefix), "NO: policy-name-" ++ name)
        v : U32 <- P.number(String.drop(line,String.length(prefix)))
        rest : Parsed <- scalars(ns,ls)
        return prepend(v, rest)
    case _ _: IO.die(Parsed, 1, "NO: policy-length")

def first(pair: Parsed) -> Fr.Words:
  Parsed{xs,_} = pair
  xs

def rest(pair: Parsed) -> P.Lines:
  Parsed{_,ls} = pair
  ls

def opt_value(name: String, +n: U32, lidb: Bool, nmin: U32) -> Bool:
  match name:
    case "lidb": Fr.within(n,23,30)
    case "nminH": lidb && Fr.within(n,2,28) && U32.is_gt(n,nmin)
    case "eg": Fr.within(n,4,7)
    case "smax": U32.is_eq(n,2047) || U32.is_eq(n,1023) || U32.is_eq(n,511) || U32.is_eq(n,255)
    case "rcl": U32.is_eq(n,1)
    case "gcl": U32.is_eq(n,1)
    case "xl": U32.is_eq(n,5)
    case _: False{}

def value_if(present: Bool, line: String, +name: String, lidb: Bool, nmin: U32) -> IO(Unit):
  match present:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      +prefix = name ++ " "
      do IO<Unit>:
        n : U32 <- P.number(String.drop(line,String.length(prefix)))
        Header.require(opt_value(name,n,lidb,nmin), "NO: policy-" ++ name)

def opts(names: P.Lines, lines: P.Lines, +lidb: Bool, +nmin: U32) -> IO(P.Lines):
  match names lines:
    case Nil{} tail: IO.pure(P.Lines, tail)
    case +name <> ns +line <> +ls:
      +hit = String.starts_with(line,name ++ " ")
      do IO<P.Lines>:
        ok : Unit <- value_if(hit,line,name,lidb,nmin)
        opts(ns, Bool.pick(P.Lines,hit,ls,line <> ls), lidb || (hit && String.eq(name,"lidb")),nmin)
    case _ _: IO.die(P.Lines, 1, "NO: policy-length")

def digest_names(+p: String) -> P.Lines:
  String.split(p ++ "0 " ++ p ++ "1 " ++ p ++ "2 " ++ p ++ "3 " ++ p ++ "4 " ++ p ++ "5 " ++ p ++ "6 " ++ p ++ "7",' ')

def identifier_char(+c: Char) -> Bool:
  Char.is_alpha(c) || Char.is_digit(c) || Char.is_eq(c,'.') || Char.is_eq(c,'_') || Char.is_eq(c,'-')

def identifier(+text: String) -> Bool:
  Bool.not(String.is_empty(text)) && List.all(&2,Char,c => identifier_char(c),String.to_list(text))

def category(name: String) -> U32:
  match name:
    case "call": 0
    case "callA": 1
    case "callH": 2
    case _: 3

def call_line(tokens: P.Lines) -> IO(U32):
  match tokens:
    case cls <> +name <> +kind <> +part <> +others:
      +c = category(cls)
      do IO<U32>:
        ok : Unit <- Header.require(U32.is_lt(c,3) && Nat.is_le(String.length(name),8n) &&
          List.all(&2,String,s => identifier(s),name <> kind <> part <> others), "NO: policy-call-line")
        return c
    case _: IO.die(U32,1,"NO: policy-call-line")

def calls(lines: P.Lines, +phase: U32, +f: U32, +a: U32, +h: U32) -> IO(Unit):
  match lines:
    case [""]:
      Header.require(Fr.within(f,1,8) && Fr.within(a,1,12) && U32.is_le(h,6), "NO: policy-call-list")
    case +line <> tail:
      do IO<Unit>:
        ok : Unit <- Header.require(Nat.is_lt(String.length(line),1023n), "NO: policy-line-long")
        +kind : U32 <- call_line(String.split(line,' '))
        ok : Unit <- Header.require(U32.is_le(phase,kind), "NO: policy-call-line")
        calls(tail,kind,U32.add(f,Bool.to_u32(U32.is_eq(kind,0))),
          U32.add(a,Bool.to_u32(U32.is_eq(kind,1))),U32.add(h,Bool.to_u32(U32.is_eq(kind,2))))
    case _: IO.die(Unit,1,"NO: parameter-line-missing")

def parse(+lines: P.Lines) -> IO(Parts):
  do IO<Parts>:
    +a : Parsed <- scalars(String.split(base_names(),' '),List.drop(&2,String,lines,32n))
    +f : Parsed <- scalars(String.split(ff_names(),' '),rest(a))
    +at : Parsed <- scalars(String.split(attention_names(),' '),rest(f))
    +h : Parsed <- scalars(String.split(head_names(),' '),rest(at))
    nmin : U32 <- P.field(lines,"nmin")
    tail : P.Lines <- opts(["lidb","nminH","eg","smax","rcl","gcl","xl"],rest(h),False{},nmin)
    names : P.Lines = List.concat(&2,String,[digest_names("tsilu"),digest_names("tsig"),digest_names("trope"),digest_names("texp")])
    values : Parsed <- scalars(names,tail)
    +remaining : P.Lines = rest(values)
    check : Unit <- calls(remaining,0,0,0,0)
    return Parts{first(a),first(f),first(at),first(h),remaining}
