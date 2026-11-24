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

# The dense mask table of a real group can exceed the JS call stack.
def count(~A: Data, xs: List<&2,A>, acc: Nat) -> Nat:
  match xs:
    case []: acc
    case _ <> tail: count(A,tail,1n+acc)

def take_into(~A: Data, xs: List<&2,A>, n: Nat, rev: List<&2,A>) -> List<&2,A>:
  match xs n:
    case Con{x,tail} 1n+k: take_into(A,tail,k,x <> rev)
    case _ _: List.reverse(&2,A,rev)

def take(~A: Data, xs: List<&2,A>, n: Nat) -> List<&2,A>: take_into(A,xs,n,[])

def cat(~A: Data, xs: List<&2,A>, ys: List<&2,A>) -> List<&2,A>:
  List.reverse.go(&2,A,List.reverse(&2,A,xs),ys)

def fill(n: Nat, +x: Ext.E3, acc: B.Elements) -> B.Elements:
  match n:
    case 0n: acc
    case 1n+k: fill(k,x,x <> acc)

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

def fixed_into(main: Form, +gs: B.Elements, +eps: Ext.E3, acc: Form) -> Form:
  match main:
    case []: List.reverse(&2,Term,acc)
    case Term{w,fs} <> more: fixed_into(more,gs,eps,fix(gs,fs,E.mul(w,eps)) <> acc)

def fixed(main: Form, gs: B.Elements, eps: Ext.E3) -> Form: fixed_into(main,gs,eps,[])

def fits_all(main: Form, +bits: Nat, good: Bool) -> Bool:
  match main good:
    case Nil{} b: b
    case Con{Term{_,fs},rest} True{}: fits_all(rest,bits,Nat.is_eq(List.length(&2,Factor,fs),bits))
    case _ _: False{}

def fits(main: Form, bits: Nat) -> Bool: fits_all(main,bits,True{})

def product(xs: B.Elements, acc: Ext.E3) -> Ext.E3:
  match xs:
    case []: acc
    case x <> tail: product(tail,E.mul(acc,x))

def scale_into(xs: B.Elements, +s: Ext.E3, acc: B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,Ext.E3,acc)
    case x <> tail: scale_into(tail,s,E.mul(s,x) <> acc)

def scaled(xs: B.Elements, s: Ext.E3) -> B.Elements: scale_into(xs,s,[])

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
  List.append(&2,Ext.E3,used,fill(Nat.sub(len,count(Ext.E3,used,0n)),zero(),[]))

def finish(claim: Claim, +gamma: B.Elements, +h: Nat, mask_len: Nat, +eps: Ext.E3, target: Ext.E3) -> Single:
  Claim{main,old,_} = claim
  old_scale = product(List.drop(&2,Ext.E3,gamma,h),eps)
  d = scaled(fold_low(List.take(&2,Ext.E3,gamma,h),old),old_scale)
  Single{fixed(main,gamma,eps),d,fresh(h,gamma,mask_len),target}

def spread_into(+lo: Ext.E3, +hi: Ext.E3, xs: B.Elements, acc: B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,Ext.E3,acc)
    case +x <> tail: spread_into(lo,hi,tail,E.mul(hi,x) <> E.mul(lo,x) <> acc)

def spread(lo: Ext.E3, hi: Ext.E3, xs: B.Elements) -> B.Elements: spread_into(lo,hi,xs,[])

# Expand a small final form. Factors stay compressed through all preceding code switches.
def factor_table(fs: Factors, weight: Ext.E3) -> B.Elements:
  match fs:
    case []: [weight]
    case Factor{lo,hi} <> tail:
      rest = factor_table(tail,weight)
      spread(lo,hi,rest)

def plus_into(xs: B.Elements, ys: B.Elements, acc: B.Elements) -> B.Elements:
  match xs ys:
    case Con{x,rest} Con{y,more}: plus_into(rest,more,E.add(x,y) <> acc)
    case _ _: List.reverse(&2,Ext.E3,acc)

def plus(xs: B.Elements, ys: B.Elements) -> B.Elements: plus_into(xs,ys,[])

# The list operation also defines the result for inputs of unequal lengths.
def expand_list(main: Form, acc: B.Elements) -> B.Elements:
  match main:
    case []: acc
    case Term{w,fs} <> more: expand_list(more,plus(factor_table(fs,w),acc))

def summed(pair: Array<Ext.E3> & Ext.E3,i: U32,w: Ext.E3) -> Array<Ext.E3>:
  (buf,old) = pair
  Array.set(Ext.E3,buf,i,E.add(old,w))

# Each nonzero endpoint contributes one subtree. Boolean selectors follow
# one child with the original weight, common when placing matrix cells.
def times(w: Ext.E3, f: Ext.E3) -> Ext.E3:
  match f:
    case Ext.E3{0,1,0,0,0,0}: w
    case x: E.mul(w,x)

def deposit_branch(fs: Factors, +i: U32, +w: Ext.E3, f: Ext.E3, skip: Bool, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match fs skip:
    case _ True{}: buf
    case Nil{} False{}: summed(Array.get(Ext.E3,buf,i),i,times(w,f))
    case Con{Factor{+a,+b},+tail} False{}:
      +v = times(w,f)
      +lo = U32.add(i,i)
      left = deposit_branch(tail,lo,v,a,B.equal(a,zero()),buf)
      deposit_branch(tail,U32.add(lo,1),v,b,B.equal(b,zero()),left)

def deposit(fs: Factors, i: U32, w: Ext.E3, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  deposit_branch(fs,i,w,one(),False{},buf)

def populate(main: Form,buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match main:
    case []: buf
    case Term{w,fs} <> rest: populate(rest,deposit(List.reverse(&2,Factor,fs),0,w,buf))

def accumulate(xs: List<Ext.E3>,ys: B.Elements,acc: B.Elements) -> B.Elements:
  match xs ys:
    case Con{x,tail} Con{y,more}: accumulate(tail,more,E.add(x,y) <> acc)
    case _ _: List.reverse(&2,Ext.E3,acc)

def values(xs: List<Ext.E3>,rev: B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,Ext.E3,rev)
    case x <> tail: values(tail,x <> rev)

# A placement that already checked factor widths can scatter into the zero vector directly.
def materialize(main: Form,k: Nat) -> B.Elements:
  values(Array.to_list(Ext.E3,populate(main,Array.new(Ext.E3,k,zero()))),[])

def sized(main: Form,acc: B.Elements,k: Nat,good: Bool) -> B.Elements:
  match good:
    case True{}: accumulate(Array.to_list(Ext.E3,populate(main,Array.new(Ext.E3,k,zero()))),acc,[])
    case False{}: expand_list(main,acc)

# Walk only nonzero branches of each tensor. Sparse mask slots add one entry per term.
def expand(main: Form,acc: B.Elements) -> B.Elements:
  match main:
    case []: acc
    case Term{w,+fs} <> rest:
      +terms : Form = Term{w,fs} <> rest
      +k = List.length(&2,Factor,fs)
      +ys = acc
      good = Nat.is_lt(k,32n) && Nat.is_eq(count(Ext.E3,ys,0n),Nat.pow(2n,k)) && fits(terms,k)
      sized(terms,ys,k,good)
