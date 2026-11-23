import Base
import ./hashlib.bend as Kernel
import ./hash_bytes.bend as H

# R15.3. K uses BLAKE2b-512's initial state, both halves of its counter
# and the first eight U32s of its output.
def blocks(left: Nat, +words: H.Bytes, +length: U32, +tag: U32,
  +done: U32, state: Kernel.H8) -> H.Bytes:
  match left:
    case 0n:
      pad = Nat.sub(32n, List.length(&2, U32, words))
      block = List.append(&2, U32, words, H.zero(pad))
      high = U32.shrn(length, 30n)
      low = U32.shln(length, 2n)
      last = H.compress_counter(block, state, high, low, length, tag, 4294967295)
      H.u32s(H.output(last, 32))
    case 1n+p:
      +used = U32.add(done, 32)
      block = List.take(&2, U32, words, 32n)
      next = H.compress_counter(block, state, U32.shrn(used, 30n), U32.shln(used, 2n), length, tag, 0)
      blocks(p, List.drop(&2, U32, words, 32n), length, tag, used, next)

def k(tag: U32, +words: H.Bytes) -> H.Bytes:
  +n = List.length(&2, U32, words)
  blocks(Nat.div(Nat.sub(n, 1n), 32n), words, U32.from_nat(n), tag, 0, H.initial(H.zero(8n), 64))

def pieces(count: Nat, +tag: U32, +words: H.Bytes) -> H.Bytes:
  match count:
    case 0n: []
    case 1n+p:
      List.append(&2, U32, k(tag, List.take(&2, U32, words, 128n)),
        pieces(p, tag, List.drop(&2, U32, words, 128n)))

# Each internal piece combines up to sixteen digests. Use a decreasing
# depth budget so the Bend checker can see termination.
def tree(depth: Nat, tag: U32, +words: H.Bytes) -> H.Bytes:
  match depth:
    case 0n: k(tag, words)
    case 1n+p:
      count = Nat.div(Nat.add(List.length(&2, U32, words), 127n), 128n)
      tree(p, 11, pieces(count, tag, words))

def depth(leaves: Nat) -> Nat:
  match leaves:
    case 0n: 0n
    case 1n: 0n
    case 2n+p: Nat.div(Nat.add(U32.log2(U32.from_nat(Nat.add(p, 1n))), 4n), 4n)

def tk(+words: H.Bytes) -> H.Bytes:
  leaves = Nat.div(Nat.add(List.length(&2, U32, words), 127n), 128n)
  tree(depth(leaves), 10, words)
