import Base
import ../../src/key_stage.bend as Key
import ../../src/hash_bytes.bend as H
import ../../src/commitment.bend as Commitment

import ../../src/key_stage_walk.bend as W
import ../../src/key_stage_wf.bend as WF
import ../../src/key_stage_lookup_rows.bend as L
import ../../src/key_stage_range_check.bend as Range
import ../../src/lin_own.bend as Lin
import ../../src/wire_reader.bend as R
import ../../src/fold.bend as F
import ../../src/sumcheck.bend as E

def describe(key: Key.AttestedKey) -> String:
  Key.AttestedKey{_,_,one,shared,rho,_} = key
  "key-transcript " ++ H.hex(one) ++ " " ++ H.hex(shared) ++ " " ++ H.hex(rho)

def changed_row(stage: WF.Stage) -> IO(WF.Stage):
  match stage:
    case WF.Rows{m,L.Row{terms,masks,target} <> tail,parts,n,k}:
      IO.pure(WF.Stage,WF.Rows{m,L.Row{terms,masks,E.add(target,F.one())} <> tail,parts,n,k})
    case _: IO.die(WF.Stage,2,"probe needs a derived lookup row")

def range_fault(pair: R.Reader & Key.FirstChain) -> IO(Unit):
  (r,Key.FirstChain{W.Traced{_,events,ranges},_,_,_,_,_}) = pair
  do IO<Unit>:
    done : Unit <- R.close(r)
    changed : WF.Stage <- changed_row(ranges)
    Range.verify(changed,events)

# Perturb the coefficient of the first tensor in g. All on-disk data and all sampled values stay fixed.
def changed_dot(first: Lin.First) -> IO(Lin.First):
  match first:
    case Lin.First{Lin.Pending{F.Term{t,fs} <> tail,psi,mask,target},opened}:
      IO.pure(Lin.First,Lin.First{Lin.Pending{F.Term{E.add(t,F.one()),fs} <> tail,psi,mask,target},opened})
    case _: IO.die(Lin.First,2,"probe needs a derived matrix form")

def dot_fault(pair: R.Reader & Key.FirstChain, plans: String) -> IO(Unit):
  (r,+input) = pair
  do IO<Unit>:
    pending : Lin.First <- Key.matrix(input)
    changed : Lin.First <- changed_dot(pending)
    key : Key.AttestedKey <- Key.bind_claim(r,input,plans,changed)
    IO.print(describe(key))

def inject(mode: String, once: R.Reader & Key.FirstChain, plans: String) -> IO(Unit):
  match mode:
    case "--changed-range-target": range_fault(once)
    case "--changed-dot-weight": dot_fault(once,plans)
    case _: IO.die(Unit,2,"unknown probe mode")

def fault(mode: String, +plans: String, config: String, path: String) -> IO(Unit):
  do IO<Unit>:
    hash : H.Bytes <- Commitment.configuration(config)
    once : R.Reader & Key.FirstChain <- Key.open_once(path,hash,plans)
    inject(mode,once,plans)

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,plans,config,path]:
      do IO<Unit>:
        hash : H.Bytes <- Commitment.configuration(config)
        result : Key.AttestedKey <- Key.check_transcript(path,hash,plans)
        IO.print(describe(result))
    case [_,mode,plans,config,path]: fault(mode,plans,config,path)
    case _: IO.die(Unit,2,"usage: key-stage [--changed-range-target|--changed-dot-weight] PLANS CONFIG KEY")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
