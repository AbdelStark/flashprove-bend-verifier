import Base
import ../src/hash_bytes.bend as H
import ../src/record_seeds.bend as Seed

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(H.hex(Seed.value(Seed.base(6n, [0,4294967295]))))
    _ : Unit <- IO.print(H.hex(Seed.value(Seed.base(6n, [1,4294967295, 7,0]))))
    _ : Unit <- IO.print(H.hex(Seed.value(Seed.base(6n, List.replicate(U32, 12n, 4294967295)))))
    _ : Unit <- IO.print(H.hex(Seed.factor(Seed.element(List.replicate(U32, 12n, 0)))))
    IO.print(H.hex(Seed.factor(Seed.element([0,0,0,0,0,0, 7,1,2,3,4,5]))))

#|00000000ffffffff
#|0700000000000000
#|0000000000000000
#|010000000000000000000000000000000000000000000000
#|070000000100000002000000030000000400000005000000
