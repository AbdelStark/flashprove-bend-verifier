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

def zero_words(n: U32) -> Bytes:
  List.replicate(U32, U32.to_nat(n), 0)

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

# Bytes of words given last word first, prepended to acc.
def unpack_rev(rev: Bytes, acc: Bytes) -> Bytes:
  match rev:
    case []: acc
    case +x <> tail:
      unpack_rev(tail, U32.and(x, 255) <> U32.and(U32.shrn(x, 8n), 255) <>
        U32.and(U32.shrn(x, 16n), 255) <> U32.shrn(x, 24n) <> acc)

# A full block is pending: compress it only if a byte follows.
def stream_last(rest: Bytes, rev: Bytes, state: Kernel.H8, +offset: U32) -> Context:
  match rest:
    case []: Context{state,unpack_rev(rev,[]),offset}
    case x <> tail:
      +end = U32.add(offset,128)
      Context{compress(List.reverse(&2,U32,rev),state,end,0),x <> tail,end}

# Read four bytes per step, holding up to j = 32 words of the current block
# (last word first). A full block is compressed only once a byte follows it,
# so the last 1..128 bytes stay for finalization. The walk recurses on the
# input itself, so it needs no length and never shares the input.
def stream(src: Bytes, j: U32, rev: Bytes, state: Kernel.H8, +offset: U32) -> Context:
  match src j:
    case a <> b <> c <> d <> tail 32:
      +end = U32.add(offset,128)
      stream(tail,1,[(a + U32.shln(b,8n) + U32.shln(c,16n) + U32.shln(d,24n) : U32)],
        compress(List.reverse(&2,U32,rev),state,end,0),end)
    case a <> b <> c <> d <> tail k:
      stream(tail,U32.add(k,1),(a + U32.shln(b,8n) + U32.shln(c,16n) + U32.shln(d,24n) : U32) <> rev,state,offset)
    case rest 32: stream_last(rest,rev,state,offset)
    case rest _: Context{state,unpack_rev(rev,rest),offset}

def update(ctx: Context, bytes: Bytes) -> Context:
  Context{state, tail, offset} = ctx
  stream(cat([tail, bytes]), 0, [], state, offset)

# The last block as 32 words with zero fill, and its byte count.
def pad_words(src: Bytes, +n: U32, rev: Bytes) -> Bytes & U32:
  match src:
    case a <> b <> c <> d <> tail:
      pad_words(tail,U32.add(n,4),(a + U32.shln(b,8n) + U32.shln(c,16n) + U32.shln(d,24n) : U32) <> rev)
    case [a,b,c]: (List.reverse.go(&2,U32,(a + U32.shln(b,8n) + U32.shln(c,16n) : U32) <> rev,zero_words(U32.sub(31,U32.shrn(n,2n)))),U32.add(n,3))
    case [a,b]: (List.reverse.go(&2,U32,(a + U32.shln(b,8n) : U32) <> rev,zero_words(U32.sub(31,U32.shrn(n,2n)))),U32.add(n,2))
    case [a]: (List.reverse.go(&2,U32,a <> rev,zero_words(U32.sub(31,U32.shrn(n,2n)))),U32.add(n,1))
    case _: (List.reverse.go(&2,U32,rev,zero_words(U32.sub(32,U32.shrn(n,2n)))),n)

def padded(last: Bytes & U32, state: Kernel.H8, offset: U32) -> Kernel.H8:
  (words, len) = last
  compress(words, state, U32.add(offset, len), 4294967295)

def finish_state(ctx: Context) -> Kernel.H8:
  Context{state, tail, offset} = ctx
  padded(pad_words(tail, 0, []), state, offset)

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
