import Base
import ../../src/key_stage.bend as Key
import ../../src/hash_bytes.bend as H
import ../../src/commitment.bend as Commitment

def describe(key: Key.AttestedKey) -> String:
  Key.AttestedKey{_,_,one,shared,rho,_} = key
  "key-transcript " ++ H.hex(one) ++ " " ++ H.hex(shared) ++ " " ++ H.hex(rho)

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,plans,config,path]:
      do IO<Unit>:
        hash : H.Bytes <- Commitment.configuration(config)
        result : Key.AttestedKey <- Key.check_transcript(path,hash,plans)
        IO.print(describe(result))
    case _: IO.die(Unit,2,"usage: key-stage PLANS CONFIG KEY")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
