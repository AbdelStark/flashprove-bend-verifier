import Base
import ../../src/head_norm.bend as Head
import ../../src/head_rounds.bend as R
import ../../src/head_catalog.bend as C
import ../../src/segment_inputs.bend as Inputs
import ../../src/segment_model.bend as M
import ../../src/plan_types.bend as PT
import ../../src/fold.bend as F
import ./segment_projection.bend as Out
import ./attention_projection.bend as Components

def rows(xs: M.Equations) -> IO(Unit):
  match xs:
    case []: IO.pure(Unit,Unit{})
    case M.Aff{fs,m,t} <> rest:
      do IO<Unit>:
        line : Unit <- IO.print("head-norm " ++ Out.print(t) ++ " " ++ Out.print(Out.dot(m,F.zero())) ++ " " ++ Out.print(Components.reads(fs,F.zero())))
        rows(rest)

def head(input: M.Inputs,p: PT.Profile) -> IO(Unit):
  M.Inputs{+link,main,_,events,_,tree,_} = input
  +s = C.select(p)
  +keys = R.keys(main,tree,C.lt(s))
  do IO<Unit>:
    +h : R.Heard <- R.hear(s,keys,events)
    norm : M.Equations <- Head.norm(s,h,keys,link)
    result : Unit <- rows(norm)
    rows(Head.logits(s,h,link))

def groups(xs: Inputs.Batches,p: PT.Profile) -> IO(Unit):
  match xs:
    case [x]: head(x,p)
    case _ <> tail: groups(tail,p)
    case _: IO.die(Unit,1,"missing output head")
