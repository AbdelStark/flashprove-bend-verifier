import Base
import ./u3_cells.bend as Cells
import ./segment_attention_aff.bend as A
import ./sumcheck.bend as E
import ./fold.bend as F
import ./extension.bend as X

def Rows() -> Data: A.Equations
def slot(vs: A.Values,i: Nat) -> A.Aff: A.slot(vs,i)
def integer(n: Nat) -> A.Aff: A.const(A.nat(n))
def times(a: A.Aff,n: Nat) -> A.Aff: A.scale(a,A.nat(n))
def two(k: Nat) -> Nat: Nat.pow(2n,k)

# R11.2 five-limb ledger. Every committed cell holds the corresponding unsigned digit minus 128.
def digit(t: Nat,j: Nat) -> A.Aff: A.plus(A.Aff{[Cells.Cell{Nat.add(t,j),F.one()}],[],F.zero()},integer(128n))

def digits(+t: Nat,n: Nat,j: Nat,v: A.Aff,+scale: X.E3) -> A.Aff:
  match n:
    case 0n: v
    case 1n+k:
      +i = j
      digits(t,k,1n+i,A.add(v,digit(t,i),scale),E.mul(scale,A.nat(256n)))

def word(t: Nat,j: Nat,n: Nat) -> A.Aff: digits(t,n,j,A.zero(),F.one())

# The 39-bit root is represented as a + 2^24 b. Its low bit is digit 59.
def low(+t: Nat) -> A.Aff:
  A.plus(times(digit(t,58n),2n),word(t,59n,3n))
def high(t: Nat) -> A.Aff: word(t,62n,2n)
def root(+t: Nat) -> A.Aff: A.plus(low(t),times(high(t),two(24n)))
def recip(t: Nat) -> A.Aff: word(t,80n,6n)

def carry(t: Nat,i: Nat) -> A.Aff:
  match i:
    case 0n: A.zero()
    case 9n: digit(t,9n)
    case 1n+k: A.minus(word(t,Nat.add(10n,Nat.mul(k,6n)),6n),integer(two(47n)))

def carries(+t: Nat,+ws: A.Values,left: Nat,i: Nat) -> Rows:
  match left:
    case 0n: []
    case 1n+n:
      +j = i
      rhs = A.plus(digit(t,j),times(carry(t,1n+j),256n))
      A.minus(A.plus(slot(ws,j),carry(t,j)),rhs) <> carries(t,ws,n,1n+j)

def lines(+t: Nat,+p: A.Values,eps: Nat,mf: Nat) -> Rows:
  +blo = word(t,74n,3n)
  +bhi = word(t,77n,2n)
  +kap = A.minus(digit(t,79n),integer(4n))
  +l = word(t,64n,5n)
  +sig = root(t)
  +q = word(t,86n,3n)
  +rr = word(t,89n,5n)
  e0 = A.minus(A.minus(slot(p,1n),blo),times(bhi,two(23n)))
  e1 = A.plus(A.minus(A.minus(A.minus(A.plus(word(t,0n,6n),integer(eps)),slot(p,0n)),times(blo,two(25n))),l),A.scale(kap,X.E3{65536,0,0,0,0,0}))
  e2 = A.minus(A.minus(A.minus(word(t,6n,4n),bhi),slot(p,2n)),kap)
  e3 = A.minus(A.plus(l,word(t,69n,5n)),times(sig,2n))
  r1 = A.minus(A.plus(slot(p,4n),slot(p,5n)),q)
  r2 = slot(p,6n)
  r3 = A.minus(A.minus(A.minus(A.minus(A.plus(integer(two(1n+mf)),sig),digit(t,59n)),times(slot(p,3n),2n)),times(q,two(25n))),times(rr,2n))
  r4 = A.plus(A.minus(A.plus(rr,word(t,94n,5n)),sig),integer(1n))
  [e0,e1,e2,e3,r1,r2,r3,r4]


def scalar(vs: A.Values,n: Nat) -> X.E3: A.scalar(A.at(vs,n))

def products(+vs: A.Values,+omega: X.E3) -> X.E3:
  +a = scalar(vs,0n)
  +b = scalar(vs,1n)
  +lo = scalar(vs,2n)
  +hi = scalar(vs,3n)
  # Horner on [a², ab, b², Rlo*a, Rlo*b, Rhi*a, Rhi*b].
  v5 = E.horner(E.mul(hi,b),omega,E.mul(hi,a))
  v4 = E.horner(v5,omega,E.mul(lo,b))
  v3 = E.horner(v4,omega,E.mul(lo,a))
  v2 = E.horner(v3,omega,E.mul(b,b))
  E.horner(E.horner(v2,omega,E.mul(a,b)),omega,E.mul(a,a))

def powers(n: Nat,+v: X.E3,p: X.E3) -> X.E3:
  match n:
    case 0n: p
    case 1n+k: powers(k,v,E.mul(p,v))

def weighted(vs: A.Values,+w: X.E3,+p: X.E3,acc: A.Aff) -> A.Aff:
  match vs:
    case []: acc
    case x <> tail: weighted(tail,w,E.mul(p,w),A.add(acc,A.hidden(x),p))
