import Base
import ../../src/fold.bend as F
import ../../src/fold_frame.bend as Frame
import ../../src/segment_local.bend as Local
import ../../src/segment_batch.bend as Batch
import ../../src/segment_inputs.bend as Inputs
import ../../src/segment_model.bend as M
import ../../src/key_stage_lookup.bend as KL
import ../../src/base_check.bend as B
import ../../src/sumcheck.bend as E
import ../../src/extension.bend as X
import ./segment_projection.bend as Output

# Differential hook shared with project-model-batch.inc.
def at(f: F.Factors, coordinate: Nat,acc: X.E3) -> X.E3:
  match f:
    case []: acc
    case +factor <> rest:
      l = F.at_bit(factor,False{})
      h = F.at_bit(factor,True{})
      +i = coordinate
      at(rest,1n+i,E.mul(acc,F.mix(l,h,KL.small(i))))

def terms(ts: F.Form,acc: X.E3) -> X.E3:
  match ts:
    case []: acc
    case F.Term{c,fs} <> tail: terms(tail,E.add(acc,at(fs,13n,c)))

def cells(ts: Frame.Forms,acc: X.E3) -> X.E3:
  match ts:
    case []: acc
    case Frame.On{_,True{},_} <> tail: cells(tail,acc)
    case Frame.On{id,False{},fs} <> tail: cells(tail,E.add(acc,E.mul(KL.small(id),terms(fs,F.zero()))))

def masks(xs: B.Elements,i: Nat,acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case x <> tail:
      +j = i
      masks(tail,1n+j,E.add(acc,E.mul(KL.small(j),x)))

def result(row: Local.Local,ms: X.E3) -> IO(Unit):
  Local.Local{Frame.Equation{fs,y},_} = row
  IO.print("model-batch " ++ Output.print(y) ++ " " ++ Output.print(cells(fs,F.zero())) ++ " " ++ Output.print(ms))

def mask_sum(got: Local.Logical) -> X.E3:
  Local.Logical{Batch.Row{_,ms,_},_,_} = got
  masks(ms,1n,F.zero())

def emit(p: Local.Logical,ctx: Local.Context,link: Nat) -> IO(Unit):
  +got = p
  do IO<Unit>:
    row : Local.Local <- Local.physical(link,ctx,got)
    result(row,mask_sum(got))

def groups(xs: Inputs.Batches,+ctx: Local.Context) -> IO(Unit):
  match xs:
    case +g <> +a <> tail:
      do IO<Unit>:
        feed : Local.Logical <- Local.at_feed(g,ctx)
        previous : Unit <- emit(feed,ctx,Local.number(g))
        got : Local.Logical <- Local.at_attention(a,ctx)
        done : Unit <- emit(got,ctx,Local.number(a))
        groups(tail,ctx)
    case [+h]:
      do IO<Unit>:
        got : Local.Logical <- Local.at_head(h,ctx)
        emit(got,ctx,Local.number(h))
    case _: IO.die(Unit,1,"NO: segment-profile-sequence")
