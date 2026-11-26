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

# The 128 powers sit in an array threaded through every column, so each
# trit reads one entry instead of taking a cell of a shared list. Missing
# powers read as zero, as a shorter list contributed nothing.
type Acc is Type:
  Acc{powers: Array<X.E3>, sum: X.E3}
type Col is Type:
  Col{powers: Array<X.E3>, sum: X.E3, stream: T.Stream}

def table(ps: B.Elements, +i: U32, buf: Array<X.E3>) -> Array<X.E3>:
  match ps:
    case []: buf
    case y <> tail: table(tail,U32.add(i,1),Array.set(X.E3,buf,i,y))

def powers_table(ps: B.Elements) -> Array<X.E3>:
  table(List.take(&2,X.E3,ps,128n),0,Array.new(X.E3,7n,F.zero()))

# Fold 16 trits of x against the powers from i on.
def limb(n: Nat, +i: U32, +x: U32, total: X.E3, got: Array<X.E3> & X.E3) -> Acc:
  match n:
    case 0n:
      (a,_) = got
      Acc{a,total}
    case 1n+k:
      (a,y) = got
      +j = U32.add(i,1)
      limb(k,j,U32.shrn(x,2n),signed(U32.and(x,3),total,y),Array.get(X.E3,a,j))

def high(r: Acc, +i: U32, +hi: U32) -> Acc:
  Acc{a,s} = r
  limb(16n,i,hi,s,Array.get(X.E3,a,i))

# Low limb first: trits i..i+15, then i+16..i+31.
def word(w: Word.Bits64, +i: U32, r: Acc) -> Acc:
  Word.Bits64{hi,lo} = w
  Acc{a,s} = r
  high(limb(16n,i,lo,s,Array.get(X.E3,a,i)),U32.add(i,16),hi)

def vector(n: Nat, +i: U32, r: Acc, stream: T.Stream) -> Col:
  match n:
    case 0n:
      Acc{a,s} = r
      Col{a,s,stream}
    case 1n+k:
      +v = T.next_word(stream)
      vector(k,U32.add(i,32),word(T.value(Word.Bits64,v),i,r),T.after(Word.Bits64,v))

# last carries the previous column's sum; the seed's is dropped at the end.
def columns_with(n: Nat, acc: B.Elements, last: Col) -> T.Read<B.Elements>:
  match n:
    case 0n:
      Col{_,s,stream} = last
      T.Read{List.drop(&2,X.E3,List.reverse(&2,X.E3,s <> acc),1n),stream}
    case 1n+k:
      Col{a,s,stream} = last
      columns_with(k,s <> acc,vector(4n,0,Acc{a,F.zero()},stream))

def columns(n: Nat, ps: B.Elements, stream: T.Stream) -> T.Read<B.Elements>:
  columns_with(n,[],Col{powers_table(ps),F.zero(),stream})
