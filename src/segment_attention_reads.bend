import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_shape.bend as S
import ./segment_attention_points.bend as Z
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F

# R11.3 plane PL, byte recomposition LV, long block XL and head sum OG.
type TensorKind is Data:
  Maximum{}
  Denominator{}
  Index{bit: Nat}
  Remainder{}
  Complement{}
  Query{}
  KeyVector{}
  ValueVector{}
  OutputVector{}

type Tensor is Data:
  Tensor{off: Nat, limbs: Nat, features: Nat, block: Nat, head: Nat, channel: B.Elements}

def tensor_at(kind: TensorKind,s: S.Shape,+l: Nat,+h: Nat,d: Nat,+dq: Nat,+dk: Nat,blk: Nat,hi: B.Elements,qhead: Nat,kv: Nat) -> Tensor:
  match kind:
    case Maximum{}: Tensor{0n,4n,h,1n,qhead,[]}
    case Denominator{}: Tensor{Nat.mul(Nat.mul(4n,l),h),4n,h,1n,qhead,[]}
    case Index{k}: Tensor{Nat.mul(Nat.mul(8n,l),h),1n,Nat.mul(S.lt(s),h),1n,Nat.add(Nat.mul(k,h),qhead),[]}
    case Remainder{}: Tensor{0n,1n,dq,blk,Nat.mul(qhead,d),hi}
    case Complement{}: Tensor{Nat.mul(l,dq),1n,dq,blk,Nat.mul(qhead,d),hi}
    case Query{}: Tensor{0n,2n,dq,blk,Nat.mul(qhead,d),hi}
    case KeyVector{}: Tensor{Nat.mul(Nat.mul(2n,l),dq),2n,dk,blk,Nat.mul(kv,d),hi}
    case ValueVector{}: Tensor{Nat.mul(Nat.mul(2n,l),Nat.add(dq,dk)),2n,dk,blk,Nat.mul(kv,d),hi}
    case OutputVector{}: Tensor{Nat.mul(Nat.mul(2n,l),Nat.add(dq,Nat.mul(2n,dk))),2n,dq,blk,Nat.mul(qhead,d),hi}

def tensor(kind: TensorKind,+s: S.Shape, lam: Nat, +qhead: Nat, kv: Nat, +zc: B.Elements) -> Tensor:
  +h = S.heads(s)
  +l = S.layers(s)
  +d = A.size(S.ld(s))
  +dq = Nat.mul(h,d)
  +dk = Nat.mul(S.group(s),d)
  +blk = A.size(S.lanes(s))
  +hi = Z.take(zc,Nat.sub(S.ld(s),S.lanes(s)))
  tensor_at(kind,s,l,h,d,dq,dk,blk,hi,qhead,kv)

def block(n: Nat,+at: Nat,+z: B.Elements,+scale: X.E3,acc: List<&2,A.Cell>) -> List<&2,A.Cell>:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      block(i,at,z,scale,A.Cell{Nat.add(at,i),E.mul(scale,A.eq(z,i))} <> acc)

def limbs(n: Nat,+off: Nat,+start: Nat,+stride: Nat,+blk: Nat,+hi: B.Elements,+scale: X.E3,
   acc: List<&2,A.Cell>) -> List<&2,A.Cell>:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      pos = Nat.add(off,Nat.div(Nat.add(start,Nat.mul(i,stride)),blk))
      w = E.mul(scale,A.nat(A.size(Nat.mul(8n,i))))
      cs = block(A.size(List.length(&2,X.E3,hi)),pos,hi,w,acc)
      limbs(i,off,start,stride,blk,hi,scale,cs)

def read_tensor(t: Tensor,layers: Nat,lam: Nat,offset: Nat,w: X.E3,acc: List<&2,A.Cell>) -> List<&2,A.Cell>:
  Tensor{off,n,+width,block_size,f,hi} = t
  limbs(n,offset,Nat.add(Nat.add(off,Nat.mul(lam,width)),f),Nat.mul(layers,width),block_size,hi,w,acc)

def heads(n: Nat,+s: S.Shape,+table: Nat,+kind: TensorKind,+b: Nat,+g: B.Elements,+zc: B.Elements,+w: X.E3,
  acc: List<&2,A.Cell>) -> List<&2,A.Cell>:
  match n:
    case 0n: acc
    case 1n+k:
      +j = k
      +ha = S.ha(s)
      +lam = Nat.div(b,ha)
      q = Nat.add(Nat.mul(j,ha),Nat.mod(b,ha))
      t = tensor(kind,s,lam,q,j,zc)
      heads(j,s,table,kind,b,g,zc,w,read_tensor(t,S.layers(s),lam,table,E.mul(w,A.eq(g,j)),acc))

def read(+s: S.Shape,table: Nat,kind: TensorKind,b: Nat,g: B.Elements,zc: B.Elements) -> A.Aff:
  A.Aff{heads(S.group(s),s,table,kind,b,g,zc,F.one(),[]),[],F.zero()}

def batch(ws: B.Elements,+s: S.Shape,+table: Nat,+kind: TensorKind,+g: B.Elements,+zc: B.Elements,b: Nat,
  acc: List<&2,A.Cell>) -> A.Aff:
  match ws:
    case []: A.Aff{acc,[],F.zero()}
    case w <> rest:
      +i = b
      cs = heads(S.group(s),s,table,kind,i,g,zc,w,acc)
      batch(rest,s,table,kind,g,zc,Nat.add(1n,i),cs)

def plane(+s: S.Shape,table: Nat,+d: Bool,z: B.Elements,x: Nat,b: Nat) -> A.Aff:
  +nb = S.ns(s,d)
  +k = Nat.sub(nb,S.lm(s))
  first = Bool.pick(Nat,d,Nat.mul(Nat.mul(5n,S.pairs(s)),A.size(Nat.sub(S.main_region(s),S.lm(s)))),0n)
  offset = Nat.add(Nat.add(table,first),Nat.mul(Nat.add(Nat.mul(x,S.pairs(s)),b),A.size(k)))
  A.Aff{block(A.size(k),offset,Z.take(z,k),F.one(),[]),[],F.zero()}

def planes(ws: B.Elements,+s: S.Shape,+table: Nat,+d: Bool,+z: B.Elements,+x: Nat,b: Nat,acc: A.Aff) -> A.Aff:
  match ws:
    case []: acc
    case w <> rest:
      +i = b
      planes(rest,s,table,d,z,x,Nat.add(1n,i),A.add(acc,plane(s,table,d,z,x,i),w))
