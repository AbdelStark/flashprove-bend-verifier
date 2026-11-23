import Base
import ../../src/segment_ff.bend as G
import ../../src/segment_model.bend as M
import ../../src/segment_inputs.bend as Inputs
import ../../src/plan_types.bend as P
import ../../src/lin_own.bend as Own
import ../../src/extension.bend as X
import ../../src/fold.bend as F
import ./segment_projection.bend as Out
import ./attention_projection.bend as Projection

def emit(result:G.Prepared) -> IO(Unit):
  G.Prepared{pre,post,tables,used,free,Own.Pending{weights,point,_,target}} = result
  do IO<Unit>:
    prefix : X.E3 <- Projection.rows(pre,F.zero())
    suffix : X.E3 <- Projection.rows(post,F.zero())
    before : Unit <- IO.print("ff-prefix " ++ Nat.show(used) ++ " " ++ Out.print(prefix) ++ " " ++ Out.print(Projection.tables(tables,F.zero())))
    IO.print("ff-carried " ++ Nat.show(free) ++ " " ++ Out.print(suffix) ++ " " ++
      Out.print(Projection.terms(weights,F.zero())) ++ " " ++ Out.print(Out.values(point,F.zero())) ++ " " ++ Out.print(target))

def groups(xs:Inputs.Batches,+p:P.Profile) -> IO(Unit):
  match xs:
    case g <> _ <> tail:
      do IO<Unit>:
        data : G.Prepared <- G.compute(g,p)
        ok : Unit <- emit(data)
        groups(tail,p)
    case _: IO.pure(Unit,Unit{})
