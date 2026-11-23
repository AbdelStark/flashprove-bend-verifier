import Base
import ./weight_types.bend as G
import ./weight_rows.bend as Rows
import ./segment_model.bend as M
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./lin_own.bend as Own
import ./key_stage_lookup_rows.bend as L
import ./key_stage_openings.bend as K
import ./extension.bend as X
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./fold.bend as F
import ./header.bend as H

type Merged is Data:
  Merged{equation: M.Aff, pending: Own.Pending, free_slot: Nat, rest: P.Cursor}

def width(g: G.Layout) -> Nat:
  G.Layout{k,_,_} = g
  k

def start(claims: List<&2,G.Claim>, +rho: X.E3, +w: X.E3, +next: Nat, a: A.Aff) -> IO(A.Aff):
  match claims:
    case []: IO.pure(A.Aff,a)
    case G.Claim{_,_,_,+i,v,b} <> tail:
      do IO<A.Aff>:
        ok : Unit <- H.require(Nat.is_lt(i,next),"NO: weights-start-slot")
        start(tail,rho,E.mul(w,rho),next,A.add(a,A.hidden(A.Value{v,i,b}),w))

def weights(claims: List<&2,G.Claim>, +g: G.Layout, +rho: X.E3, +w: X.E3, +psi: B.Elements, acc: F.Form) -> IO(F.Form):
  match claims:
    case []: IO.pure(F.Form,acc)
    case c <> tail:
      do IO<F.Form>:
        ws : F.Form <- Rows.claim(g,c,psi,w,acc)
        weights(tail,g,rho,E.mul(w,rho),psi,ws)

def equation(row: A.Aff) -> M.Aff:
  A.Aff{_,ms,c} = row
  M.Aff{[],ms,E.negate(c)}

def finish(read: P.Read, +claims: List<&2,G.Claim>, g: G.Layout, rho: X.E3, s: A.Aff, index: Nat) -> IO(Merged):
  match read:
    case P.Read{P.Check{before,at,[A.Value{+target,+slot,+beta}],psc,first},tail}:
      +psi = A.rev(at)
      do IO<Merged>:
        ws : F.Form <- weights(claims,g,rho,F.one(),psi,[])
        row : M.Aff = equation(P.row(P.Check{before,[],[],psc,first},s,target))
        return Merged{row,Own.Pending{ws,psi,[Own.Slot{index,beta}],target},slot,tail}
    case _: IO.die(Merged,1,"NO: weights-merge-end")

def psc(heard: P.Coin, +g: G.Layout, +claims: List<&2,G.Claim>, index: Nat) -> IO(Merged):
  match heard:
    case P.Coin{_,[+rho],P.Cursor{ev,+first}}:
      do IO<Merged>:
        s : A.Aff <- start(claims,rho,F.one(),first,A.zero())
        read : P.Read <- P.parse(P.Cursor{ev,first},0n,List.replicate(Nat,width(g),2n),1n,1n)
        finish(read,claims,g,rho,s,index)
    case _: IO.die(Merged,1,"NO: weights-merge-challenge")

def check(g: G.Layout, +claims: List<&2,G.Claim>, events: L.Events, first_slot: Nat, index_slot: Nat, extra: Nat) -> IO(Merged):
  do IO<Merged>:
    ok : Unit <- H.require(Bool.not(List.is_empty(&2,G.Claim,claims)),"NO: weights-claim-count")
    c : P.Coin <- P.coin(P.Cursor{events,first_slot},"BAT-sigma",extra,1n)
    psc(c,g,claims,index_slot)
