import Base
import ../../src/policy_statement.bend as S
import ../../src/policy_config.bend as C
import ../../src/hash_bytes.bend as H
import ../../src/header.bend as Header

def output(value: C.Configured) -> IO(Unit):
  C.Configured{digest,_} = value
  IO.print(H.hex(digest))

def check(+config: String, req: String, y: String, tables: String, plans: String, claim: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    st : S.Statement <- S.load(config,req,y,tables,claim)
    cfg : C.Configured <- C.load(st,config,plans)
    output(cfg)

# Differential tests can replace the layout being checked while keeping the
# plan anchored to the separately loaded, genuine configuration.
def candidate(st: S.Statement, original: C.Configured, raw: H.Bytes) -> IO(Unit):
  C.Configured{digest,plan} = original
  C.verify_config(st,C.Snapshot{digest,raw},plan)

def altered(+config: String, req: String, y: String, tables: String, plans: String, replacement: String) -> IO(Unit):
  do IO<Unit>:
    +st : S.Statement <- S.load(config,req,y,tables,None{})
    cfg : C.Configured <- C.load(st,config,plans)
    raw : H.Bytes <- C.read_layout(replacement)
    candidate(st,cfg,raw)

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,mode,config,req,y,tables,plans,replacement]:
      do IO<Unit>:
        ok : Unit <- Header.require(String.eq(mode,"--candidate"), "unknown test mode")
        altered(config,req,y,tables,plans,replacement)
    case [_,config,req,y,tables,plans,policy]: check(config,req,y,tables,plans,Some{policy})
    case [_,config,req,y,tables,plans]: check(config,req,y,tables,plans,None{})
    case _: IO.die(Unit,2,"usage: public_layout CONFIG REQUEST Y TABLES PLANS [POLICY]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
