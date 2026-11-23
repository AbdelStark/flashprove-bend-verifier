import Base
import ./header.bend as Header
import ./commitment.bend as Commitment
import ./policy.bend as Policy

# Replace this process to preserve the whole verifier's result and exit status.
def Backend.exec() -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/exec_verifier.c"
  import "./native/exec_verifier.js"

def usage() -> IO(Unit):
  IO.die(Unit, 2, "usage: verify CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-j N] [-q]")

type Options is Data:
  Options{id: Maybe<&2, String>, policy: Maybe<&2, String>}

def options(args: List<String>, state: Options) -> Maybe<&2, Options>:
  match args state:
    case [] value: Some{value}
    case "-q" <> tail value: options(tail, value)
    case "-j" <> count <> tail value: options(tail, value)
    case "-policy" <> name <> tail Options{id, None{}}:
      options(tail, Options{id, Some{name}})
    case "-id" <> digest <> tail Options{None{}, policy}:
      options(tail, Options{Some{digest}, policy})
    case _ _: None{}

def valid_policy(named: Maybe<&2, String>) -> Bool:
  match named:
    case None{}: True{}
    case Some{text}: Policy.option_valid(text)

def whole(+config: String, +ivk: String, +request: String, y: String, proof: String, expected: String, named: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    checked : Unit <- Header.check(config, ivk, proof, request, y)
    policy : Unit <- Policy.check(config, request, named)
    id : String <- Commitment.compute(config, ivk)
    bound : Unit <- Header.require(String.eq(id, String.to_lower(expected)), "NO: model-statement")
    IO.try(Unit, Backend.exec())

def valid_options(opts: Maybe<&2, Options>) -> Bool:
  match opts:
    case Some{Options{_, named}}: valid_policy(named)
    case None{}: False{}

def valid_call(opts: Maybe<&2, Options>, ordinary: Bool, config: String,
  ivk: String, request: String, y: String, proof: String) -> IO(Unit):
  match opts ordinary:
    case Some{Options{Some{expected}, named}} True{}:
      whole(config, ivk, request, y, proof, expected, named)
    case _ _: usage()

def run(args: List<String>) -> IO(Unit):
  match args:
    case _ <> +config <> ivk <> request <> y <> proof <> tail:
      +opts = options(tail, Options{None{},None{}})
      valid_call(opts, valid_options(opts) && Bool.not(String.starts_with(config, "-")),
        config, ivk, request, y, proof)
    case _: usage()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
