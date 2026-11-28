import Base
import ../src/hash_bytes.bend as H
import ../src/hashlib.bend as Kernel

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

# The block reader that update used before it streamed: it counts the input
# first, then compresses every block that a byte follows. Kept as the reference.
type Block is Data:
  Block{words: H.Bytes, rest: H.Bytes}

def read_block(n: Nat, src: H.Bytes, rev: H.Bytes) -> Block:
  match n src:
    case 1n+k a <> b <> c <> d <> tail:
      read_block(k,tail,(a + U32.shln(b,8n) + U32.shln(c,16n) + U32.shln(d,24n) : U32) <> rev)
    case _ tail: Block{List.reverse(&2,U32,rev),tail}

def absorb_more(n: Nat, state: Kernel.H8, block: Block, +end: U32) -> H.Context:
  match n block:
    case 0n Block{words,rest}: H.Context{H.compress(words,state,end,0),rest,end}
    case 1n+k Block{words,rest}:
      absorb_more(k,H.compress(words,state,end,0),read_block(32n,rest,[]),U32.add(end,128))

def absorb(count: Nat, state: Kernel.H8, src: H.Bytes, offset: U32) -> H.Context:
  match count:
    case 0n: H.Context{state,src,offset}
    case 1n+k: absorb_more(k,state,read_block(32n,src,[]),U32.add(offset,128))

def ref_update(ctx: H.Context, bytes: H.Bytes) -> H.Context:
  H.Context{state, tail, offset} = ctx
  +src = H.cat([tail, bytes])
  absorb(Nat.div(Nat.sub(H.length(src), 1n), 128n), state, src, offset)

def ref_finish(ctx: H.Context) -> H.Bytes:
  H.Context{state, +tail, offset} = ctx
  +len = H.length(tail)
  padded = H.cat([tail, List.replicate(U32, Nat.sub(128n, len), 0)])
  H.output(H.compress(H.u32s(padded), state, U32.add(offset, U32.from_nat(len)), 4294967295), 64)

def equal(xs: H.Bytes, ys: H.Bytes) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case Con{x,xt} Con{y,yt}: U32.is_eq(x,y) && equal(xt,yt)
    case _ _: False{}

# Every total length 0..299 in two updates split at n mod 131 and in three
# updates, against the reference, on the internal state and the 64-byte output.
def agrees(+n: Nat) -> Bool:
  +a = Nat.mod(n,131n)
  +b = Nat.sub(n,a)
  +c = Nat.div(b,2n)
  two = equal(H.finish(H.update(H.update(H.start(169,2),pattern(a,11)),pattern(b,59)),64),
    ref_finish(ref_update(ref_update(H.start(169,2),pattern(a,11)),pattern(b,59))))
  three = equal(H.finish(H.update(H.update(H.update(H.start(7,1),pattern(c,3)),pattern(a,5)),pattern(Nat.sub(b,c),9)),64),
    ref_finish(ref_update(ref_update(ref_update(H.start(7,1),pattern(c,3)),pattern(a,5)),pattern(Nat.sub(b,c),9))))
  two && three

def mismatches(n: Nat, +acc: Nat) -> Nat:
  match n:
    case 0n: acc
    case 1n+(+k): mismatches(k,Bool.pick(Nat,agrees(k),acc,1n+acc))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(0n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(111n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(112n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(113n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(240n))))
    _ : Unit <- IO.print(H.hex(H.plain(169, 2, H.zero(241n))))
    _ : Unit <- IO.print(H.hex(streamed()))
    IO.print("stream mismatches: " ++ Nat.show(mismatches(300n,0n)))

#|eab20f466f130865694011275be06978167d29e8c8a0f5842588952eae4bbae8
#|e75f798ed38c90e9a3e582272ea242cb73198e9c255237d5be50fbc31c68ba30
#|3ef19e47b98450e215b13a2dfacb2d825a4ce3770dfcbf6632de3d0049c1a3ba
#|7668eb4af791af352c66788469d7b247f9f34878a5f8ccc97caf27bb79e1f361
#|c037c153c757fa17bf808c9f1c70783bc6dc89d5f7cccd32cf456583a0c46d47
#|f96324d3313100740a240b4283e9c2c28d56b555c2dc3c309ef902f1a4d83de0
#|b06b5a3e4706d93908bd26c61f401a6ce6a65d49b630e14992f1ec62e2ec9591
#|stream mismatches: 0
