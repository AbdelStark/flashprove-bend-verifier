import Base
import ../../src/leaf_stage.bend as Leaf
import ../../src/leaf_batch.bend as Batch
import ../../src/leaf_check.bend as Check
import ../../src/key_stage.bend as Key
import ../../src/commitment.bend as Commitment
import ../../src/hash_bytes.bend as H
import ../../src/fold.bend as F
import ../../src/sumcheck.bend as E
import ../../src/header.bend as Header

def read(key: Key.AttestedKey, path: String, config: H.Bytes, plans: String) -> IO(Leaf.Trace):
  Key.AttestedKey{root,answers,_,_,_,session} = key
  Leaf.inspect(path,config,plans,Leaf.Table{root,answers},session)

def rho(trace: Check.Checked) -> String:
  Check.Checked{_,_,bytes} = trace
  H.hex(bytes)

def modified(change: Bool, batch: Batch.Prepared) -> Batch.Prepared:
  match change:
    case False{}: batch
    case True{}:
      Batch.Prepared{F.Claim{form,mask,target},rounds} = batch
      Batch.Prepared{F.Claim{form,mask,E.add(target,F.one())},rounds}

def judge(trace: Leaf.Trace, cfg: H.Bytes, change: Bool) -> IO(Check.Checked):
  Leaf.Trace{+shape,a,+b,rounds,session,digest} = trace
  do IO<Check.Checked>:
    batch : Batch.Prepared <- Batch.prepare(shape,a,b,rounds,cfg)
    Check.finish(modified(change,batch),shape,b,session,digest)

def inspect(+plans: String, config: String, key: String, leaf: String, change: Bool) -> IO(Unit):
  do IO<Unit>:
    +cfg : H.Bytes <- Commitment.configuration(config)
    table : Key.AttestedKey <- Key.check_transcript(key,cfg,plans)
    trace : Leaf.Trace <- read(table,leaf,cfg,plans)
    result : Check.Checked <- judge(trace,cfg,change)
    IO.print("leaf-link " ++ rho(result))

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,plans,config,key,leaf]: inspect(plans,config,key,leaf,False{})
    case [_,mode,plans,config,key,leaf]:
      do IO<Unit>:
        ok : Unit <- Header.require(String.eq(mode,"--changed-batch-target"),"NO: probe-option")
        inspect(plans,config,key,leaf,True{})
    case _: IO.die(Unit,2,"usage: leaf-stage [--changed-batch-target] PLANS CONFIG KEY LEAF")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
