import Base
import ./commitment.bend as Commitment

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_, config, ivk]:
      do IO<Unit>:
        id : String <- Commitment.compute(config, ivk)
        IO.print(id)
    case _: IO.die(Unit, 2, "usage: commitment_cli CONFIG IVK")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
