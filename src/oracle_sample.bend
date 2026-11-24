import Base
import ./hash_bytes.bend as H
import ./transcript.bend as T
import ./base_check.bend as B
import ./fold.bend as F
import ./row_tensor.bend as X
import ./sumcheck.bend as E
import ./extension.bend as Ext
import ./commitment.bend as C

# R8.3 and the H821 SEND sample form, toys/1-product §2.4. Index bits are row first.
# first_row is the member's aligned row block in the batched group's corresponding table.
type Part is Data:
  Part{rows: Nat, ell: Nat, group_row_bits: Nat, first_row: Nat}
type Member is Data:
  Member{main: Part, mask: Part, base_main: Bool}
type Sample is Data:
  Sample{main: F.Form, mask: F.Form, target: Ext.E3}
type Seed is Data:
  Seed{point: B.Elements, beta: Ext.E3}

def point(n: Nat, s: T.Stream, acc: B.Elements) -> Seed:
  match n:
    case 0n: Seed{List.reverse(&2,Ext.E3,acc),T.value(Ext.E3,T.nonzero(s))}
    case 1n+k:
      +x = T.element(s)
      point(k,T.after(Ext.E3,x),T.value(Ext.E3,x) <> acc)

def row_bits(n: Nat) -> Nat:
  C.variables(U32.from_nat(Nat.max(1n,n)))

def width(part: Part) -> Nat:
  Part{rows,ell,_,_} = part
  Nat.add(row_bits(rows),row_bits(ell))

def exists(part: Part) -> Bool:
  Part{rows,_,_,_} = part
  Nat.is_lt(0n,rows)

def valid(part: Part) -> Bool:
  Part{+rows,ell,+g,+first} = part
  +span = Nat.pow(2n,row_bits(rows))
  Nat.is_eq(rows,0n) || (Nat.is_lt(0n,ell) && Nat.is_le(g,32n) && Nat.is_eq(Nat.mod(first,span),0n) &&
    Nat.is_le(Nat.add(first,span),Nat.pow(2n,Nat.min(g,32n))))

# The prefix fixes the high group-row coordinates between member rows and places.
def insert_prefix(rows: Nat, fs: F.Factors, prefix: F.Factors) -> F.Factors:
  match rows fs:
    case 0n rest: List.append(&2,F.Factor,prefix,rest)
    case 1n+k Con{f,rest}: f <> insert_prefix(k,rest,prefix)
    case _ Nil{}: prefix

def prefix_terms(terms: F.Form, +bits: Nat, +prefix: F.Factors) -> F.Form:
  match terms:
    case []: []
    case F.Term{w,fs} <> rest:
      F.Term{w,insert_prefix(bits,fs,prefix)} <> prefix_terms(rest,bits,prefix)

def embed_group(extra: Nat, terms: F.Form, +bits: Nat, first: Nat) -> F.Form:
  match extra:
    case 0n: terms
    case 1n+k: prefix_terms(terms,bits,X.choice(1n+k,Nat.div(first,Nat.pow(2n,bits))))

def group_form(terms: F.Form, +bits: Nat, group: Nat, first: Nat) -> F.Form:
  embed_group(Nat.sub(group,bits),terms,bits,first)

def basis(i: Nat) -> Ext.E3:
  match i:
    case 0n: F.one()
    case 1n: Ext.E3{0,0,0,1,0,0}
    case _: Ext.E3{0,0,0,0,0,1}

def pads(n: Nat, +factor: Ext.E3, +beta: Ext.E3, +fs: F.Factors, +bits: Nat, +base: Nat, +stride: Nat) -> F.Form:
  match n:
    case 0n: []
    case 1n+k:
      +i = k
      +j = Nat.add(base,Nat.mul(i,stride))
      delta = F.sub(E.mul(beta,basis(i)),E.mul(factor,X.entry(fs,j,F.one())))
      F.Term{delta,X.choice(bits,j)} <> pads(i,factor,beta,fs,bits,base,stride)

def form(part: Part, +z: B.Elements, factor: Ext.E3, pad_count: Nat, beta: Ext.E3) -> F.Form:
  match part:
    case Part{0n,_,_,_}: []
    case Part{+rows,+ell,g,first}:
      +r = row_bits(rows)
      +bits = Nat.add(r,row_bits(ell))
      +fs = X.eq(List.take(&2,Ext.E3,z,bits))
      +stride = Nat.pow(2n,r)
      +n = pad_count
      start = Nat.add(Nat.sub(rows,1n),Nat.mul(Nat.sub(ell,n),stride))
      +scale = factor
      corrections = pads(n,scale,beta,fs,bits,start,stride)
      group_form(F.Term{scale,fs} <> corrections,r,g,first)

def zeros(z: B.Elements, acc: Ext.E3) -> Ext.E3:
  match z:
    case []: acc
    case h <> t: zeros(t,E.mul(acc,F.sub(F.one(),h)))

def split_factor(z: B.Elements, +bits: Nat, max_bits: Nat, side: Ext.E3) -> Ext.E3:
  zeros(List.take(&2,Ext.E3,List.drop(&2,Ext.E3,z,bits),Nat.sub(max_bits,bits)),side)

def build(member: Member, seed: Seed, y: Ext.E3, valid_shape: Bool) -> Maybe<&2,Sample>:
  match member seed valid_shape:
    case _ _ False{}: None{}
    case Member{+m,+w,base} Seed{+z,+beta} True{}:
      +both = exists(m) && exists(w)
      +b = Nat.max(width(m),width(w))
      +top = Maybe.default(&2,Ext.E3,List.get(&2,Ext.E3,z,b),F.zero())
      sm = Bool.pick(Ext.E3,both,split_factor(z,width(m),b,F.sub(F.one(),top)),F.one())
      sw = Bool.pick(Ext.E3,both,split_factor(z,width(w),b,top),F.one())
      pc = Bool.pick(Nat,exists(w),0n,Bool.pick(Nat,base,3n,1n))
      good = Nat.is_le(Nat.add(b,Bool.pick(Nat,both,1n,0n)),List.length(&2,Ext.E3,z))
      sample: Sample = Sample{form(m,z,sm,pc,beta),form(w,z,sw,1n,beta),y}
      Bool.pick(Maybe<&2,Sample>,good,Some{sample},None{})

def single(+member: Member, seed: Seed, y: Ext.E3) -> Maybe<&2,Sample>:
  Member{+m,+w,_} = member
  build(member,seed,y,valid(m) && valid(w) && (exists(m) || exists(w)))
