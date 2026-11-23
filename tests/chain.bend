import Base
import ../src/chain.bend as Chain

def show(value: Chain.Bits64) -> String:
  Chain.Bits64{hi, lo} = value
  U32.show(hi) ++ " " ++ U32.show(lo)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show(Chain.position(4294967295, 4294967295, 0n)))
    IO.print(show(Chain.position(4294967295, 4294967295, 31n)))
    IO.print(show(Chain.position(4294967295, 4294967295, 32n)))
    IO.print(show(Chain.position(4294967295, 42, 33n)))
    IO.print(show(Chain.position(4294967295, 42, 63n)))
    IO.print(U32.show(Chain.has_work(4294967295, 1, 0n)))
    IO.print(U32.show(Chain.has_work(4294967295, 1, 1n)))
    IO.print(U32.show(Chain.has_work(1, 0, 32n)))
    IO.print(U32.show(Chain.has_work(1, 0, 33n)))
    IO.print(U32.show(Chain.has_work(2147483648, 0, 63n)))
    IO.print(U32.show(Chain.has_work(2147483648, 0, 64n)))
    IO.print(U32.show(Chain.has_work(0, 0, 64n)))
    IO.print(U32.show(Chain.has_work(0, 0, 65n)))
    IO.print(U32.show(Chain.field_candidate(0, 0)))
    IO.print(U32.show(Chain.field_candidate(4294967294, 4294967295)))
    IO.print(U32.show(Chain.field_candidate(4294967295, 0)))
    IO.print(U32.show(Chain.field_candidate(4294967295, 1)))
    IO.print(U32.show(Chain.field_candidate(4294967295, 4294967295)))

#|0 0
#|0 2147483647
#|0 4294967295
#|1 42
#|2147483647 42
#|1
#|0
#|1
#|0
#|1
#|0
#|1
#|0
#|1
#|1
#|1
#|0
#|0
