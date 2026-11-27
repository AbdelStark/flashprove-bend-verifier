import Base
import ./src/goldilocks.bend as Gl

# Laws for the verifier's arithmetic kernels (REQ-ASSURE-5). Each law is a claim about the code
# in src/, stated over naturals. PROOF.bend proves each one; `make laws` checks them.
#
# Bend checks proofs by computing, and it writes a natural in unary. So a law never asks it to
# compute 2^32: it names pow2(32n) and leaves it unexpanded.

def pow2(n: Nat) -> Nat:
  match n:
    case 0n:
      1n
    case 1n+p:
      Nat.double(pow2(p))

# Limb law 1. The 32-bit sum s = a + b wraps, and Gl.carry(a, s) is the bit that was lost:
# s + carry * 2^32 = a + b.
law carry_exact:
  for +a: U32
  for +b: U32
  {Nat.add(U32.to_nat(U32.add(a, b)), Nat.mul(U32.to_nat(Gl.carry(a, U32.add(a, b))), pow2(32n)))
    == Nat.add(U32.to_nat(a), U32.to_nat(b)) : Nat}

# Limb law 2. The 32-bit difference d = a - b wraps, and Gl.borrow(a, b) says by how much:
# d + b = a + borrow * 2^32.
law borrow_exact:
  for +a: U32
  for +b: U32
  {Nat.add(U32.to_nat(U32.sub(a, b)), U32.to_nat(b))
    == Nat.add(U32.to_nat(a), Nat.mul(U32.to_nat(Gl.borrow(a, b)), pow2(32n))) : Nat}
