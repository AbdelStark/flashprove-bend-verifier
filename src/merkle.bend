import Base
import ./hashlib.bend as Hash

# Digests use on-wire word order. B2b.compress takes high, then low, limbs.
type Digest is Data:
  Digest{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32}

def truncate(state: Hash.H8) -> Digest:
  Hash.H8{h0,l0,h1,l1,h2,l2,h3,l3,_,_,_,_,_,_,_,_} = state
  Digest{l0,h0,l1,h1,l2,h2,l3,h3}

# R3.1: H(tag, index, start; left || right). Used for internal vertices
# and RUN. 16 label bytes + 64 child bytes fit in a single final block.
def parent(tagHi: U32, tagLo: U32, indexHi: U32, indexLo: U32,
           start: Digest, left: Digest, right: Digest) -> Digest:
  Digest{s0,s1,s2,s3,s4,s5,s6,s7} = start
  Digest{a0,a1,a2,a3,a4,a5,a6,a7} = left
  Digest{b0,b1,b2,b3,b4,b5,b6,b7} = right
  truncate(Hash.B2b.compress(
    1779033703, 4072524072, 3144134277, 2227873595, 1013904242, 4271175723, 2773480762, 1595750129,
    U32.xor(1359893119,s1), U32.xor(2917565137,s0), U32.xor(2600822924,s3), U32.xor(725511199,s2),
    U32.xor(528734635,s5), U32.xor(4215389547,s4), U32.xor(1541459225,s7), U32.xor(327033209,s6),
    tagHi,tagLo,indexHi,indexLo, a1,a0,a3,a2,a5,a4,a7,a6, b1,b0,b3,b2,b5,b4,b7,b6,
    0,0,0,0,0,0,0,0,0,0,0,0, 0,80,0,0,4294967295,4294967295))
