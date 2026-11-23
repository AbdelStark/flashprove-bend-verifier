import Base
import ./fold.bend as F
import ./sumcheck.bend as E
import ./extension.bend as X
import ./base_check.bend as B
import ./transcript.bend as T
import ./chain.bend as Word
import ./key_stage_trace.bend as Trace
import ./plan.bend as P
import ./header.bend as Header

# R11.1 extracts 128 ternary coefficients of a physical column, low pair
# of bits first. Fold each column immediately into sum(Cf[c,u]*chi^u).
type Coins is Data:
  Coins{rng: T.Stream, count: Nat, chi: X.E3, batch: Nat}

def name(round: P.Round) -> String:
  P.Round{n,_,_,_,_,_,_,_,_,_,_,_} = round
  n

def tag(n: String) -> U32:
  match n:
    case "BAT-sigma": 1
    case "RNG": 2
    case _: 0

type Found is Data:
  Found{rng: Maybe<&2,T.Stream>, entries: Nat, final: Maybe<&2,X.E3>, rows: Nat}

def count(p: P.Round) -> U32:
  P.Round{_,_,_,_,_,_,_,_,_,_,_,n} = p
  n

def trits(p: P.Round) -> U32:
  P.Round{_,_,_,_,_,_,_,_,_,_,n,_} = p
  n

def update(code: U32, stream: T.Stream, round: P.Round, old: Found) -> Found:
  match code old:
    case 1 Found{rng,n,_,_}:
      Found{rng,n,Some{T.value(X.E3,T.element(stream))},U32.to_nat(count(round))}
    case 2 Found{_,_,last,rows}:
      Found{Some{stream},U32.to_nat(trits(round)),last,rows}
    case _ st: st

def find(events: Trace.Events, state: Found) -> IO(Coins):
  match events state:
    case Nil{} Found{Some{r},n,Some{v},count}: IO.pure(Coins,Coins{r,n,v,count})
    case Con{Trace.Observed{+round,_,s,_,_},tail} st: find(tail,update(tag(name(round)),s,round,st))
    case _ _: IO.die(Coins,1,"NO: segment-smallness-coins")

def powers(n: Nat, +chi: X.E3, +x: X.E3) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k: x <> powers(k,chi,E.mul(x,chi))

def signed(bit: U32, acc: X.E3, term: X.E3) -> X.E3:
  match bit:
    case 1: E.add(acc,term)
    case 3: F.sub(acc,term)
    case _: acc

def limb(p: B.Elements, +x: U32, total: X.E3) -> X.E3:
  match p:
    case []: total
    case y <> tail: limb(tail,U32.shrn(x,2n),signed(U32.and(x,3),total,y))

def end_word(w: Word.Bits64, +ps: B.Elements, sum: X.E3) -> X.E3:
  Word.Bits64{hi,lo} = w
  limb(List.drop(&2,X.E3,ps,16n),hi,limb(List.take(&2,X.E3,ps,16n),lo,sum))

def vector(n: Nat, ps: B.Elements, stream: T.Stream, sum: X.E3) -> T.Read<X.E3>:
  match n:
    case 0n: T.Read{sum,stream}
    case 1n+k:
      +powers = ps
      +v = T.next_word(stream)
      next = end_word(T.value(Word.Bits64,v),List.take(&2,X.E3,powers,32n),sum)
      vector(k,List.drop(&2,X.E3,powers,32n),T.after(Word.Bits64,v),next)

def columns(n: Nat, +ps: B.Elements, stream: T.Stream, acc: B.Elements) -> T.Read<B.Elements>:
  match n:
    case 0n: T.Read{List.reverse(&2,X.E3,acc),stream}
    case 1n+k:
      +c = vector(4n,ps,stream,F.zero())
      columns(k,ps,T.after(X.E3,c),T.value(X.E3,c) <> acc)
