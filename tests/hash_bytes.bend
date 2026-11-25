import Base
import ../src/hash_bytes.bend as H

# hashlib.blake2b over two LE64 domain words followed by byte i = (37*i+11) mod 256.
# The three updates leave 127 bytes, then exactly one final block, then span two blocks.
def pattern(n: Nat, +byte: U32) -> H.Bytes:
  match n:
    case 0n: []
    case 1n+k: byte <> pattern(k,U32.and(U32.add(byte,37),255))

def streamed() -> H.Bytes:
  first = H.update(H.start(169,2),pattern(111n,11))
  second = H.update(first,pattern(1n,22))
  H.finish(H.update(second,pattern(273n,59)),32)

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(0n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(111n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(112n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(113n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(240n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(241n))))
    IO.print(H.hex(streamed()))

#|eab20f466f130865694011275be06978167d29e8c8a0f5842588952eae4bbae8
#|e75f798ed38c90e9a3e582272ea242cb73198e9c255237d5be50fbc31c68ba30
#|3ef19e47b98450e215b13a2dfacb2d825a4ce3770dfcbf6632de3d0049c1a3ba
#|7668eb4af791af352c66788469d7b247f9f34878a5f8ccc97caf27bb79e1f361
#|c037c153c757fa17bf808c9f1c70783bc6dc89d5f7cccd32cf456583a0c46d47
#|f96324d3313100740a240b4283e9c2c28d56b555c2dc3c309ef902f1a4d83de0
#|b06b5a3e4706d93908bd26c61f401a6ce6a65d49b630e14992f1ec62e2ec9591
