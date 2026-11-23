import Base
import ../../src/segment_head.bend as Head
import ../../src/segment_inputs.bend as Inputs
import ../../src/segment_model.bend as M
import ../../src/lin_own.bend as Own
import ../../src/plan_types.bend as PT
import ../../src/fold.bend as F
import ./attention_projection.bend as Parts
import ./segment_projection.bend as Out

def rows(xs: M.Equations) -> IO(Unit):
  match xs:
    case []: IO.pure(Unit,Unit{})
    case M.Aff{r,m,t} <> tail:
      do IO<Unit>:
        ok : Unit <- IO.print("head-row " ++ Out.print(t) ++ " " ++ Out.print(Out.dot(m,F.zero())) ++ " " ++ Out.print(Parts.reads(r,F.zero())))
        rows(tail)

def emit(p: Head.Prepared) -> IO(Unit):
  Head.Prepared{a,b,fs,n,free,Own.Pending{ws,psi,mask,y}} = p
  do IO<Unit>:
    ra : Unit <- rows(a)
    rb : Unit <- rows(b)
    IO.print("head-functions " ++ Nat.show(n) ++ " " ++ Nat.show(free) ++ " " ++ Out.print(Parts.tables(fs,F.zero())) ++ " " ++
      Out.print(Parts.terms(ws,F.zero())) ++ " " ++ Out.print(Out.values(psi,F.zero())) ++ " " ++ Out.print(y))

def groups(xs: Inputs.Batches,+p: PT.Profile) -> IO(Unit):
  match xs:
    case [x]:
      do IO<Unit>:
        result : Head.Prepared <- Head.compute(x,p)
        emit(result)
    case _ <> tail: groups(tail,p)
    case _: IO.die(Unit,1,"missing output head")
