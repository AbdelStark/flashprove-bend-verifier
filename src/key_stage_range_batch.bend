import Base
import ./key_stage_lookup.bend as Arg
import ./key_stage_lookup_plan.bend as M
import ./key_stage_lookup_rows.bend as L
import ./key_stage_openings.bend as K
import ./oracle_sample.bend as Sample
import ./fold.bend as F
import ./row_tensor.bend as X
import ./base_check.bend as B
import ./extension.bend as Ext
import ./sumcheck.bend as E
import ./header.bend as Header
import ./leaf_shape.bend as S
import ./pow2.bend as P2

# R13.14. Partition each lookup's live planes into decreasing aligned binary
# blocks. Larger blocks from all lookups fill the oracle's message rows first.
type Block is Data:
  Block{lookup: Nat, first: Nat, free: Nat, mu: Nat, bits: Nat}
type Placed is Data:
  Placed{block: Block, row: Nat, cell: Nat}
def Blocks() -> Data: List<&2,Block>
def Layout() -> Data: List<&2,Placed>

def block_list(bits: Nat, +live: Nat, at: Nat, +d: Nat, +mu: Nat, +id: Nat) -> Blocks:
  match bits:
    case 0n: []
    case 1n+k:
      +b = k
      +size = P2.pow2(b)
      +hit = Nat.is_eq(Nat.mod(Nat.div(live,size),2n),1n)
      +pos = at
      +rest = block_list(b,live,Bool.pick(Nat,hit,Nat.add(pos,size),pos),d,mu,id)
      Bool.pick(Blocks,hit,Block{id,pos,b,mu,Nat.add(b,d)} <> rest,rest)

def blocks(xs: List<&2,M.Lookup>, id: Nat) -> Blocks:
  match xs:
    case []: []
    case M.Lookup{d,mu,live,_,_,_,_,_} <> tail:
      +j = id
      +m = U32.to_nat(mu)
      List.append(&2,Block,block_list(1n+m,U32.to_nat(live),0n,U32.to_nat(d),m,j),blocks(tail,1n+j))

def before(a: Block, b: Block) -> Bool:
  Block{_,_,_,_,x} = a
  Block{_,_,_,_,y} = b
  Nat.is_ge(x,y)

def place(xs: Blocks, +ell: Nat, row: Nat, cell: Nat) -> Layout:
  match xs:
    case []: []
    case +top <> tail:
      Block{_,_,_,_,b} = top
      +w = P2.pow2(b)
      +r = row
      +c = cell
      +fits = Nat.is_le(Nat.add(c,w),ell)
      +i = Bool.pick(Nat,fits,r,1n+r)
      +j = Bool.pick(Nat,fits,c,0n)
      Placed{top,i,j} <> place(tail,ell,i,Nat.add(j,w))

def term(block: Placed, factors: F.Factors, weight: Ext.E3, group: Nat, width: Nat) -> F.Term:
  Placed{Block{_,first,+b,+mu,+bits},row,cell} = block
  +fs = factors
  fixed = List.take(&2,F.Factor,List.drop(&2,F.Factor,fs,b),Nat.sub(mu,b))
  scalar = X.entry(fixed,Nat.div(first,P2.pow2(b)),weight)
  places = X.choice(Nat.sub(width,bits),Nat.div(cell,P2.pow2(bits)))
  all = List.concat(&2,F.Factor,[X.choice(group,row),List.take(&2,F.Factor,fs,b),
    List.drop(&2,F.Factor,fs,mu),places])
  F.Term{scalar,all}

def local(xs: Layout, +id: Nat, +f: F.Term, +power: Ext.E3, +group: Nat, +width: Nat, acc: F.Form) -> F.Form:
  match xs:
    case []: acc
    case +item <> rest:
      Placed{Block{shown,_,_,_,_},_,_} = item
      F.Term{w,fs} = f
      +tail = local(rest,id,f,power,group,width,acc)
      Bool.pick(F.Form,Nat.is_eq(id,shown),term(item,fs,E.mul(power,w),group,width) <> tail,tail)

def main_terms(planes: List<&2,L.Plane>, +layout: Layout, +power: Ext.E3, +group: Nat, +width: Nat, acc: F.Form) -> F.Form:
  match planes:
    case []: acc
    case L.Plane{id,f} <> tail:
      main_terms(tail,layout,power,group,width,local(layout,id,f,power,group,width,acc))

