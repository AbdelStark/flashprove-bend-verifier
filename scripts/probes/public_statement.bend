import Base
import ../../src/policy_statement.bend as S
import ../../src/hash_bytes.bend as H
import ../../src/result.bend as R
import ../../src/plan_types.bend as P
import ../../src/policy.bend as Policy
import ../../src/head_coverage.bend as Head

def word_bytes(words: H.Bytes) -> H.Bytes:
  match words:
    case []: []
    case w <> ws: List.append(&2,U32,H.le(w),word_bytes(ws))

def emit(xs: S.Statement) -> IO(Unit):
  S.Statement{words, _, _, _, _, _, _, _} = xs
  IO.print(H.hex(word_bytes(words)))

# Test-only output for the head's winners on alternative caller intervals.
def details(p:Head.Covered) -> IO(Unit):
  Head.Covered{_,_,_,cs} = p
  IO.print("winners " ++ H.hex(word_bytes(cs)))

def winners(st:S.Statement,t:Nat) -> IO(Unit):
  S.Statement{_,+req,y,_,_,_,_,_} = st
  +len = t
  do IO<Unit>:
    p : Head.Covered <- Head.checked(List.drop(&2,U32,req,len),req,y,len)
    details(p)

def profile(st:S.Statement) -> IO(P.Profile):
  S.Statement{_,_,_,_,_,_,_,lines} = st
  do IO<P.Profile>:
    price : U32 <- Policy.field(lines,"C")
    return Bool.pick(P.Profile,U32.is_eq(price,256),P.SmallExact{},P.SmallClipped{})

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_,"coverage",config,req,y,tables,id,build,+named]:
      +opt = Bool.pick(Maybe<&2,String>,String.eq(named,"-"),None{},Some{named})
      do IO<Unit>:
        +value : S.Statement <- S.load(config,req,y,tables,opt)
        log : Unit <- winners(value,64n)
        prof : P.Profile <- profile(value)
        R.result(value,Some{prof},id,0,build)
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
