import Base
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./extension.bend as Ext

# A separable main-row coefficient is weight times one endpoint per bit, low row bits first.
type Factor is Data:
  Factor{lo: Ext.E3, hi: Ext.E3}
def Factors() -> Data:
  List<&2,Factor>
type Term is Data:
  Term{weight: Ext.E3, factors: Factors}
def Form() -> Data:
  List<&2,Term>
type Claim is Data:
  Claim{main: Form, mask: B.Elements, target: Ext.E3}
type Single is Data:
  Single{main: Form, old_mask: B.Elements, fresh_mask: B.Elements, target: Ext.E3}

def zero() -> Ext.E3: Ext.E3{0,0,0,0,0,0}
def one() -> Ext.E3: Ext.E3{0,1,0,0,0,0}
def sub(a: Ext.E3, b: Ext.E3) -> Ext.E3: E.add(a,E.negate(b))
def mix(+lo: Ext.E3, hi: Ext.E3, g: Ext.E3) -> Ext.E3: B.masked(lo,g,sub(hi,lo))

# q(0)+q(1) fixes the absent linear coefficient.
def round(claim: Ext.E3, +c0: Ext.E3, +c2: Ext.E3, +g: Ext.E3) -> Ext.E3:
  c1 = sub(sub(claim,E.add(c0,c0)),c2)
  E.horner(E.horner(c2,g,c1),g,c0)

def fix(gs: B.Elements, fs: Factors, weight: Ext.E3) -> Term:
  match gs fs:
    case Nil{} rest: Term{weight,rest}
    case Con{g,tail} Con{Factor{lo,hi},rest}: fix(tail,rest,E.mul(weight,mix(lo,hi,g)))
    case _ _: Term{zero(),[]}

def fixed(main: Form, +gs: B.Elements, +eps: Ext.E3) -> Form:
  match main:
    case []: []
    case Term{w,fs} <> more: fix(gs,fs,E.mul(w,eps)) <> fixed(more,gs,eps)

def fits(main: Form, +bits: Nat) -> Bool:
  match main:
    case []: True{}
    case Term{_,fs} <> rest: Nat.is_eq(List.length(&2,Factor,fs),bits) && fits(rest,bits)

def product(xs: B.Elements, acc: Ext.E3) -> Ext.E3:
  match xs:
    case []: acc
    case x <> tail: product(tail,E.mul(acc,x))

def scaled(xs: B.Elements, +s: Ext.E3) -> B.Elements:
  match xs:
    case []: []
    case x <> tail: E.mul(s,x) <> scaled(tail,s)

def pairs(xs: B.Elements, +g: Ext.E3, acc: B.Elements) -> B.Elements:
  match xs:
    case lo <> hi <> tail: pairs(tail,g,mix(lo,hi,g) <> acc)
    case _: List.reverse(&2,Ext.E3,acc)

def fold_low(gs: B.Elements, xs: B.Elements) -> B.Elements:
  match gs:
    case []: xs
    case g <> tail: fold_low(tail,pairs(xs,g,[]))

def tail_weights(xs: B.Elements, first: Bool) -> B.Elements:
  match xs:
    case []: [one()]
    case +x <> +tail:
      +linear = product(tail,x)
      +rest: B.Elements = E.mul(linear,x) <> tail_weights(tail,False{})
      Bool.pick(B.Elements,first,rest,linear <> rest)

# Weights of the fresh hiding polynomial in fold_algebra.h, in its sent-column order.
def fresh(+h: Nat, +gs: B.Elements, len: Nat) -> B.Elements:
  +low = List.take(&2,Ext.E3,gs,h)
  +high = List.drop(&2,Ext.E3,gs,h)
  +s = product(high,one())
  extra = Bool.pick(B.Elements,List.is_empty(&2,Ext.E3,high),[],tail_weights(high,True{}))
  +used: B.Elements = s <> List.append(&2,Ext.E3,scaled(low,s),extra)
  List.append(&2,Ext.E3,used,List.replicate(Ext.E3,Nat.sub(len,List.length(&2,Ext.E3,used)),zero()))

def finish(claim: Claim, +gamma: B.Elements, +h: Nat, mask_len: Nat, +eps: Ext.E3, target: Ext.E3) -> Single:
  Claim{main,old,_} = claim
  old_scale = product(List.drop(&2,Ext.E3,gamma,h),eps)
  d = scaled(fold_low(List.take(&2,Ext.E3,gamma,h),old),old_scale)
  Single{fixed(main,gamma,eps),d,fresh(h,gamma,mask_len),target}

def spread(+lo: Ext.E3, +hi: Ext.E3, xs: B.Elements) -> B.Elements:
  match xs:
    case []: []
    case +x <> tail: E.mul(lo,x) <> E.mul(hi,x) <> spread(lo,hi,tail)

# Expand a small final form. Factors stay compressed through all preceding code switches.
def factor_table(fs: Factors, weight: Ext.E3) -> B.Elements:
  match fs:
    case []: [weight]
    case Factor{lo,hi} <> tail:
      rest = factor_table(tail,weight)
      spread(lo,hi,rest)

def plus(xs: B.Elements, ys: B.Elements) -> B.Elements:
  match xs ys:
    case Con{x,rest} Con{y,more}: E.add(x,y) <> plus(rest,more)
    case _ _: []

def expand(main: Form, acc: B.Elements) -> B.Elements:
  match main:
    case []: acc
    case Term{w,fs} <> more: expand(more,plus(factor_table(fs,w),acc))
