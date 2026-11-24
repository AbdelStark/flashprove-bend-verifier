import Base
import ../src/segment_stage.bend as Stage
import ../src/segment_geometry.bend as Geometry
import ../src/segment_tables.bend as Forest
import ../src/policy_tables.bend as Policy
import ../src/segment_workers.bend as Workers

# R11.1. An empty authenticated event list is too short for either action.
# Each action has a distinct refusal. The leftmost action must win for either
# order when two independent forest workers refuse in the same call.
def message(result: IO.OP<Stage.Groups>) -> String:
  match result:
    case Halt{1,message}: message
    case _: "unexpected result"

def refusal(actions: Geometry.Actions) -> String:
  +t: Policy.Table = Policy.Table{[],[]}
  message(Workers.observe(Stage.Groups,Stage.checks(actions,[],0n,Policy.Tables{t,t,t,t},[])))

def main() -> IO(Unit):
  +a: Geometry.Action = Geometry.TermsCoin{0n}
  +b: Geometry.Action = Geometry.Forest{0n,1n,0n,1n,Forest.Forest{0n,0n,0n,0n,[]}}
  IO.print(refusal([a,b]) ++ "\n" ++ refusal([b,a]))

#|NO: segment-terms-round
#|NO: short-segment-forest