def updated(pair: Array<Ext.E3> & Ext.E3, i: U32, v: Ext.E3) -> Array<Ext.E3>:
  (a,old) = pair
  Array.set(Ext.E3,a,i,E.add(old,v))

def mask_terms(terms: L.Masks, +real: Nat, +padded: Nat, +power: Ext.E3, buf: Array<Ext.E3>) -> IO(Array<Ext.E3>):
  match terms:
    case []: IO.pure(Array<Ext.E3>,buf)
    case L.Mask{L.Multiplicities{},+i,c} <> tail:
      +slot = U32.from_nat(Nat.add(Nat.mod(i,real),Nat.mul(Nat.div(i,real),padded)))
      mask_terms(tail,real,padded,power,updated(Array.get(Ext.E3,buf,slot),slot,E.mul(c,power)))
    case _: IO.die(Array<Ext.E3>,1,"NO: key-range-mask-oracle")

type Batched is Type:
  Batched{power: Ext.E3, target: Ext.E3, main: F.Form, mask: Array<Ext.E3>}

type Axis is Data:
  Axis{layout: Layout, k: Nat, h: Nat, width: Nat, mask_rows: Nat}

def add(row: L.Row, axis: Axis, x: Ext.E3, state: Batched) -> IO(Batched):
  L.Row{ps,ms,target} = row
  Axis{layout,group,h,width,real} = axis
  Batched{+p,t,main,buf} = state
  do IO<Batched>:
    next : Array<Ext.E3> <- mask_terms(ms,real,P2.pow2(h),p,buf)
    return Batched{E.mul(p,x),E.add(t,E.mul(p,target)),main_terms(ps,layout,p,group,width,main),next}

def rows(xs: List<&2,L.Row>, +axis: Axis, +x: Ext.E3, state: Batched) -> IO(Batched):
  match xs:
    case []: IO.pure(Batched,state)
    case r <> tail:
      do IO<Batched>:
        next : Batched <- add(r,axis,x,state)
        rows(tail,axis,x,next)

def from_linear(xs: List<Ext.E3>, acc: B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,Ext.E3,acc)
    case h <> tail: from_linear(tail,h <> acc)

def finish(st: Batched, sample: Sample.Sample) -> F.Claim:
  Batched{+power,target,main,mask} = st
  Sample.Sample{mm,mz,answer} = sample
  coeff = from_linear(Array.to_list(Ext.E3,mask),[])
  F.Claim{X.scale(mm,power,main),F.expand(X.scale(mz,power,[]),coeff),E.add(target,E.mul(power,answer))}

def bat(meta: M.Metadata, verified: List<&2,L.Row>, seed: Sample.Seed, answer: Ext.E3,
  theta: Ext.E3, slots: Nat) -> IO(F.Claim):
  match meta:
    case M.Metadata{lookups,_,_,real,mask,S.Stage{B.Code{_,+ell,_},B.Code{_,+ml,_},k,h} <> _}:
      +n = U32.to_nat(real)
      +m = U32.to_nat(mask)
      +rb = U32.to_nat(k)
      +mb = U32.to_nat(h)
      +mask_bits = Nat.add(mb,Sample.row_bits(ml))
      sorted = List.sort(Block,before,blocks(lookups,0n))
      axis: Axis = Axis{place(sorted,ell,0n,0n),rb,mb,Sample.row_bits(ell),m}
      form: Sample.Member = Sample.Member{Sample.Part{n,ell,rb,0n},Sample.Part{m,ml,mb,0n},True{}}
      do IO<F.Claim>:
        ok : Unit <- Header.require(Nat.is_le(slots,Nat.sub(Nat.mul(m,ml),1n)),"NO: key-range-mask-budget")
        st : Batched <- rows(verified,axis,theta,Batched{F.one(),F.zero(),[],Array.new(Ext.E3,mask_bits,F.zero())})
        y : Sample.Sample <- K.need(Sample.Sample,Sample.single(form,seed,answer),"NO: key-range-sample")
        return finish(st,y)
    case _: IO.die(F.Claim,1,"NO: key-range-stages")
