import Base
import ./leaf_stage.bend as L
import ./leaf_batch.bend as Batch
import ./leaf_shape.bend as S
import ./fold_verify.bend as F
import ./opening_bytes.bend as O
import ./hash_bytes.bend as H
import ./header.bend as Header

# R13.9-11. Provenance of the first table is supplied by the calling key stage.
type Checked is Data:
  Checked{table: L.Table, session: O.Session, rho: H.Bytes}

def finish(prepared: Batch.Prepared, shape: S.Shape, table: L.Table, session: O.Session, rho: H.Bytes) -> IO(Checked):
  Batch.Prepared{claim,rounds} = prepared
  do IO<Checked>:
    valid : Unit <- Header.require(F.verify(claim,shape,rounds),"NO: link-proximity")
    return Checked{table,session,rho}

def algebra(trace: L.Trace, config: H.Bytes) -> IO(Checked):
  L.Trace{+shape,anchor,+leaf,rounds,session,rho} = trace
  do IO<Checked>:
    prepared : Batch.Prepared <- Batch.prepare(shape,anchor,leaf,rounds,config)
    finish(prepared,shape,leaf,session,rho)
