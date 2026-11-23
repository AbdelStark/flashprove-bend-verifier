import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as PSC
import ./segment_attention_rounds.bend as R
import ./segment_forest.bend as Forest
import ./segment_tables.bend as S
import ./head_catalog.bend as C
import ./head_types.bend as G
import ./key_stage_trace.bend as Trace
import ./key_stage_lookup_rows.bend as L
import ./key_stage_psc.bend as P
import ./extension.bend as X
import ./base_check.bend as B
import ./fold.bend as F
import ./plan.bend as Plan
import ./header.bend as Header

# All points in the H821 descriptions are printed high bit first. The key
# forest returns separate selector and within-tree points, both low bit first.
type Keys is Data:
  Keys{trees: B.Elements, leaves: B.Elements, token_high: B.Elements}

def keys(f: Forest.Claims, shape: S.Forest, +lt: Nat) -> Keys:
  Forest.Claims{L.Point{+xs,_,_},_,_,_} = f
  S.Forest{_,_,+tree,_,_} = shape
  +leaves = List.drop(&2,X.E3,xs,tree)
  Keys{F.take(X.E3,xs,tree),leaves,A.rev(F.take(X.E3,leaves,lt))}

def tokens(k: Keys) -> B.Elements:
  Keys{_,_,p} = k
  p

def column(k: Keys, lt: Nat, bits: Nat) -> B.Elements:
  Keys{tree,leaf,_} = k
  F.take(X.E3,F.cat(X.E3,List.drop(&2,X.E3,leaf,lt),tree),bits)

def parse(cur: PSC.Cursor, pre: Nat, point: B.Elements, ends: Nat) -> IO(PSC.Read):
  PSC.with_variables(cur,pre,PSC.eqs(point),2n,ends)

type Heard is Data:
  Heard{pv: B.Elements, limbs: A.Values, gamma: X.E3, squares: PSC.Check, products: A.Values, omega: X.E3,
    row: PSC.Check, norm: PSC.Check, logits: PSC.Check}

def receive(cur: PSC.Cursor, +s: G.Shape, +k: Keys) -> IO(Heard):
  +t = C.lt(s)
  +d = C.log_channels(s)
  +hs = List.replicate(X.E3,d,PSC.half())
  do IO<Heard>:
    +pv : PSC.Coin <- PSC.coin(cur,"ZERO",0n,t)
    +limbs : PSC.Coin <- PSC.coin(R.next_coin(pv),"BAT-sigma",9n,1n)
    +squares : PSC.Read <- parse(R.next_coin(limbs),0n,F.cat(X.E3,hs,R.points(pv)),2n)
    tau : PSC.Coin <- PSC.coin(R.next(squares),"LINE",0n,1n)
    +prod : PSC.Coin <- PSC.coin(R.next_coin(tau),"BAT-sigma",7n,1n)
    +row : PSC.Read <- parse(R.next_coin(prod),1n,R.points(pv),4n)
    +norm : PSC.Read <- parse(R.next(row),1n,tokens(k),2n)
    +logits : PSC.Read <- parse(R.next(norm),1n,F.cat(X.E3,tokens(k),hs),2n)
    n : Nat <- R.used(logits)
    return Heard{R.points(pv),R.declared(limbs),R.challenge(limbs),R.checked(squares),R.declared(prod),
      R.challenge(prod),R.checked(row),R.checked(norm),R.checked(logits)}

def bat(ev: Trace.Observed) -> Bool:
  Trace.Observed{Plan.Round{n,_,_,_,_,_,_,_,_,_,_,_},_,_,_,_} = ev
  String.eq(n,"BAT-sigma")

def named(ev: Trace.Observed) -> String:
  Trace.Observed{Plan.Round{n,_,_,_,_,_,_,_,_,_,_,_},_,_,_,_} = ev
  n

def first(events: Trace.Events, +slots: Nat) -> IO(PSC.Cursor):
  match events:
    case +a <> +b <> +tail:
      pick = Bool.pick(Unit -> IO(PSC.Cursor),String.eq(named(a),"ZERO") && bat(b),
        _ => R.scan(a <> b <> tail,slots,[]), _ => first(b <> tail,slots))
      pick(Unit{})
    case _: IO.die(PSC.Cursor,1,"NO: head-norm-point")

def hear(s: G.Shape, k: Keys, events: Trace.Events) -> IO(Heard):
  +shape = s
  do IO<Heard>:
    cur : PSC.Cursor <- first(events,C.forest_slots(shape))
    receive(cur,shape,k)
