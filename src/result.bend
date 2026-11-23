import Base
import ./policy_statement.bend as S
import ./policy.bend as P
import ./plan_types.bend as PT
import ./plan_catalog.bend as Catalog
import ./accounting_catalog.bend as C
import ./hash_bytes.bend as H
import ./header.bend as Header

type Range is Data:
  Range{r: Nat,e: Nat,t: Nat,last: Nat,count: Nat}

def coverage(rs: List<&2,U32>,+t: Nat) -> IO(Range):
  match rs:
    case [r,e]:
      +first = U32.to_nat(r)
      +end = U32.to_nat(e)
      +last = Nat.min(end,Nat.sub(t,1n))
      do IO<Range>:
        ok : Unit <- Header.require(Nat.is_lt(first,end) && Nat.is_le(end,t),"NO: statement-range")
        return Range{first,end,t,last,Nat.sub(last,first)}
    case _: IO.die(Range,1,"NO: statement-range")

def above(c: Nat,theta: Nat,+cap: Nat,+n: Nat,+unit: Nat) -> Nat:
  +span = Nat.sub(c,unit)
  +simple = Nat.min(cap,n)
  Bool.pick(Nat,Nat.is_gt(span,0n),Nat.min(simple,Nat.div(Nat.mul(n,Nat.sub(theta,unit)),Nat.max(1n,span))),simple)

def emit(claim: P.Claim,range: Range,report: C.Report,id: String,leaf: U32,build: String) -> IO(Unit):
  P.Claim{+c,+theta,+cap,s,+sh,st,f} = claim
  Range{+r,+e,+t,last,+n} = range
  C.Report{+work,+rounds,+least,+bare,+theorem} = report
  +unit = U32.shln(1,U32.to_nat(sh))
  +exact = U32.is_eq(c,unit) && U32.is_eq(theta,unit) && U32.is_zero(cap)
  +kind = P.kind_name(exact)
  +policy = kind ++ " C=" ++ U32.show(c) ++ " theta=" ++ U32.show(theta) ++ " cap=" ++ U32.show(cap) ++ " s=" ++ U32.show(s) ++ " sh=" ++ U32.show(sh)
  +substantive = Nat.is_gt(n,0n)
  +limited = substantive && Bool.not(exact)
  label = Bool.pick(String,substantive,Bool.pick(String,limited,"policy","exact-match"),"next-token")
  tokens = Bool.pick(String,substantive,Nat.show(1n+r) ++ ".." ++ Nat.show(last),"none")
  count = above(U32.to_nat(c),U32.to_nat(theta),U32.to_nat(cap),n,U32.to_nat(unit))
  do IO<Unit>:
    IO.print("commitment: " ++ theorem ++ " closeness rounds of the one-time files rest on another source than the bound within a third of the distance; the table has a record: the binding of the weights rests on the theorem on codes (ePrint 2025/2055, Theorem 4.6), taken as given")
    IO.print("proof of work: up to " ++ work ++ " bits counted in " ++ rounds ++ " rounds; with it the least round has " ++ least ++ " bits, without it " ++ bare ++ " bits")
    IO.print("result-v1 status=0 claim=" ++ label ++ " id=" ++ id ++ " bits=128 work=" ++ work ++ " work-rounds=" ++ rounds ++ " least-round=" ++ least ++ " least-round-without-work=" ++ bare ++ " commitment-assumed-rounds=" ++ theorem ++ " record=1 r=" ++ Nat.show(r) ++ " e=" ++ Nat.show(e) ++ " T=" ++ Nat.show(t) ++ " tokens=" ++ tokens ++ " y=" ++ Bool.pick(String,Nat.is_eq(e,t),"yes","no") ++ " policy=" ++ policy ++ " sT=" ++ U32.show(st) ++ " F=" ++ U32.show(f) ++ " above-clip=" ++ Nat.show(count) ++ " leaf=" ++ U32.show(leaf) ++ " stages=key,leaf,request dw=8 build=" ++ build)
    IO.print(Bool.pick(String,limited,"WITHIN LIMITS: " ++ policy,"YES"))

def result(st: S.Statement,p: Maybe<&2,PT.Profile>,id: String,leaf: U32,build: String) -> IO(Unit):
  match st p:
    case S.Statement{_,+request,_,_,_,_,_,lines} Some{profile}:
      +t = Nat.sub(List.length(&2,U32,request),2n)
      do IO<Unit>:
        policy : P.Claim <- P.parse(lines)
        range : Range <- coverage(List.drop(&2,U32,request,t),t)
        emit(policy,range,C.report(profile),id,leaf,build)
    case _ _: IO.die(Unit,1,"NO: unsupported-configuration")

def print(st: S.Statement,hash: H.Bytes,id: String,leaf: U32,build: String) -> IO(Unit):
  result(st,Catalog.select(H.u32s(hash)),id,leaf,build)
