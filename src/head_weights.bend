import Base
import ./head_types.bend as G
import ./head_catalog.bend as C
import ./head_rounds.bend as R
import ./head_coverage.bend as V
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./weight_types.bend as W
import ./weight_merge.bend as Merge
import ./segment_stage.bend as Stage
import ./segment_attention_rounds.bend as Read
import ./key_stage_trace.bend as Trace
import ./key_stage_lookup_rows.bend as L
import ./fold.bend as F
import ./sumcheck.bend as E
import ./row_tensor.bend as T
import ./extension.bend as X
import ./base_check.bend as B
import ./header.bend as Header

def channel_factor(r: B.Elements, u: W.WeightUnit) -> IO(W.Factor):
  match u:
    case W.WeightUnit{13n,_,_,_,_,_,[W.Group{_,W.A{},_,_,_,_,_,_,_},W.Group{_,W.E{},False{},_,odd,+bits,_,_,_}]}:
      +rs = r
      high = F.factor_table(T.eq(List.drop(&2,X.E3,rs,bits)),F.one())
      IO.pure(W.Factor,W.Equality{F.take(X.E3,rs,bits),F.take(X.E3,high,odd)})
    case _: IO.die(W.Factor,1,"NO: head-weight-layout")

def first(us: List<&2,W.WeightUnit>) -> IO(W.WeightUnit):
  match us:
    case x <> _: IO.pure(W.WeightUnit,x)
    case _: IO.die(W.WeightUnit,1,"NO: head-weight-layout")

def head_unit(layout: W.Layout) -> IO(W.WeightUnit):
  W.Layout{_,_,us} = layout
  first(List.reverse(&2,W.WeightUnit,us))

def claim(v: A.Value, s: G.Shape, vocab: B.Elements, channels: W.Factor) -> W.Claim:
  A.Value{x,i,beta} = v
  W.Claim{13n,C.layer(s),[W.ArrayFactor{vocab},channels],i,x,beta}

def make(+s: G.Shape, k: R.Keys, cov: V.Covered, h: R.Heard, layout: W.Layout) -> IO(W.Claim):
  R.Heard{_,_,_,_,_,_,_,_,+logits} = h
  +point = P.point(logits)
  +lt = C.lt(s)
  vocab = V.vocabulary(cov,G.segment(s,2n),k,lt,C.vocab(s),F.take(X.E3,point,lt))
  rs = A.rev(List.drop(&2,X.E3,point,lt))
  do IO<W.Claim>:
    u : W.WeightUnit <- head_unit(layout)
    ch : W.Factor <- channel_factor(rs,u)
    return claim(A.at(P.ends(logits),1n),s,vocab,ch)

def apply(slice: Stage.Slice, layout: W.Layout, c: W.Claim, slot: Nat, index: Nat) -> IO(Merge.Merged):
  Stage.Slice{rs,_} = slice
  Merge.check(layout,[c],rs,slot,index,0n)

def merge(+s: G.Shape, +w: W.Layout, c: W.Claim, +events: Trace.Events, index: Nat) -> IO(Merge.Merged):
  +bits = Merge.width(w)
  count = Nat.add(bits,4n)
  skip = Nat.sub(List.length(&2,Trace.Observed,events),Nat.add(bits,5n))
  used = Nat.sub(C.slots(s),Nat.add(Nat.mul(2n,bits),3n))
  do IO<Merge.Merged>:
    slice : Stage.Slice <- Stage.slice(count,List.drop(&2,Trace.Observed,events,skip),[])
    apply(slice,w,c,used,index)
