import Base
import ./key_stage_lookup_plan.bend as M
import ./key_stage_lookup.bend as Arg
import ./key_stage_lookup_rows.bend as L
import ./base_check.bend as B
import ./extension.bend as Ext
import ./fold.bend as F
import ./row_tensor.bend as X
import ./sumcheck.bend as E
import ./hash_bytes.bend as H
import ./key_stage_openings.bend as K
import ./header.bend as Header
import ./pow2.bend as P2

# Sum of the public multilinear weights at indices < limit. Higher bits supersede
# the earlier comparison. This also handles a limit equal to the whole domain.
def below(point: B.Elements, +limit: Nat, +acc: Ext.E3) -> Ext.E3:
  match point:
    case []: Bool.pick(Ext.E3,Nat.is_eq(limit,0n),acc,F.one())
    case +z <> tail:
      +lo = F.sub(F.one(),z)
      next = Bool.pick(Ext.E3,Nat.is_eq(Nat.mod(limit,2n),0n),E.mul(lo,acc),E.add(lo,E.mul(z,acc)))
      below(tail,Nat.div(limit,2n),next)

def coverage(rs: List<&2,M.Run>, +point: B.Elements, acc: Ext.E3) -> Ext.E3:
  match rs:
    case []: acc
    case M.Run{from,_,n,_} <> more:
      +start = U32.to_nat(from)
      hi = below(point,Nat.add(start,U32.to_nat(n)),F.zero())
      lo = below(point,start,F.zero())
      coverage(more,point,E.add(acc,F.sub(hi,lo)))

# For a fixed destination block, weight j is eq(source + j, point).
# A bit of source plus the incoming carry is 0, 1, or 2. Only at 1 does
# the carry depend on the destination bit. All equal upper factors are shared.
type Carries is Data:
  Carries{without: F.Form, with_carry: F.Form}

def attach(terms: F.Form, +endpoints: F.Factor, acc: F.Form) -> F.Form:
  match terms:
    case []: acc
    case F.Term{w,fs} <> tail: attach(tail,endpoints,F.Term{w,endpoints <> fs} <> acc)

def choose(bit: Nat, a: F.Form, b: F.Form, cross: F.Form, f: F.Factor) -> Carries:
  match bit:
    case 0n: Carries{attach(a,f,[]),cross}
    case _: Carries{cross,attach(b,f,[])}

def step(carries: Carries, +lo: Ext.E3, +hi: Ext.E3, bit: Nat) -> Carries:
  Carries{+a,+b} = carries
  cross = attach(a,F.Factor{hi,F.zero()},attach(b,F.Factor{F.zero(),lo},[]))
  choose(bit,a,b,cross,F.Factor{lo,hi})

def shifted(n: Nat, +src: Nat, factors: F.Factors, prefix: F.Factors, +scale: Ext.E3) -> Carries:
  match n factors:
    case 0n +high:
      +suffix = prefix
      a = X.entry(high,src,scale)
      b = X.entry(high,1n+src,scale)
      Carries{[F.Term{a,suffix}],[F.Term{b,suffix}]}
    case 1n+k Con{+f,tail}:
      lo = F.at_bit(f,False{})
      hi = F.at_bit(f,True{})
      step(shifted(k,Nat.div(src,2n),tail,prefix,scale),lo,hi,Nat.mod(src,2n))
    case _ _: Carries{[],[]}

def merge(carries: Carries, acc: F.Form) -> F.Form:
  Carries{xs,_} = carries
  List.reverse.go(&2,F.Term,xs,acc)

def block_bits(n: Nat, row: Nat) -> Nat:
  +k = U32.log2(U32.from_nat(n))
  +word = U32.from_nat(row)
  Bool.pick(Nat,U32.is_zero(word),k,Nat.min(k,U32.log2(U32.and(word,U32.sub(0,word)))))

