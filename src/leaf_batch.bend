import Base
import ./commitment.bend as Commitment
import ./leaf_stage.bend as L
import ./leaf_shape.bend as S
import ./leaf_walk.bend as W
import ./leaf_rows.bend as Rows
import ./row_tensor.bend as X
import ./base_check.bend as B
import ./fold.bend as F
import ./extension.bend as Ext
import ./key_stage_openings.bend as K
import ./transcript.bend as T
import ./hash_bytes.bend as H
import ./opening_bytes.bend as O
import ./header.bend as Header

type Input is Data:
  Input{gamma: T.Stream, seed: T.Stream, answers: H.Bytes, draws: O.Places, left: O.Columns, right: O.Columns, phi: T.Stream, bat: T.Stream}

type Prepared is Data:
  Prepared{claim: F.Claim, after_bat: List<&2,W.EntryRound>}

def split(rounds: List<&2,W.EntryRound>) -> IO(Input & List<&2,W.EntryRound>):
  match rounds:
    case W.EntryRound{a,_,gamma,_,_,_} <> W.EntryRound{b,_,seed,_,_,_} <> W.EntryRound{c,answers,_,_,_,_} <> W.EntryRound{d,_,_,draws,left,right} <> W.EntryRound{e,_,phi,_,_,_} <> W.EntryRound{f,_,bat,_,_,_} <> rest:
      do IO<Input & List<&2,W.EntryRound>>:
        ok : Unit <- Header.require(String.eq(a,"LINK point") && String.eq(b,"SEND seed") && String.eq(c,"SEND answer") && String.eq(d,"LINK") && String.eq(e,"LINK phi") && String.eq(f,"BAT"),"NO: link-row-order")
        return (Input{gamma,seed,answers,draws,left,right,phi,bat},rest)
    case _: IO.die(Input & List<&2,W.EntryRound>,1,"NO: link-round-order")

def finish(state: Rows.Batch, shape: S.Shape, rest: List<&2,W.EntryRound>) -> IO(Prepared):
  Rows.Batch{_,_,form,target} = state
  match shape:
    case S.Shape{_,_,_,_,_,_,_,_,_,Con{S.Stage{_,B.Code{_,ell,_},_,0},_}}:
      IO.pure(Prepared,Prepared{F.Claim{form,List.replicate(Ext.E3,ell,F.zero()),target},rest})
    case _: IO.die(Prepared,1,"NO: link-mask-size")

def sides(answers: B.Elements, layout: Rows.Layout, fs: F.Factors, beta: Ext.E3, acc: Rows.Batch) -> IO(Rows.Batch):
  match answers:
    case [a,b]:
      +l = layout
      +terms = fs
      +w = beta
      IO.pure(Rows.Batch,Rows.add(Rows.sample(l,X.Right{},terms,w,b),Rows.add(Rows.sample(l,X.Left{},terms,w,a),acc)))
    case _: IO.die(Rows.Batch,1,"NO: link-sample-count")

def build(pair: Input & List<&2,W.EntryRound>, +shape: S.Shape, +layout: Rows.Layout, first: L.Table, second: L.Table, +config: H.Bytes) -> IO(Prepared):
  (Input{g,s,answers,+xs,left,right,p,bat},rest) = pair
  S.Shape{_,n,_,v,_,_,+count,_,_,_} = shape
  Rows.Layout{_,_,_,_,places,bits,_} = layout
  +gamma = T.value(B.Elements,Rows.take_point(U32.to_nat(v),g,[]))
  +seeds = Rows.take_point(Nat.add(places,bits),s,[])
  fs = X.eq(T.value(B.Elements,seeds))
  beta = T.value(Ext.E3,T.nonzero(T.after(B.Elements,seeds)))
  phi = T.value(B.Elements,Rows.take_point(Commitment.variables(n),p,[]))
  t = T.value(Ext.E3,T.element(bat))
  do IO<Prepared>:
    a : Rows.Row <- Rows.record(first,X.Left{},shape,layout,config,gamma)
    b : Rows.Row <- Rows.record(second,X.Right{},shape,layout,config,gamma)
    plain : Rows.Batch = Rows.add(Rows.equality(layout,phi),Rows.add(b,Rows.add(a,Rows.Batch{t,F.one(),[],F.zero()})))
    sampled : Rows.Batch <- sides(Rows.packed(answers),layout,fs,beta,plain)
    lhs : Rows.Batch <- Rows.columns(List.take(&2,Nat,xs,U32.to_nat(count)),left,layout,X.Left{},gamma,sampled)
    rhs : Rows.Batch <- Rows.columns(List.drop(&2,Nat,xs,U32.to_nat(count)),right,layout,X.Right{},gamma,lhs)
    finish(rhs,shape,rest)

def prepare(+shape: S.Shape, first: L.Table, second: L.Table, rounds: List<&2,W.EntryRound>, config: H.Bytes) -> IO(Prepared):
  do IO<Prepared>:
    layout : Rows.Layout <- Rows.layout(shape)
    pair : Input & List<&2,W.EntryRound> <- split(rounds)
    build(pair,shape,layout,first,second,config)
