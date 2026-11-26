import Base
import ./base_check.bend as B
import ./fold.bend as F
import ./fold_cs.bend as CS
import ./fold_verify.bend as V
import ./key_stage_trace.bend as Tr
import ./lin_run.bend as Lin
import ./extension.bend as X
import ./sumcheck.bend as E
import ./header.bend as H
import ./leaf_shape.bend as S
import ./row_tensor.bend as T

# The only observation of the carried main coefficients occurs at BASE.
# Each subsequent code switch passes them unchanged to the next low-bit
# fold. Its hiding epsilon scales both representations identically. Thus it
# suffices to retain the column functional after fixing the terminal gammas.
# The ordinary terminal verifier replays the same authenticated rounds.
type Basis is Data:
  Basis{gamma: B.Elements, low_bits: Nat, base_bits: Nat}

def tag(name: String) -> U32:
  match name:
    case "BAT": 1
    case "FOLD round": 2
    case "BASE": 3
    case _: 0

# The final BAT is immediately before the one-bit FOLD of carrier rows.
# That first gamma chooses the carrier's row. Subsequent gammas fix columns.
def next(kind: U32,e: Tr.Observed,rev: B.Elements) -> B.Elements:
  match kind:
    case 1: []
    case 2: V.first(Lin.stream(e)) <> rev
    case _: rev

def columns(values: B.Elements) -> Maybe<&2,B.Elements>:
  match values:
    case _ <> tail: Some{tail}
    case []: None{}

def take(events: Tr.Events,+rev: B.Elements) -> Maybe<&2,B.Elements>:
  match events:
    case []: None{}
    case +e <> tail:
      +kind = tag(Lin.name(e))
      choose = Bool.pick(Unit -> Maybe<&2,B.Elements>,U32.is_eq(kind,3),
        _ => columns(List.reverse(&2,X.E3,rev)), _ => take(tail,next(kind,e,rev)))
      choose(Unit{})

def parsed(gs: Maybe<&2,B.Elements>,ell: Nat,+n: Nat) -> IO(Basis):
  match gs:
    case Some{+coords}:
      +bits = F.count(X.E3,coords,0n)
      +base_bits = CS.bits(n)
      do IO<Basis>:
        ok : Unit <- H.require(Nat.is_eq(ell,Nat.mul(n,CS.size(bits))) && CS.power_two(n),"NO: request-terminal-dimensions")
        return Basis{coords,bits,base_bits}
    case _: IO.die(Basis,1,"NO: request-terminal-rounds")

def load(events: Tr.Events,ell: Nat,stages: List<&2,S.Stage>) -> IO(Basis):
  match stages:
    case [S.Stage{B.Code{_,n,_},_,_,_}]: parsed(take(events,[]),ell,n)
    case _ <> rest: load(events,ell,rest)
    case []: IO.die(Basis,1,"NO: request-terminal-stages")

def deposit_unless(zero: Bool,fs: F.Factors,w: X.E3,buf: Array<X.E3>) -> Array<X.E3>:
  match zero:
    case True{}: buf
    case False{}: F.deposit(List.reverse(&2,F.Factor,fs),0,w,buf)

def write(term: F.Term,buf: Array<X.E3>) -> Array<X.E3>:
  F.Term{+w,fs} = term
  deposit_unless(B.equal(w,F.zero()),fs,w,buf)

# The projector is threaded through the terms; last is the previous term.
def reduce_with(xs: F.Form,last: F.Projected,buf: Array<X.E3>) -> Array<X.E3>:
  match xs:
    case []:
      F.Projected{t,_} = last
      write(t,buf)
    case term <> tail:
      F.Projected{t,p} = last
      reduce_with(tail,F.project_with(p,term),write(t,buf))

def reduce(xs: F.Form,cs: F.Chunks,buf: Array<X.E3>) -> Array<X.E3>:
  reduce_with(xs,F.Projected{F.Term{F.zero(),[]},F.projector(cs)},buf)

def merge(+basis: Basis,local: F.Form,old: B.Elements,scale: X.E3) -> B.Elements:
  Basis{gs,_,n} = basis
  table = reduce(local,F.prepare(gs),Array.new(X.E3,n,F.zero()))
  F.accumulate(Array.to_list(X.E3,table),F.scaled(old,scale),[])

def zeros(basis: Basis) -> B.Elements:
  Basis{_,_,n} = basis
  CS.zeros(CS.size(n))

# Lift the small table to a function constant in all already-fixed low bits.
# Evaluating these neutral factors needs no inverse, including at gamma=0 or 1.
def rows(xs: B.Elements,+low: F.Factors,+bits: Nat,+i: Nat,+acc: F.Form) -> F.Form:
  match xs:
    case []: acc
    case +x <> tail:
      fs = List.append(&2,F.Factor,low,T.choice(bits,i))
      rows(tail,low,bits,1n+i,Bool.pick(F.Form,B.equal(x,F.zero()),acc,F.Term{x,fs} <> acc))

def lift(basis: Basis,values: B.Elements) -> F.Form:
  Basis{_,k,n} = basis
  rows(values,List.replicate(F.Factor,k,F.Factor{F.one(),F.one()}),n,0n,[])
