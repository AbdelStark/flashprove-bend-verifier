import Base
import ./hash_bytes.bend as H

# R4.8, R5.4. The round label is 2^32, giving 2^48 + 162 in the hash label.
def queries(count: Nat, +rho: H.Bytes, +j: U32) -> H.Bytes:
  match count:
    case 0n: []
    case 1n+k:
      label = H.cat([H.le(162), H.le(65536), H.word(1)])
      tail = H.cat([H.word(U32.add(3, U32.shln(j, 16n))), H.word(0)])
      H.cat([H.digest(label, rho, tail, 64), queries(k, rho, U32.add(j, 1))])

type Draw is Data:
  Draw{bytes: H.Bytes, zero: Bool, rest: List<&2, U32>}

# R6.4. Goldilocks rejects a word exactly when its high limb is 2^32-1
# and its low limb is nonzero. Six misses yield zero.
def base(tries: Nat, xs: List<&2, U32>) -> Draw:
  match tries xs:
    case 0n rest: Draw{H.word(0), True{}, rest}
    case 1n+p 0 <> 4294967295 <> tail:
      Draw{H.cat([H.le(0), H.le(4294967295)]), False{}, tail}
    case 1n+p lo <> 4294967295 <> tail:
      base(p, tail)
    case 1n+p +lo <> +hi <> tail:
      Draw{H.cat([H.le(lo), H.le(hi)]), U32.is_zero(U32.or(lo, hi)), tail}
    case 1n+p _: Draw{H.word(0), True{}, []}

def third(draw: Draw, a: H.Bytes, b: H.Bytes, ab_zero: Bool) -> Draw:
  Draw{c, cz, rest} = draw
  Draw{H.cat([a,b,c]), ab_zero && cz, rest}

def middle(draw: Draw, a: H.Bytes, az: Bool) -> Draw:
  Draw{b, bz, rest} = draw
  third(base(6n, rest), a, b, az && bz)

def first(draw: Draw) -> Draw:
  Draw{a, az, rest} = draw
  middle(base(6n, rest), a, az)

def element(xs: List<&2, U32>) -> Draw:
  first(base(6n, xs))

def second(draw: Draw) -> H.Bytes:
  match draw:
    case Draw{_, True{}, _}: H.cat([H.word(1), H.zero(16n)])
    case Draw{value, False{}, _}: value

def factor(draw: Draw) -> H.Bytes:
  match draw:
    case Draw{_, True{}, rest}: second(element(rest))
    case Draw{value, False{}, _}: value

def value(draw: Draw) -> H.Bytes:
  Draw{v, _, _} = draw
  v

def rest(draw: Draw) -> H.Bytes:
  Draw{_, _, t} = draw
  t

def coordinates(count: Nat, xs: List<&2, U32>) -> H.Bytes:
  match count:
    case 0n: factor(element(xs))
    case 1n+k:
      +draw = element(xs)
      H.cat([value(draw), coordinates(k, rest(draw))])

# H821 admits exactly one answer per row (parameter file, line "answers").
def sample(+name: H.Bytes, +variables: Nat) -> H.Bytes:
  label = H.cat([H.word(160), H.le(0), H.le(1)])
  first = H.cat([H.zero(32n), H.word(112), name, H.word(0), H.word(0)])
  rho = H.digest(label, H.zero(32n), first, 32)
  # Skip the four words of the new chain value. A sampled element needs at
  # most 18 words and its nonzero factor may consume a second element.
  words = Nat.add(4n, Nat.mul(18n, Nat.add(variables, 2n)))
  blocks = Nat.div(Nat.add(words, 7n), 8n)
  values = List.drop(&2, U32, H.u32s(queries(blocks, rho, 0)), 8n)
  coordinates(variables, values)