# When the source start is divisible by this block's length, its low
# coordinates pass through unchanged and cannot carry into the prefix.
def aligned(n: Nat, cell: Nat, fs: F.Factors, high: F.Factors, scale: Ext.E3, rev: F.Factors, acc: F.Form) -> F.Form:
  match n fs:
    case 0n rest: F.Term{X.entry(rest,cell,scale),List.reverse.go(&2,F.Factor,rev,high)} <> acc
    case 1n+k f <> rest: aligned(k,cell,rest,high,scale,f <> rev,acc)
    case _ _: acc

def shifted_block(exact: Bool, b: Nat, +c: Nat, size: Nat, point: F.Factors, high: F.Factors, scale: Ext.E3, acc: F.Form) -> F.Form:
  match exact:
    case True{}: aligned(b,Nat.div(c,size),point,high,scale,[],acc)
    case False{}: merge(shifted(b,c,point,high,scale),acc)

# A run needs at most two destination blocks per row-index bit.
def stretch(fuel: Nat, +rows: Nat, cell: Nat, row: Nat, count: Nat, +point: F.Factors, +scale: Ext.E3, acc: F.Form) -> F.Form:
  match fuel count:
    case _ 0n: acc
    case 1n+k +n:
      +r = row
      +b = block_bits(n,r)
      +size = P2.pow2(b)
      +c = cell
      high = X.choice(Nat.sub(rows,b),Nat.div(r,size))
      items = shifted_block(Nat.is_eq(Nat.mod(c,size),0n),b,c,size,point,high,scale,acc)
      stretch(k,rows,Nat.add(c,size),Nat.add(r,size),Nat.sub(n,size),point,scale,items)
    case _ _: acc

def digits(weights: H.Bytes, +cell: Nat, +row: Nat, +count: Nat, +stride: Nat, +bits: Nat,
  +point: F.Factors, +coeff: Ext.E3, acc: F.Form) -> F.Form:
  match weights:
    case []: acc
    case w <> tail:
      scale = E.mul(coeff,Arg.small(U32.to_nat(w)))
      next = stretch(1n+Nat.mul(2n,bits),bits,cell,row,count,point,scale,acc)
      digits(tail,cell,Nat.add(row,stride),count,stride,bits,point,coeff,next)

def runs(rs: List<&2,M.Run>, +weights: H.Bytes, +bits: Nat, +point: F.Factors, +coeff: Ext.E3, acc: F.Form) -> F.Form:
  match rs:
    case []: acc
    case M.Run{cell,row,n,stride} <> tail:
      next = digits(weights,U32.to_nat(cell),U32.to_nat(row),U32.to_nat(n),U32.to_nat(stride),bits,point,coeff,acc)
      runs(tail,weights,bits,point,coeff,next)

type Part is Data:
  Part{source: List<&2,M.Run>, digit_weights: H.Bytes, cell_point: F.Factors, psi: B.Elements, masks: L.Masks, target: Ext.E3}

def prepared(pending: Arg.Pending, lookup: M.Lookup, kcol: Nat) -> Part:
  Arg.Pending{L.Point{+z,ms,v},M.Part{_,+rs},alpha,_} = pending
  M.Lookup{_,_,_,ws,off,pad,_,_} = lookup
  +k = kcol
  +cells = List.drop(&2,Ext.E3,z,k)
  +sum = coverage(rs,cells,F.zero())
  correction = E.add(E.mul(sum,Arg.small(U32.to_nat(off))),E.mul(F.sub(F.one(),sum),Arg.small(U32.to_nat(pad))))
  Part{rs,ws,X.eq(cells),List.take(&2,Ext.E3,z,k),L.scale(ms,E.negate(F.one())),F.sub(F.sub(alpha,v),correction)}

def parts(pending: List<&2,Arg.Pending>, +lookups: List<&2,M.Lookup>, +kcol: Nat, acc: List<&2,Part>) -> IO(List<&2,Part>):
  match pending:
    case []: IO.pure(List<&2,Part>,List.reverse(&2,Part,acc))
    case +p <> tail:
      Arg.Pending{_,_,_,id} = p
      do IO<List<&2,Part>>:
        lookup : M.Lookup <- K.need(M.Lookup,List.get(&2,M.Lookup,lookups,id),"NO: key-pending-lookup")
        parts(tail,lookups,kcol,prepared(p,lookup,kcol) <> acc)
