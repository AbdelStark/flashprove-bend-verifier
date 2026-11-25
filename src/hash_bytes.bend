import Base
import ./hashlib.bend as Kernel

def Bytes() -> Data:
  List<&2, U32>

def cat(parts: List<&2, Bytes>) -> Bytes:
  match parts:
    case []: []
    case [last]: last
    case prefix <> rest:
      List.reverse.go(&2,U32,List.reverse(&2,U32,prefix),cat(rest))

def le(+x: U32) -> Bytes:
  [U32.and(x, 255), U32.and(U32.shrn(x, 8n), 255),
   U32.and(U32.shrn(x, 16n), 255), U32.shrn(x, 24n)]

def word(x: U32) -> Bytes:
  cat([le(x), [0,0,0,0]])

def length_go(bytes: Bytes, n: Nat) -> Nat:
  match bytes:
    case []: n
    case _ <> rest: length_go(rest,1n+n)

def length(bytes: Bytes) -> Nat:
  length_go(bytes,0n)

def take_rev(bytes: Bytes, n: Nat, acc: Bytes) -> Bytes:
  match bytes n:
    case Nil{} _: List.reverse(&2,U32,acc)
    case _ 0n: List.reverse(&2,U32,acc)
    case Con{x,rest} 1n+k: take_rev(rest,k,x <> acc)

def take(bytes: Bytes, n: Nat) -> Bytes:
  take_rev(bytes,n,[])

def u32s_rev(xs: Bytes, acc: Bytes) -> Bytes:
  match xs:
    case a <> b <> c <> d <> tail:
      u32s_rev(tail,(a + U32.shln(b,8n) + U32.shln(c,16n) + U32.shln(d,24n) : U32) <> acc)
    case [a,b,c]: List.reverse(&2,U32,(a + U32.shln(b,8n) + U32.shln(c,16n) : U32) <> acc)
    case [a,b]: List.reverse(&2,U32,(a + U32.shln(b,8n) : U32) <> acc)
    case [a]: List.reverse(&2,U32,a <> acc)
    case []: List.reverse(&2,U32,acc)

def u32s(xs: Bytes) -> Bytes:
  u32s_rev(xs,[])

def initial(start: List<&2, U32>, n: U32) -> Kernel.H8:
  match start:
    case [a,b,c,d,e,f,g,h]:
      Kernel.H8{1779033703, U32.xor(4072524040, n), 3144134277, 2227873595,
        1013904242, 4271175723, 2773480762, 1595750129,
        U32.xor(1359893119, b), U32.xor(2917565137, a), U32.xor(2600822924, d), U32.xor(725511199, c),
        U32.xor(528734635, f), U32.xor(4215389547, e), U32.xor(1541459225, h), U32.xor(327033209, g)}
    case _: Kernel.H8{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}

# B2b.compress expects the high limb first in both the state and message.
def compress_counter(block: List<&2, U32>, state: Kernel.H8, t0h: U32, t0l: U32,
  t1h: U32, t1l: U32, +flag: U32) -> Kernel.H8:
  match block:
    case [m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15,
          m16, m17, m18, m19, m20, m21, m22, m23, m24, m25, m26, m27, m28, m29, m30, m31]:
      Kernel.H8{h0, h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, h13, h14, h15} = state
      Kernel.B2b.compress(
        h0, h1, h2, h3, h4, h5, h6, h7,
        h8, h9, h10, h11, h12, h13, h14, h15,
        m1, m0, m3, m2, m5, m4, m7, m6,
        m9, m8, m11, m10, m13, m12, m15, m14,
        m17, m16, m19, m18, m21, m20, m23, m22,
        m25, m24, m27, m26, m29, m28, m31, m30,
        t0h, t0l, t1h, t1l, flag, flag)
    case _: state

def compress(block: List<&2, U32>, state: Kernel.H8, used: U32, flag: U32) -> Kernel.H8:
  compress_counter(block, state, 0, used, 0, 0, flag)

def output(state: Kernel.H8, n: U32) -> Bytes:
  Kernel.H8{h0, h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, h13, h14, h15} = state
  all = cat([le(h1), le(h0), le(h3), le(h2), le(h5), le(h4), le(h7), le(h6),
    le(h9), le(h8), le(h11), le(h10), le(h13), le(h12), le(h15), le(h14)])
  List.take(&2, U32, all, U32.to_nat(n))

type Context is Data:
  Context{state: Kernel.H8, tail: Bytes, offset: U32}

type Block is Data:
  Block{words: Bytes, rest: Bytes}

# A full BLAKE2b block has 32 little-endian words. Consume each byte once
# and return the suffix. update keeps the last 1..128 bytes for finalization.
def read_block(n: Nat, src: Bytes, rev: Bytes) -> Block:
  match n src:
    case 1n+k a <> b <> c <> d <> tail:
      w = (a + U32.shln(b,8n) + U32.shln(c,16n) + U32.shln(d,24n) : U32)
      read_block(k,tail,w <> rev)
    case _ tail: Block{List.reverse(&2,U32,rev),tail}

def absorb_more(n: Nat, state: Kernel.H8, block: Block, +end: U32) -> Context:
  match n block:
    case 0n Block{words,rest}: Context{compress(words,state,end,0),rest,end}
    case 1n+k Block{words,rest}:
      absorb_more(k,compress(words,state,end,0),read_block(32n,rest,[]),U32.add(end,128))

def absorb(count: Nat, state: Kernel.H8, src: Bytes, offset: U32) -> Context:
  match count:
    case 0n: Context{state,src,offset}
    case 1n+k: absorb_more(k,state,read_block(32n,src,[]),U32.add(offset,128))

def update(ctx: Context, bytes: Bytes) -> Context:
  Context{state, tail, offset} = ctx
  +src = cat([tail, bytes])
  count = Nat.div(Nat.sub(length(src), 1n), 128n)
  absorb(count, state, src, offset)

def finish_state(ctx: Context) -> Kernel.H8:
  Context{state, +tail, offset} = ctx
  +len = length(tail)
  padded = cat([tail, List.replicate(U32, Nat.sub(128n, len), 0)])
  compress(u32s(padded), state, U32.add(offset, U32.from_nat(len)), 4294967295)

def finish(ctx: Context, n: U32) -> Bytes:
  output(finish_state(ctx),n)

# R2.1. The caller supplies the two-word domain label and the 32-byte start value.
def digest(label: Bytes, start: Bytes, body: Bytes, +n: U32) -> Bytes:
  finish(update(Context{initial(u32s(start), n), label, 0}, body), n)

def zero(n: Nat) -> Bytes:
  List.replicate(U32, n, 0)

def start(number: U32, index: U32) -> Context:
  Context{initial(u32s(zero(32n)), 32), cat([word(number), word(index)]), 0}

def plain(number: U32, index: U32, body: Bytes) -> Bytes:
  digest(cat([word(number), word(index)]), zero(32n), body, 32)

def hex(xs: Bytes) -> String:
  match xs:
    case []: ""
    case +x <> tail:
      String.take(String.drop("0123456789abcdef", U32.to_nat(U32.shrn(x, 4n))), 1n) ++
        String.take(String.drop("0123456789abcdef", U32.to_nat(U32.and(x, 15))), 1n) ++ hex(tail)

def size(ctx: Context) -> Nat:
  Context{_, tail, offset} = ctx
  Nat.add(U32.to_nat(offset), length(tail))
