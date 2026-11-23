import Base

# FORMAT R6.6. A position keeps the low k bits of one little-endian transcript word.
type Bits64 is Data:
  Bits64{hi: U32, lo: U32}

def mask32(+bits: Nat) -> U32:
  # Limit the shift to 31 even on targets that wrap a 32-bit shift count.
  Bool.pick(U32, Nat.is_ge(bits, 32n), 4294967295,
    U32.sub(U32.shln(1, Nat.min(bits, 31n)), 1))

def position(hi: U32, lo: U32, +bits: Nat) -> Bits64:
  Bits64{U32.and(hi, mask32(Nat.sub(bits, 32n))), U32.and(lo, mask32(bits))}

def zero(value: Bits64) -> Bool:
  Bits64{hi, lo} = value
  U32.is_zero(U32.or(hi, lo))

# FORMAT R5.5. Call zero supplies the work word. Count 64 checks the entire word.
def has_work(hi: U32, lo: U32, +bits: Nat) -> U32:
  Bool.to_u32(Bool.and(Nat.is_le(bits, 64n), zero(position(hi, lo, bits))))

# FORMAT R6.3. Draws in F keep canonical words. Sampling retries on words >= p.
def field_candidate(hi: U32, lo: U32) -> U32:
  Bool.to_u32(Bool.or(U32.is_ne(hi, 4294967295), U32.is_zero(lo)))
