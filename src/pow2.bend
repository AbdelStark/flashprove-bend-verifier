import Base

# 2^k in at most two native operations, where Nat.pow(2n, k) makes k recursive products.
# The runtime's Nat holds up to 2^48 - 1, so exponents from 64 up keep Nat.pow, which fails
# there as it always did.
def wide(big: Bool, +k: Nat) -> Nat:
  match big:
    case True{}:
      Nat.mul(U32.to_nat(U32.shln(1, Nat.sub(k, 32n))), Nat.mul(65536n, 65536n))
    case False{}:
      Nat.pow(2n, k)

def pick(small: Bool, +k: Nat) -> Nat:
  match small:
    case True{}:
      U32.to_nat(U32.shln(1, k))
    case False{}:
      wide(Nat.is_lt(k, 64n), k)

def pow2(+k: Nat) -> Nat:
  pick(Nat.is_lt(k, 32n), k)
