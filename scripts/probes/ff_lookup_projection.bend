import Base
import ../../src/u3_cells.bend as Cells
import ../../src/ff_lookup.bend as Lookup
import ../../src/ff_shape.bend as G
import ../../src/ff_catalog.bend as Catalog
import ../../src/segment_inputs.bend as I
import ../../src/segment_attention_aff.bend as A
import ../../src/segment_model.bend as M
import ../../src/key_stage_lookup.bend as Int
import ../../src/extension.bend as X
import ../../src/fold.bend as F
import ../../src/sumcheck.bend as E
import ../../src/head_catalog.bend as C
import ../../src/plan_types.bend as PT
import ./segment_projection.bend as Out

def project(xs: List<&2,Cells.Cell>, a: X.E3) -> X.E3:
  match xs:
    case []: a
    case Cells.Cell{i,w} <> tail: project(tail,E.add(a,Int.power(32n,i,A.nat(3n),w)))

def show(row: A.Aff) -> IO(Unit):
  A.Aff{cs,ms,t} = row
  IO.print("ff-join " ++ Out.print(E.negate(t)) ++ " " ++ Out.print(Out.dot(ms,F.zero())) ++ " " ++ Out.print(project(cs,F.zero())))

def link(x: M.Inputs,p: PT.Profile) -> IO(Unit):
  M.Inputs{+j,f,_,_,st,shape,_} = x
  do IO<Unit>:
    s : G.Shape <- Catalog.shape(C.lt(C.select(p)),Nat.is_eq(j,0n))
    a : A.Aff <- Lookup.join(s,j,f,st,shape)
    show(a)

def groups(xs:I.Batches,+p:PT.Profile) -> IO(Unit):
  match xs:
    case x <> _ <> tail:
      do IO<Unit>:
        ok : Unit <- link(x,p)
        groups(tail,p)
    case _: IO.pure(Unit,Unit{})
