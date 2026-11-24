import Base
import ../../src/u3_series.bend as U
import ../../src/segment_inputs.bend as Inputs
import ../../src/segment_attention.bend as Attention
import ../../src/segment_attention_aff.bend as A
import ../../src/segment_model.bend as Model
import ../../src/key_stage_lookup_rows.bend as L
import ../../src/fold.bend as F
import ../../src/extension.bend as X
import ../../src/sumcheck.bend as E
import ./segment_projection.bend as Output

# Evaluate each coefficient vector at U3[j] = 3^j. Factorization avoids
# allocating its entire dense table. Independently assign mask[j] = j+1.
def factors(xs:F.Factors,+power:X.E3,acc:X.E3) -> X.E3:
  match xs:
    case []: acc
    case +factor <> tail:
      lo = F.at_bit(factor,False{})
      hi = F.at_bit(factor,True{})
      factors(tail,E.mul(power,power),E.mul(acc,E.add(lo,E.mul(power,hi))))
def terms(xs:F.Form,acc:X.E3) -> X.E3:
  match xs:
    case []: acc
    case F.Term{w,fs} <> tail: terms(tail,E.add(acc,factors(fs,A.nat(3n),w)))
def reads(xs:List<&2,Model.Read>,acc:X.E3) -> X.E3:
  match xs:
    case []: acc
    case Model.U3Run{_,s} <> tail: reads(tail,terms(U.expand(s),acc))
    case Model.Read{_,_,fs} <> tail: reads(tail,terms(fs,acc))
def rows(xs:Model.Equations,acc:X.E3) -> IO(X.E3):
  match xs:
    case []: IO.pure(X.E3,acc)
    case Model.Aff{e,m,t} <> tail:
      +v = Output.step(Output.step(t,Output.dot(m,F.zero())),reads(e,F.zero()))
      rows(tail,Output.step(acc,v))
def tables(xs:Model.Functionals,acc:X.E3) -> X.E3:
  match xs:
    case []: acc
    case Model.Functional{m,n,f,o} <> tail:
      v = Output.step(Output.step(Output.step(A.nat(m),A.nat(n)),A.nat(o)),terms(f,F.zero()))
      tables(tail,Output.step(acc,v))
def emit(p: Attention.Prepared) -> IO(Unit):
  Attention.Prepared{cs,fs,n} = p
  do IO<Unit>:
    digest : X.E3 <- rows(cs,F.zero())
    IO.print("attention " ++ Nat.show(n) ++ " " ++ Output.print(digest) ++ " " ++ Output.print(tables(fs,F.zero())))
def compute(x: Model.Inputs) -> IO(Unit):
  do IO<Unit>:
    result : Attention.Prepared <- Attention.compute(x)
    emit(result)
def groups(xs: Inputs.Batches) -> IO(Unit):
  match xs:
    case _ <> attention <> tail:
      do IO<Unit>:
        wrote : Unit <- compute(attention)
        groups(tail)
    case _: IO.pure(Unit,Unit{})
