import Base
import ../src/policy_hash.bend as K
import ../src/hash_bytes.bend as H

# FORMAT §12.6 prints U32 values in big-endian hex.
def show(xs: H.Bytes) -> String:
  match xs:
    case []: ""
    case +w <> ws: H.hex(List.reverse(&2, U32, H.le(w))) ++ show(ws)

def range(n: Nat, +start: U32) -> H.Bytes:
  match n:
    case 0n: []
    case 1n+p: start <> range(p, U32.add(start, 1))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(show(K.k(10, [])))
    _ : Unit <- IO.print(show(K.k(10, [7])))
    _ : Unit <- IO.print(show(K.k(10, [7,0])))
    _ : Unit <- IO.print(show(K.k(3, range(32n, 1))))
    _ : Unit <- IO.print(show(K.k(3, range(33n, 1))))
    _ : Unit <- IO.print(show(K.tk(range(8n, 1))))
    _ : Unit <- IO.print(show(K.tk(range(136n, 1))))
    IO.print(show(K.tk(range(2049n, 1))))

#|642033eebd8188a6b2b6dba3ad4e81de70b03c7d9bc86eec189b6da891098fc0
#|9199d8e76712b9d5a45ca6ffa7333389d9332b0a830f4274cc71888ff4dd0629
#|5270ece847c0c6e6215c895e003b513dc694c460d5091150f1a79692658fcb04
#|3d11700a6c1b3f588c605790c666049f2a3b0711fb1cdb03fc8cba0a088f932b
#|63879cbc0f65a48f466bbb5507fb9c4244a169c026ffae47fb3f0fa72bd88212
#|2c9ad89066617790478f356ad1401491956327cfb43ec51194e7ad7eb36bdbba
#|b790a9d3eb4b5173034538aa7d2ddd3ab7359b67c77b274469f8de7e5f0044b2
#|3323f7b96604ef89cbe4e3b4ae6641bb73ccc22b581b898b679d62882b68a13e
