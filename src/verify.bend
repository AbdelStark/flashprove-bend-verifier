import Base
import ./header.bend as Header
import ./commitment.bend as Commitment

# Replace this process to preserve the whole verifier's result and exit status.
def Backend.exec() -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/exec_verifier.c"
  import "./native/exec_verifier.js"

def usage() -> IO(Unit):
  IO.die(Unit, 2, "usage: verify CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-j N] [-q]")

# The whole-call worker validates option values. This parser restricts the
# reachable modes and requires the caller's commitment ID exactly once.
def options(args: List<String>, id: Maybe<&2, String>) -> Maybe<&2, String>:
  match args id:
    case [] value: value
    case "-q" <> tail value: options(tail, value)
    case "-j" <> count <> tail value: options(tail, value)
    case "-policy" <> policy <> tail value: options(tail, value)
    case "-id" <> digest <> tail None{}: options(tail, Some{digest})
    case _ _: None{}

def whole(+config: String, +ivk: String, request: String, y: String, proof: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    checked : Unit <- Header.check(config, ivk, proof, request, y)
    id : String <- Commitment.compute(config, ivk)
    bound : Unit <- Header.require(String.eq(id, String.to_lower(expected)), "NO: model-statement")
    IO.try(Unit, Backend.exec())

def valid_call(id: Maybe<&2, String>, ordinary: Bool, config: String,
  ivk: String, request: String, y: String, proof: String) -> IO(Unit):
  match id ordinary:
    case Some{expected} True{}: whole(config, ivk, request, y, proof, expected)
    case _ _: usage()

def run(args: List<String>) -> IO(Unit):
  match args:
    case _ <> +config <> ivk <> request <> y <> proof <> tail:
      valid_call(options(tail, None{}), Bool.not(String.starts_with(config, "-")),
        config, ivk, request, y, proof)
    case _: usage()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
