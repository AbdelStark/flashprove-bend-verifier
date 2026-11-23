import Base
import ./lin_own.bend as Own
import ./lin_run.bend as Run
import ./key_stage_batt.bend as Key
import ./key_stage_lookup_rows.bend as L
import ./key_stage_psc.bend as PSC
import ./key_stage_openings.bend as K
import ./key_stage_trace.bend as Tr
import ./leaf_shape.bend as Leaf
import ./lin_shape.bend as Lin
import ./oracle_sample.bend as Sample
import ./fold.bend as F
import ./fold_verify.bend as V
import ./sumcheck.bend as A
import ./row_tensor.bend as X
import ./base_check.bend as B
import ./extension.bend as E
import ./plan.bend as P
import ./header.bend as H

def Pending() -> Data: List<&2,Own.Pending>

def slot_scale(xs: List<&2,Own.Slot>, +p: E.E3, acc: L.Masks) -> L.Masks:
  match xs:
    case []: acc
    case Own.Slot{i,w} <> more: slot_scale(more,p,L.Mask{L.IndexMask{},i,A.mul(w,p)} <> acc)

def merge(xs: Pending, +theta: E.E3, +p: E.E3, masks: L.Masks, target: E.E3) -> Key.Combined:
  match xs:
    case []: Key.Combined{masks,target}
    case Own.Pending{_,_,ms,t} <> rest: merge(rest,theta,A.mul(p,theta),slot_scale(ms,p,masks),B.masked(target,p,t))

def weights(xs: Pending, +gamma: B.Elements, +theta: E.E3, +w: E.E3, acc: F.Form) -> F.Form:
  match xs:
    case []: acc
    case Own.Pending{fs,z,_,_} <> tail: weights(tail,gamma,theta,A.mul(theta,w),X.scale(fs,Key.eq(z,gamma,w),acc))

def finish(tape: L.Tape, obligation: PSC.Obligation, xs: Pending, inherited: L.Masks, +gamma: B.Elements, theta: E.E3, eps: E.E3, next: Nat) -> IO(Own.Pending):
  L.Tape{rest,_,_,_} = tape
  PSC.Obligation{target,fresh,carry,_} = obligation
  do IO<Own.Pending>:
    valid : Unit <- H.require(List.is_empty(&2,L.AlgebraRound,rest),"NO: request-batt-extra-rounds")
    masks : List<&2,Own.Slot> <- Key.slots(L.sum(L.next(fresh,L.IndexMask{},next),L.scale(inherited,carry)),[])
    return Own.Pending{weights(xs,gamma,theta,eps,[]),gamma,masks,target}

def folded(state: L.State, xs: Pending, inherited: L.Masks, theta: E.E3, next: Nat) -> IO(Own.Pending):
  L.State{+claim,rev,tape} = state
  PSC.Claim{_,eps,_} = claim
  finish(tape,PSC.obligation(claim,F.zero(),[]),xs,inherited,List.reverse(&2,E.E3,rev),theta,eps,next)

def sumcheck(start: Key.Combined, tape: L.Events, +xs: Pending, theta: E.E3, k: Nat, next: Nat) -> IO(Own.Pending):
  Key.Combined{masks,target} = start
  do IO<Own.Pending>:
    first : L.State <- L.begin(L.Tape{tape,0n,0n,[]},target)
    last : L.State <- L.rounds(List.replicate(PSC.Variable,k,PSC.Variable{PSC.Plain{},2n}),first)
    folded(last,xs,masks,theta,next)

type Index is Data:
  Index{seed: Sample.Seed, answer: E.E3}

def initial(events: Tr.Events) -> IO(Index):
  match events:
    case Tr.Observed{P.Round{first,_,_,_,_,_,n,1,_,_,_,_},_,s,_,_} <> Tr.Observed{P.Round{reply,_,_,_,_,+a,_,_,_,_,_,_},raw,_,_,_} <> _:
      do IO<Index>:
        ok : Unit <- H.require(String.eq(first,"SEND seed") && String.eq(reply,"SEND answer") && U32.is_lt(0,a),"NO: request-index-send")
        ys : B.Elements <- K.need(B.Elements,B.read_elements(U32.to_nat(a),raw,[],True{}),"NO: request-index-answer")
        return Index{Sample.point(Nat.sub(U32.to_nat(n),1n),s,[]),V.pick(List.reverse(&2,E.E3,ys))}
    case _: IO.die(Index,1,"NO: request-index-send")

def point_sizes(xs: Pending, +k: Nat, good: Bool) -> Bool:
  match xs good:
    case Nil{} v: v
    case Con{Own.Pending{_,z,_,_},rest} True{}: point_sizes(rest,k,Nat.is_eq(F.count(E.E3,z,0n),k))
    case _ _: False{}

def result(first: Index, tail: Key.Tail, +rows: Pending, +k: Nat) -> IO(Own.First):
  Index{iz,iy} = first
  Key.Tail{+theta,count,Key.Later{tape,ws,wy}} = tail
  +n = F.count(Own.Pending,rows,0n)
  do IO<Own.First>:
    ok : Unit <- H.require(Nat.is_eq(count,n) && Nat.is_lt(1n,n) && point_sizes(rows,k,True{}),"NO: request-batt-row-count")
    pending : Own.Pending <- sumcheck(merge(rows,theta,F.one(),[],F.zero()),tape,rows,theta,k,n)
    return Own.First{pending,Own.Opened{iz,iy,ws,wy}}

def combine(events: Tr.Events, after_base: Tr.Events, rows: Pending, k_col: Nat) -> IO(Own.First):
  do IO<Own.First>:
    idx : Index <- initial(events)
    bat : Key.Tail <- Key.sigma(after_base)
    result(idx,bat,rows,k_col)

def columns(shape: Lin.Shape) -> Nat:
  Lin.Shape{Leaf.Shape{_,_,_,v,_,_,_,_,_,_},low,_,_,_,_,_} = shape
  Nat.add(low,U32.to_nat(v))

def checked(events: Tr.Events, after_base: Tr.Events, rows: Pending, items: List<&2,P.Item>) -> IO(Own.First):
  do IO<Own.First>:
    table : Lin.Shape <- Lin.load(items)
    combine(events,after_base,rows,columns(table))
