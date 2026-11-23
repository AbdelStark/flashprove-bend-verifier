import Base

# Spike: read a file as a byte list, fold it as little-endian 64-bit words (two U32 limbs),
# XOR them together and count the words >= p = 2^64 - 2^32 + 1 (non-canonical field elements).
type Acc is Data:
  Acc{xh: U32, xl: U32, bad: U32, n: U32}

def nz(+v: U32) -> U32:
  U32.shrn(U32.or(v, U32.sub(0, v)), 31n)

def step(+xh: U32, +xl: U32, +bad: U32, +n: U32, +b0: U32, +b1: U32, +b2: U32, +b3: U32, +b4: U32, +b5: U32, +b6: U32, +b7: U32) -> Acc:
  +lo = U32.or(U32.or(b0, U32.shln(b1, 8n)), U32.or(U32.shln(b2, 16n), U32.shln(b3, 24n)))
  +hi = U32.or(U32.or(b4, U32.shln(b5, 8n)), U32.or(U32.shln(b6, 16n), U32.shln(b7, 24n)))
  +ge = U32.and(U32.sub(1, nz(U32.add(hi, 1))), nz(lo))
  Acc{U32.xor(xh, hi), U32.xor(xl, lo), U32.add(bad, ge), U32.add(n, 1)}

def go(xs: List<&2, U32>, acc: Acc) -> Acc:
  match xs:
    case Con{b0, Con{b1, Con{b2, Con{b3, Con{b4, Con{b5, Con{b6, Con{b7, t}}}}}}}}:
      Acc{xh, xl, bad, n} = acc
      go(t, step(xh, xl, bad, n, b0, b1, b2, b3, b4, b5, b6, b7))
    case _:
      acc

def show(a: Acc) -> String:
  Acc{xh, xl, bad, n} = a
  U32.show(xh) ++ " " ++ U32.show(xl) ++ " bad=" ++ U32.show(bad) ++ " n=" ++ U32.show(n)

def got(m: File & Result<&1, &1, (U32 & String), List<&2, U32>>) -> IO(Unit):
  (f, r) = m
  do IO<Unit>:
    xs : List<&2, U32> <- IO.pass(List<&2, U32>, r)
    u : Unit <- IO.print(show(go(xs, Acc{0, 0, 0, 0})))
    File.close(f)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{path, rest}}:
      do IO<Unit>:
        f : File <- IO.try(File, File.open(path, "r"))
        m : File & Result<&1, &1, (U32 & String), List<&2, U32>> <- File.read_bytes(f, 2147483647)
        got(m)
    case _:
      IO.print("usage: parse FILE")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
