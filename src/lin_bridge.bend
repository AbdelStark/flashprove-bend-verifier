import Base
import ./lin_shared.bend as Lin
import ./key_stage_walk.bend as W
import ./wire_reader.bend as R
import ./leaf_stage.bend as L
import ./plan.bend as P
import ./hash_bytes.bend as H

type Shared is Data:
  Shared{end: W.End, adopted: Lin.Adopted}

def check(trace: R.Reader & W.Traced, plan: P.Plan, table: L.Table, cfg: H.Bytes) -> IO(R.Reader & Shared):
  (r,W.Traced{end,events,_}) = trace
  P.Plan{_,_,_,items} = plan
  do IO<R.Reader & Shared>:
    adopted : Lin.Adopted <- Lin.check(events,items,table,cfg)
    return (r,Shared{end,adopted})
