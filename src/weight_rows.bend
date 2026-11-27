import Base
import ./weight_types.bend as G
import ./fold.bend as F
import ./base_check.bend as B
import ./extension.bend as X
import ./row_tensor.bend as T
import ./sumcheck.bend as E
import ./key_stage_matrix.bend as Matrix
import ./key_stage_lookup.bend as Int
import ./oracle_sample.bend as Sample
import ./header.bend as H
import ./pow2.bend as P2

# For each mixed-radix group, the remaining row polynomial is represented
# by a small list of high-digit weights and a tensor over its low binary bits.
type Part is Data:
  Part{high: B.Elements, low: F.Factors}
type Product is Data:
  Product{coefficient: X.E3, parts: List<&2,Part>}

def eq_product(xs: B.Elements, ys: B.Elements, w: X.E3) -> X.E3:
  match xs ys:
    case Con{+x,a} Con{y,b}: eq_product(a,b,E.mul(w,F.mix(F.sub(F.one(),x),x,y)))
    case _ _: w

def pad(xs: B.Elements, acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case v <> tail: pad(tail,E.mul(acc,F.sub(F.one(),v)))

def pair_values(xs: B.Elements, +z: X.E3, acc: B.Elements) -> B.Elements:
  match xs:
    case x <> y <> tail: pair_values(tail,z,F.mix(x,y,z) <> acc)
    case [x]: List.reverse(&2,X.E3,F.mix(x,F.zero(),z) <> acc)
    case _: List.reverse(&2,X.E3,acc)

def evaluate(point: B.Elements, values: B.Elements) -> X.E3:
  match point:
    case g <> tail: evaluate(tail,pair_values(values,g,[]))
    case []: Maybe.default(&2,X.E3,List.head(&2,X.E3,values),F.zero())

def slice(xs: B.Elements, start: Nat, count: Nat) -> B.Elements:
  F.take(X.E3,List.drop(&2,X.E3,xs,start),count)

def equality(+high: Bool, bits: Nat, taken: Nat, +p: B.Elements, hv: B.Elements, column: B.Elements, c: X.E3, ps: List<&2,Part>) -> Product:
  +k = taken
  +rest = Nat.sub(bits,k)
  +a = Bool.pick(Nat,high,rest,0n)
  +b = Bool.pick(Nat,high,0n,k)
  Product{eq_product(slice(p,a,k),column,c),Part{hv,T.eq(slice(p,b,rest))} <> ps}

def group(g: G.Group, value: G.Factor, psi: B.Elements, old: Product) -> IO(Product):
  match g value old:
    case G.Group{_,G.E{},high,_,odd,+bits,+taken,start,_} G.Equality{+p,+hv} Product{w,rs}:
      do IO<Product>:
        ok : Unit <- H.require(Nat.is_eq(F.count(X.E3,p,0n),bits) && Nat.is_eq(F.count(X.E3,hv,0n),odd),"NO: weights-equality-shape")
        return equality(high,bits,taken,p,hv,slice(psi,start,taken),w,rs)
    case G.Group{_,G.A{},_,len,_,_,0n,_,_} G.ArrayFactor{+vals} Product{w,rs}:
      do IO<Product>:
        ok : Unit <- H.require(Nat.is_eq(F.count(X.E3,vals,0n),len),"NO: weights-array-shape")
        return Product{w,Part{vals,[]} <> rs}
    case G.Group{_,G.A{},_,len,_,_,taken,start,_} G.ArrayFactor{+vals} Product{w,rs}:
      do IO<Product>:
        ok : Unit <- H.require(Nat.is_eq(F.count(X.E3,vals,0n),len),"NO: weights-array-shape")
        return Product{E.mul(w,evaluate(slice(psi,start,taken),vals)),rs}
    case _ _ _: IO.die(Product,1,"NO: weights-factor")

def groups(gs: List<&2,G.Group>, vs: List<&2,G.Factor>, +psi: B.Elements, acc: Product) -> IO(Product):
  match gs vs:
    case Nil{} Nil{}: IO.pure(Product,acc)
    case Con{g,tail} Con{v,rest}:
      do IO<Product>:
        p : Product <- group(g,v,psi,acc)
        groups(tail,rest,psi,p)
    case _ _: IO.die(Product,1,"NO: weights-group-count")

def digit_weights(n: Nat, +v: X.E3) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k: v <> digit_weights(k,E.mul(v,Int.small(256n)))

# High-digit differencing is unnecessary when all groups have binary low
# coordinates: join successive low factors into one tensor whenever possible.
def normalize(xs: List<&2,Part>, low: F.Factors) -> List<&2,Part>:
  match xs:
    case Part{[X.E3{0,1,0,0,0,0}],fs} <> tail: normalize(tail,F.cat(F.Factor,low,fs))
    case Part{hs,fs} <> tail:
      Part{hs,F.cat(F.Factor,low,fs)} <> normalize(tail,[])
    case []: [Part{[F.one()],low}]

type Run is Data:
  Run{w: X.E3, at: Nat}

def expand_values(vs: B.Elements, +offset: Nat, +step: Nat, +coeff: X.E3, acc: List<&2,Run>) -> List<&2,Run>:
  match vs:
    case []: acc
    case x <> tail:
      expand_values(tail,Nat.add(offset,step),step,coeff,Run{E.mul(coeff,x),offset} <> acc)

def dense_terms(parents: List<&2,Run>, +vals: B.Elements, +stride: Nat, acc: List<&2,Run>) -> List<&2,Run>:
  match parents:
    case []: acc
    case Run{w,at} <> tail: dense_terms(tail,vals,stride,expand_values(vals,at,stride,w,acc))

def unfold(highs: B.Elements, +fs: F.Factors, acc: B.Elements) -> B.Elements:
  match highs:
    case []: List.reverse(&2,X.E3,acc)
    case h <> tail: unfold(tail,fs,List.reverse.go(&2,X.E3,F.factor_table(fs,h),acc))

def outer(ps: List<&2,Part>, parents: List<&2,Run>, +stride: Nat) -> List<&2,Run>:
  match ps:
    case []: parents
    case Part{hs,fs} <> tail:
      +v = unfold(hs,fs,[])
      outer(tail,dense_terms(parents,v,stride,[]),Nat.mul(stride,F.count(X.E3,v,0n)))

def translated(rs: List<&2,Run>, +bits: Nat, +low: F.Factors, +size: Nat, acc: F.Form) -> F.Form:
  match rs:
    case []: acc
    case Run{w,at} <> tail:
      next = Matrix.stretch(1n+Nat.mul(2n,bits),bits,0n,at,size,low,w,acc)
      translated(tail,bits,low,size,next)

def rows(parts: List<&2,Part>, w: X.E3, off: Nat, bits: Nat, acc: F.Form) -> F.Form:
  match parts:
    case Part{+hs,+low} <> tail:
      +n = P2.pow2(List.length(&2,F.Factor,low))
      runs = expand_values(hs,off,n,w,[])
      translated(outer(tail,runs,Nat.mul(n,F.count(X.E3,hs,0n))),bits,low,n,acc)
    case []: acc

def output(p: Product, d: Nat, off: Nat, bits: Nat, acc: F.Form) -> F.Form:
  Product{w,rev} = p
  all = List.reverse.go(&2,Part,rev,[Part{digit_weights(d,F.one()),[]}])
  rows(normalize(all,[]),w,off,bits,acc)

def unit(us: List<&2,G.WeightUnit>, +kind: Nat, +layer: Nat) -> IO(G.WeightUnit):
  match us:
    case []: IO.die(G.WeightUnit,1,"NO: weights-unit")
    case G.WeightUnit{+x,+l,d,c,at,rows,gs} <> tail:
      picked = Bool.pick(Unit -> IO(G.WeightUnit),Nat.is_eq(x,kind) && Nat.is_eq(l,layer),
        _ => IO.pure(G.WeightUnit,G.WeightUnit{x,l,d,c,at,rows,gs}), _ => unit(tail,kind,layer))
      picked(Unit{})

def in_unit(u: G.WeightUnit, fs: List<&2,G.Factor>, +psi: B.Elements, rho: X.E3, bits: Nat, acc: F.Form) -> IO(F.Form):
  G.WeightUnit{_,_,d,cb,at,_,gs} = u
  do IO<F.Form>:
    p : Product <- groups(gs,fs,psi,Product{pad(List.drop(&2,X.E3,psi,cb),rho),[]})
    return output(p,d,at,bits,acc)

def claim(layout: G.Layout, c: G.Claim, +psi: B.Elements, rho: X.E3, acc: F.Form) -> IO(F.Form):
  G.Layout{k,n,units} = layout
  G.Claim{x,l,fs,_,_,_} = c
  do IO<F.Form>:
    u : G.WeightUnit <- unit(units,x,l)
    ok : Unit <- H.require(Nat.is_eq(k,List.length(&2,X.E3,psi)),"NO: weights-column-point")
    in_unit(u,fs,psi,rho,Sample.row_bits(n),acc)
