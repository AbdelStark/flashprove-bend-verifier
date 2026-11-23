import Base
import ./header.bend as Header

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_, config, ivk, proof, request, token]:
      Header.check(config, ivk, proof, request, token)
    case _: IO.die(Unit, 2, "usage: header_cli CONFIG IVK PROOF REQUEST Y")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
