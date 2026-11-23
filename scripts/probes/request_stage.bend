import Base
import ../../src/request_stage.bend as Q
import ../../src/policy_statement.bend as S
import ../../src/policy_config.bend as C
import ../../src/header.bend as Header
import ../../src/key_stage.bend as Key
import ../../src/leaf_stage.bend as Leaf
import ../../src/hash_bytes.bend as H
import ../../src/opening_bytes.bend as O

def print_trace(trace: Q.Trace) -> IO(Unit):
  Q.Trace{slot,root,first,shared,rho,_} = trace
  IO.print(Nat.show(slot) ++ " " ++ H.hex(O.digest_bytes(root)) ++ " " ++ H.hex(first) ++ " " ++ H.hex(shared) ++ " " ++ H.hex(rho))

def proof(trace: Leaf.Trace, cfg: C.Configured, stmt: S.Statement, path: String, copy: U32, plans: String) -> IO(Unit):
  Leaf.Trace{_,_,checked,_,session,_} = trace
  do IO<Unit>:
    checked : Q.Trace <- Q.inspect(path,copy,stmt,cfg,plans,checked,session)
    print_trace(checked)

def entry(key: Key.AttestedKey, +cfg: C.Configured, stmt: S.Statement, +ivk: String, +path: String, +plans: String) -> IO(Unit):
  Key.AttestedKey{root,answers,_,_,_,session} = key
  C.Configured{digest,_} = cfg
  do IO<Unit>:
    h : H.Bytes <- Header.bytes(path,12)
    +copy : U32 <- Header.leaf_index(h)
    data : Leaf.Trace <- Leaf.inspect(ivk ++ "/leaf/" ++ U32.show(copy) ++ ".bin",digest,plans,Leaf.Table{root,answers},session)
    proof(data,cfg,stmt,path,copy,plans)

def digest(cfg: C.Configured) -> H.Bytes:
  C.Configured{d,_} = cfg
  d

def stage(+folder: String, path: String, r: String, y: String, tables: String, +plans: String, named: Maybe<&2,String>) -> IO(Unit):
  +config = folder ++ "/config"
  +ivk = folder ++ "/ivk"
  do IO<Unit>:
    +stmt : S.Statement <- S.load(config,r,y,tables,named)
    +cfg : C.Configured <- C.load(stmt,config,plans)
    key : Key.AttestedKey <- Key.check_transcript(ivk ++ "/key.bin",digest(cfg),plans)
    entry(key,cfg,stmt,ivk,path,plans)

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,folder,path,r,y,tables,plans]: stage(folder,path,r,y,tables,plans,None{})
    case [_,folder,path,r,y,tables,plans,named]: stage(folder,path,r,y,tables,plans,Some{named})
    case _: IO.die(Unit,2,"usage: request_stage EXAMPLE PROOF REQUEST Y TABLES PLANS [POLICY]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
