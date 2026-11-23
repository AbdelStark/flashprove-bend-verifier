import Base
import ./segment_attention_aff.bend as A
import ./key_stage_lookup_rows.bend as L
import ./key_stage_psc.bend as PSC
import ./key_stage_openings.bend as K
import ./fold.bend as F
import ./extension.bend as X
import ./sumcheck.bend as E
import ./base_check.bend as B
import ./header.bend as Header

# R11.3 table of rounds 4–15. Hidden scalars piggybacked on epsilon and
# BAT-sigma occupy earlier absolute slots than the sumcheck's own coefficients.
type Cursor is Data:
  Cursor{events: L.Events, slot: Nat}
type Check is Data:
  Check{before: A.Values, at: B.Elements, ends: A.Values, masks: L.Masks, relation: B.Elements}
type Read is Data:
  Read{check: Check, cursor: Cursor}

def hidden(xs: B.Elements, +beta: X.E3, i: Nat) -> A.Values:
  match xs:
    case []: []
    case x <> tail:
      +j = i
      A.Value{x,j,beta} <> hidden(tail,beta,1n+j)

def completed(input: A.Values, at: B.Elements, ends: A.Values, o: PSC.Obligation, epsilon: X.E3, i: Nat) -> Check:
  PSC.Obligation{running,fs,carry,_} = o
  Check{input,at,ends,L.next(fs,L.Multiplicities{},i),[running,epsilon,carry]}

def epsilon(c: PSC.Claim) -> X.E3:
  PSC.Claim{_,eps,_} = c
  eps

def mask_count(o: PSC.Obligation) -> Nat:
  PSC.Obligation{_,ms,_,_} = o
  List.length(&2,X.E3,ms)

def values(n: Nat, state: L.State, +first: Nat, inputs: A.Values, at: B.Elements) -> IO(Read):
  match state:
    case L.State{claim,beta <> _,L.Tape{L.AlgebraRound{name,+vals,[]} <> tail,_,_,_}}:
      +count = List.length(&2,X.E3,vals)
      +p = claim
      +slot = Nat.add(first,mask_count(PSC.obligation(p,F.zero(),[])))
      do IO<Read>:
        ok : Unit <- Header.require(String.eq(name,"PSC values") && Nat.is_eq(n,count),"NO: attention-psc-values")
        return Read{completed(inputs,at,hidden(vals,beta,slot),PSC.obligation(p,F.zero(),[]),epsilon(p),first),Cursor{tail,Nat.add(slot,count)}}
    case _: IO.die(Read,1,"NO: attention-psc-values")

def last(+st: L.State, y: Nat, n: Nat, first: Nat, inputs: A.Values) -> IO(Read):
  L.State{_,rev,_} = st
  do IO<Read>:
    end : L.State <- L.bind(st,"PSC Y",PSC.Variable{PSC.Equal{F.zero()},y})
    values(n,end,first,inputs,A.rev(rev))

def half() -> X.E3: X.E3{2147483647,2147483649,0,0,0,0}

def eqs(zs: B.Elements) -> List<&2,PSC.Variable>:
  match zs:
    case []: []
    case z <> tail: PSC.Variable{PSC.Equal{z},2n} <> eqs(tail)

def degrees(xs: List<&2,Nat>) -> List<&2,PSC.Variable>:
  match xs:
    case []: []
    case n <> tail: PSC.Variable{PSC.Plain{},n} <> degrees(tail)

def begin(raw: B.Elements, mu_list: B.Elements, +pre: Nat, eps: X.E3, vars: List<&2,PSC.Variable>, y: Nat, n: Nat, after: Cursor) -> IO(Read):
  match mu_list after:
    case [mu] Cursor{events,+slot}:
      do IO<Read>:
        bound : L.State <- L.rounds(vars,L.State{PSC.begin(mu,eps,F.zero()),[],L.Tape{events,0n,0n,[]}})
        last(bound,y,n,Nat.add(slot,pre),hidden(List.take(&2,X.E3,raw,pre),F.one(),slot))
    case _ _: IO.die(Read,1,"NO: attention-psc-prefix")

def with_variables(cursor: Cursor, +pre: Nat, vars: List<&2,PSC.Variable>, y: Nat, n: Nat) -> IO(Read):
  match cursor:
    case Cursor{L.AlgebraRound{name,+raw,[eps]} <> events,slot}:
      do IO<Read>:
        ok : Unit <- Header.require(String.eq(name,"PSC epsilon"),"NO: attention-psc")
        begin(raw,List.drop(&2,X.E3,raw,pre),pre,eps,vars,y,n,Cursor{events,slot})
    case _: IO.die(Read,1,"NO: attention-psc")

def parse(cursor: Cursor, pre: Nat, vars: List<&2,Nat>, y: Nat, n: Nat) -> IO(Read):
  with_variables(cursor,pre,degrees(vars),y,n)

def sc3(cursor: Cursor, prefix: Nat, rounds: Nat, pairs: Nat) -> IO(Read):
  parse(cursor,prefix,List.replicate(Nat,rounds,3n),2n,Nat.mul(2n,pairs))

type Coin is Data:
  Coin{hidden: A.Values, challenges: B.Elements, cursor: Cursor}

def coin(cursor: Cursor, expected: String, +n: Nat, c: Nat) -> IO(Coin):
  match cursor:
    case Cursor{L.AlgebraRound{name,+raw,+xs} <> tail,+slot}:
      do IO<Coin>:
        ok : Unit <- Header.require(String.eq(name,expected) && Nat.is_eq(n,List.length(&2,X.E3,raw)) &&
          Nat.is_eq(c,List.length(&2,X.E3,xs)),"NO: attention-coin")
        return Coin{hidden(raw,F.one(),slot),xs,Cursor{tail,Nat.add(slot,n)}}
    case _: IO.die(Coin,1,"NO: attention-coin")

def row(c: Check, start: A.Aff, s0: X.E3) -> A.Aff:
  Check{_,_,_,m,+relation} = c
  # With zero as provisional start, cur lacks eps * product(gamma) * pub(start).
  # The public part cancels its occurrence in P(pub(start)-start).
  constant = F.sub(E.mul(A.get(relation,1n),s0),A.get(relation,0n))
  A.add(A.Aff{[],m,constant},start,E.negate(A.get(relation,2n)))

def products(vs: A.Values, weights: B.Elements, a: X.E3) -> X.E3:
  match vs weights:
    case Con{x,Con{y,rest}} Con{w,tail}: products(rest,tail,E.add(a,E.mul(w,E.mul(A.scalar(x),A.scalar(y)))))
    case _ _: a

def product_row(+c: Check, start: A.Aff, weights: B.Elements) -> A.Aff:
  Check{_,_,ends,_,_} = c
  row(c,start,products(ends,weights,F.zero()))

def prefix(c: Check) -> A.Values:
  Check{vs,_,_,_,_} = c
  vs

def point(c: Check) -> B.Elements:
  Check{_,at,_,_,_} = c
  at

def ends(c: Check) -> A.Values:
  Check{_,_,vs,_,_} = c
  vs
