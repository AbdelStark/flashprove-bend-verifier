import Base
import ../../src/policy_statement.bend as S
import ../../src/hash_bytes.bend as H

def word_bytes(words: H.Bytes) -> H.Bytes:
  match words:
    case []: []
    case w <> ws: List.append(&2,U32,H.le(w),word_bytes(ws))

def emit(xs: S.Statement) -> IO(Unit):
  S.Statement{words, _, _, _, _, _, _, _} = xs
  IO.print(H.hex(word_bytes(words)))

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,config,req,y,tables,policy]:
      do IO<Unit>:
        value : S.Statement <- S.load(config,req,y,tables,Some{policy})
        emit(value)
    case [_,config,req,y,tables]:
      do IO<Unit>:
        value : S.Statement <- S.load(config,req,y,tables,None{})
        emit(value)
    case _: IO.die(Unit,2,"usage: public_statement CONFIG REQUEST Y TABLES [POLICY]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
