#!/usr/bin/env python3
"""Reference for the spike: chain N BLAKE2b compressions (t=128, f=0) in pure Python."""
import sys
M=(1<<64)-1
IV=[0x6a09e667f3bcc908,0xbb67ae8584caa73b,0x3c6ef372fe94f82b,0xa54ff53a5f1d36f1,0x510e527fade682d1,0x9b05688c2b3e6c1f,0x1f83d9abfb41bd6b,0x5be0cd19137e2179]
SIGMA=[[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],[14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3],[11,8,12,0,5,2,15,13,10,14,3,6,7,1,9,4],[7,9,3,1,13,12,11,14,2,6,5,10,4,0,15,8],[9,0,5,7,2,4,10,15,14,1,11,12,6,8,3,13],[2,12,6,10,0,11,8,3,4,13,7,5,15,14,1,9],[12,5,1,15,14,13,4,10,0,7,6,3,9,2,8,11],[13,11,7,14,12,1,3,9,5,0,15,4,8,6,2,10],[6,15,14,9,11,3,0,8,12,2,13,7,1,4,10,5],[10,2,8,4,7,6,1,5,15,11,9,14,3,12,13,0]]
def rotr(x,n): return ((x>>n)|(x<<(64-n)))&M
def F(h,m,t,f):
    v=h[:]+IV[:]
    v[12]^=t&M; v[13]^=(t>>64)&M
    if f: v[14]^=M
    def G(a,b,c,d,x,y):
        v[a]=(v[a]+v[b]+x)&M; v[d]=rotr(v[d]^v[a],32); v[c]=(v[c]+v[d])&M; v[b]=rotr(v[b]^v[c],24)
        v[a]=(v[a]+v[b]+y)&M; v[d]=rotr(v[d]^v[a],16); v[c]=(v[c]+v[d])&M; v[b]=rotr(v[b]^v[c],63)
    for r in range(12):
        s=SIGMA[r%10]
        G(0,4,8,12,m[s[0]],m[s[1]]); G(1,5,9,13,m[s[2]],m[s[3]]); G(2,6,10,14,m[s[4]],m[s[5]]); G(3,7,11,15,m[s[6]],m[s[7]])
        G(0,5,10,15,m[s[8]],m[s[9]]); G(1,6,11,12,m[s[10]],m[s[11]]); G(2,7,8,13,m[s[12]],m[s[13]]); G(3,4,9,14,m[s[14]],m[s[15]])
    return [h[i]^v[i]^v[i+8] for i in range(8)]
N=int(sys.argv[1]) if len(sys.argv)>1 else 1000
h=IV[:]; h[0]^=0x01010040
msg=bytes(range(128)); m=[int.from_bytes(msg[8*i:8*i+8],"little") for i in range(16)]
for _ in range(N): h=F(h,m,128,False)
print(" ".join(f"{x:016x}" for x in h)+" ")
# self-check of F against hashlib on one-block message
import hashlib
hh=IV[:]; hh[0]^=0x01010040
blk=b"abc"+bytes(125); mm=[int.from_bytes(blk[8*i:8*i+8],"little") for i in range(16)]
d=b"".join(x.to_bytes(8,"little") for x in F(hh,mm,3,True))
assert d==hashlib.blake2b(b"abc").digest(), "reference F is wrong"
