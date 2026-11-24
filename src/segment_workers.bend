import Base

# The segment algebra is expressed in IO for early refusals. Its inputs are
# values in memory. Evaluate it to an operation, then replay that operation
# in transcript order so a sibling cannot print a later failure first.
def observe(~A: Data,action: IO(A)) -> IO.OP<A>:
  action(A,x => Emit{x})

def result(~A: Data,checked: IO.OP<A>) -> IO(A):
  match checked:
    case Emit{x}: IO.pure(A,x)
    case Halt{code,msg}: IO.die(A,code,msg)
    case Exit{code}: R => k => Exit{code}
