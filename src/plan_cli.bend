import Base
import ./plan.bend as Plan
import ./plan_types.bend as P
import ./hash_bytes.bend as H
import ./commitment.bend as Commitment

def summary(plan: Plan.Plan, name: String) -> String:
  Plan.Plan{digest,_,rounds,_} = plan
  name ++ " " ++ Nat.show(List.length(&2, Plan.Round, rounds)) ++ " " ++ H.hex(digest)

def inspect(chains: List<&2, P.Chain>, +hash: H.Bytes, +dir: String) -> IO(Unit):
  match chains:
    case []: IO.pure(Unit, Unit{})
    case +head <> tail:
      do IO<Unit>:
        plan : Plan.Plan <- Plan.load(hash, head, dir)
        printed : Unit <- IO.print(summary(plan, P.stem(head)))
        inspect(tail, hash, dir)

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_, dir, config]:
      do IO<Unit>:
        digest : H.Bytes <- Commitment.configuration(config)
        inspect([P.KeyOnce{},P.KeyShared{},P.KeySecond{},P.Entry{},P.RequestFirst{},P.RequestShared{},P.RequestSecond{}], digest, dir)
    case _: IO.die(Unit, 2, "usage: inspect-plans PLAN_DIRECTORY CONFIG")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
