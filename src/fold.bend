import Base
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./extension.bend as Ext
import ./pow2.bend as P2

# A separable main-row coefficient is weight times one endpoint per bit, low row bits first.
type Factor is Data:
  Factor{lo: Ext.E3, hi: Ext.E3}
  Low{}
  High{}
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

# Fixed address bits occur once per dimension of a placed cell.
def at_bit(f: Factor, high: Bool) -> Ext.E3:
  match f:
    case Low{}: Bool.pick(Ext.E3,high,zero(),one())
    case High{}: Bool.pick(Ext.E3,high,one(),zero())
    case Factor{lo,hi}: Bool.pick(Ext.E3,high,hi,lo)

# q(0)+q(1) fixes the absent linear coefficient.
def round(claim: Ext.E3, +c0: Ext.E3, +c2: Ext.E3, +g: Ext.E3) -> Ext.E3:
  c1 = sub(sub(claim,E.add(c0,c0)),c2)
  E.horner(E.horner(c2,g,c1),g,c0)

def fix(gs: B.Elements, fs: Factors, weight: Ext.E3) -> Term:
  match gs fs:
    case Nil{} rest: Term{weight,rest}
    case Con{g,tail} Con{High{},rest}: fix(tail,rest,E.mul(weight,g))
    case Con{g,tail} Con{Low{},rest}: fix(tail,rest,E.mul(weight,sub(one(),g)))
    case Con{g,tail} Con{Factor{lo,hi},rest}: fix(tail,rest,E.mul(weight,mix(lo,hi,g)))
    case _ _: Term{zero(),[]}

def times(w: Ext.E3, f: Ext.E3) -> Ext.E3:
  match f:
    case Ext.E3{0,1,0,0,0,0}: w
    case x: E.mul(w,x)

# Fixing the first G coordinates at gammas. Coordinates go in chunks of
# four. A Projector's table holds, per chunk c, the product of each Boolean
# prefix of depth d and bits i at 32c + 2^d - 1 + i, then every gamma at
# base + p. A run of Boolean factors becomes an index with one product per
# chunk; a general factor fixes the rest of its chunk by interpolation.
# The walk reads a table it owns, so no shared node is taken per bit.
type Chunks is Data:
  Chunks{count: Nat, gammas: B.Elements}
type Projector is Type:
  Projector{count: Nat, base: U32, table: Array<Ext.E3>}
type Projected is Type:
  Projected{term: Term, projector: Projector}

def prepare(+gs: B.Elements) -> Chunks: Chunks{count(Ext.E3,gs,0n),gs}

def pick(bit: U32, +g: Ext.E3) -> Ext.E3: Bool.pick(Ext.E3,U32.is_eq(bit,1),g,sub(one(),g))

def prefix_weight(d: Nat, gs: B.Elements, +i: U32, acc: Ext.E3) -> Ext.E3:
  match d gs:
    case 1n+k Con{g,tail}: prefix_weight(k,tail,U32.shrn(i,1n),times(pick(U32.and(i,1),g),acc))
    case _ _: acc

def put(ok: Bool, buf: Array<Ext.E3>, i: U32, v: Ext.E3) -> Array<Ext.E3>:
  match ok:
    case True{}: Array.set(Ext.E3,buf,i,v)
    case False{}: buf

# Slot e of a chunk holds depth d = log2(e+1) and bits e+1-2^d.
def fill_chunk(k: Nat, +gs: B.Elements, +m: Nat, +at: U32, +e: U32, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match k:
    case 0n: buf
    case 1n+r:
      +d = U32.log2(U32.add(e,1))
      +i = U32.sub(U32.add(e,1),U32.shln(1,d))
      fill_chunk(r,gs,m,at,U32.add(e,1),put(Nat.is_le(d,m),buf,U32.add(at,e),prefix_weight(d,gs,i,one())))

def tables(fuel: Nat, gs: B.Elements, +c: U32, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match fuel gs:
    case 1n+k Con{g,rest}:
      +all: B.Elements = g <> rest
      +part = List.take(&2,Ext.E3,all,4n)
      tables(k,List.drop(&2,Ext.E3,all,4n),U32.add(c,1),fill_chunk(32n,part,count(Ext.E3,part,0n),U32.shln(c,5n),0,buf))
    case _ _: buf

def gammas(gs: B.Elements, +i: U32, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match gs:
    case []: buf
    case g <> tail: gammas(tail,U32.add(i,1),Array.set(Ext.E3,buf,i,g))

def projector(cs: Chunks) -> Projector:
  Chunks{+n,+gs} = cs
  +base = U32.shln(U32.from_nat(Nat.div(Nat.add(n,3n),4n)),5n)
  +size = U32.add(base,U32.from_nat(n))
  +depth = Bool.pick(Nat,U32.is_le(size,1),0n,Nat.add(U32.log2(U32.sub(size,1)),1n))
  Projector{n,base,gammas(gs,base,tables(n,gs,0,Array.new(Ext.E3,depth,zero())))}

# The prefix weight of the current chunk at depth j with bits i.
def slot(+pos: U32, +j: U32, +i: U32) -> U32:
  U32.add(U32.shln(U32.shrn(U32.sub(pos,j),2n),5n),U32.add(U32.sub(U32.shln(1,U32.to_nat(j)),1),i))

def edge(j: U32, rem: Nat) -> Bool: U32.is_eq(j,4) || Nat.is_eq(rem,0n)

def fixed_at(f: Factor, +g: Ext.E3) -> Ext.E3:
  match f:
    case High{}: g
    case Low{}: sub(one(),g)
    case Factor{lo,hi}: mix(lo,hi,g)

def done(+n: Nat, +base: U32, t: Term, got: Array<Ext.E3> & Ext.E3) -> Projected:
  (buf,_) = got
  Projected{t,Projector{n,base,buf}}

# fast: the chunk so far is Boolean and got holds its prefix weight.
# Otherwise got holds the gamma at pos. Each step reads one entry. A walk
# takes at most count + 2 * chunks + 1 steps, so its fuel never runs out.
def walk(fuel: Nat, at_edge: Bool, fast: Bool, rem: Nat, fs: Factors, +n: Nat, +base: U32, +pos: U32, +j: U32, +i: U32, w: Ext.E3, got: Array<Ext.E3> & Ext.E3) -> Projected:
  match fuel at_edge fast rem fs:
    case 0n _ _ _ _: done(n,base,Term{zero(),[]},got)
    case _ True{} True{} 0n rest:
      (buf,v) = got
      Projected{Term{times(w,v),rest},Projector{n,base,buf}}
    case 1n+h True{} True{} 1n+r rest:
      (buf,v) = got
      walk(h,False{},True{},1n+r,rest,n,base,pos,0,0,times(w,v),Array.get(Ext.E3,buf,slot(pos,0,0)))
    case _ True{} False{} 0n rest: done(n,base,Term{w,rest},got)
    case 1n+h True{} False{} 1n+r rest:
      (buf,_) = got
      walk(h,False{},True{},1n+r,rest,n,base,pos,0,0,w,Array.get(Ext.E3,buf,slot(pos,0,0)))
    case _ False{} _ 0n rest: done(n,base,Term{w,rest},got)
    case _ False{} _ _ Nil{}: done(n,base,Term{zero(),[]},got)
    case 1n+h False{} True{} 1n+(+r) Con{Low{},tail}:
      (buf,_) = got
      +k = U32.add(j,1)
      +p = U32.add(pos,1)
      walk(h,edge(k,r),True{},r,tail,n,base,p,k,i,w,Array.get(Ext.E3,buf,slot(p,k,i)))
    case 1n+h False{} True{} 1n+(+r) Con{High{},tail}:
      (buf,_) = got
      +k = U32.add(j,1)
      +p = U32.add(pos,1)
      +ix = U32.or(i,U32.shln(1,U32.to_nat(j)))
      walk(h,edge(k,r),True{},r,tail,n,base,p,k,ix,w,Array.get(Ext.E3,buf,slot(p,k,ix)))
    case 1n+h False{} True{} 1n+r Con{Factor{lo,hi},tail}:
      (buf,v) = got
      walk(h,False{},False{},1n+r,Factor{lo,hi} <> tail,n,base,pos,j,i,times(w,v),Array.get(Ext.E3,buf,U32.add(base,pos)))
    case 1n+h False{} False{} 1n+(+r) Con{f,tail}:
      (buf,g) = got
      +k = U32.add(j,1)
      +p = U32.add(pos,1)
      walk(h,edge(k,r),False{},r,tail,n,base,p,k,0,E.mul(w,fixed_at(f,g)),Array.get(Ext.E3,buf,U32.add(base,p)))

# Fix the first count coordinates of a term. Equals fix(gammas,fs,w), with
# zero weight and no factors when fs is shorter than the gammas.
def project_with(p: Projector, term: Term) -> Projected:
  Projector{+n,base,buf} = p
  Term{w,fs} = term
  +none = Nat.is_eq(n,0n)
  walk(Nat.add(Nat.double(n),4n),none,Bool.not(none),n,fs,n,base,0,0,0,w,Array.get(Ext.E3,buf,0))

def projected(p: Projected) -> Term:
  Projected{t,_} = p
  t

def project(cs: Chunks, term: Term) -> Term: projected(project_with(projector(cs),term))

def fixed_into(main: Form, +eps: Ext.E3, acc: Form, last: Projected) -> Form:
  match main:
    case []:
      Projected{t,_} = last
      List.reverse(&2,Term,t <> acc)
    case Term{w,fs} <> more:
      Projected{t,p} = last
      fixed_into(more,eps,t <> acc,project_with(p,Term{E.mul(w,eps),fs}))

# The seed projection heads the accumulated list.
def tail_of(xs: Form) -> Form:
  match xs:
    case []: []
    case _ <> rest: rest

def fixed(main: Form, gs: B.Elements, eps: Ext.E3) -> Form:
  tail_of(fixed_into(main,eps,[],Projected{Term{zero(),[]},projector(prepare(gs))}))

def has_width(bits: Nat, fs: Factors) -> Bool:
  match bits fs:
    case 0n Nil{}: True{}
    case 1n+k Con{_,rest}: has_width(k,rest)
    case _ _: False{}

def fits_all(main: Form, +bits: Nat, good: Bool) -> Bool:
  match main good:
    case Nil{} b: b
    case Con{Term{_,fs},rest} True{}: fits_all(rest,bits,has_width(bits,fs))
    case _ _: False{}

def fits(main: Form, bits: Nat) -> Bool: fits_all(main,bits,True{})

def product(xs: B.Elements, acc: Ext.E3) -> Ext.E3:
  match xs:
    case []: acc
    case x <> tail: product(tail,E.mul(acc,x))

def scale_into(+mode: U32, xs: B.Elements, +s: Ext.E3, acc: B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,Ext.E3,acc)
    case x <> tail: scale_into(mode,tail,s,E.by(mode,s,x) <> acc)

def scaled(xs: B.Elements, +s: Ext.E3) -> B.Elements: scale_into(E.unit(s),xs,s,[])

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
    case +f <> tail:
      lo = at_bit(f,False{})
      hi = at_bit(f,True{})
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

def scaled_by(skip: Bool,+w: Ext.E3,+f: Ext.E3) -> Ext.E3:
  match skip:
    case True{}: zero()
    case False{}: times(w,f)

# The low endpoint of an equality factor {1-x,x} needs no product: w(1-x) = w - wx.
def low_weight(complement: Bool,+w: Ext.E3,+a: Ext.E3,+high: Ext.E3) -> Ext.E3:
  match complement:
    case True{}: sub(w,high)
    case False{}: times(w,a)

# Each nonzero endpoint contributes one subtree, entered with its weight
# already applied. Boolean selectors follow one child with the original
# weight, common when placing matrix cells.
def deposit_branch(fs: Factors, +i: U32, +w: Ext.E3, skip: Bool, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match fs skip:
    case _ True{}: buf
    case Nil{} False{}: summed(Array.get(Ext.E3,buf,i),i,w)
    case Con{Low{},tail} False{}: deposit_branch(tail,U32.add(i,i),w,False{},buf)
    case Con{High{},tail} False{}: deposit_branch(tail,U32.add(U32.add(i,i),1),w,False{},buf)
    case Con{Factor{+a,+b},+tail} False{}:
      +b_zero = B.equal(b,zero())
      +high = scaled_by(b_zero,w,b)
      low = low_weight(B.equal(a,sub(one(),b)),w,a,high)
      +lo = U32.add(i,i)
      left = deposit_branch(tail,lo,low,B.equal(a,zero()),buf)
      deposit_branch(tail,U32.add(lo,1),high,b_zero,left)

def deposit(fs: Factors, i: U32, w: Ext.E3, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  deposit_branch(fs,i,w,False{},buf)

# A term of general factors fills its whole table. Double it in place one
# factor at a time, highest bit first, so entry 2k+b takes entry k times the
# new factor's endpoint b; the last factor adds into the buffer instead.
def double(n: Nat, +k: U32, +lo: Ext.E3, +hi: Ext.E3, +eq: Bool, got: Array<Ext.E3> & Ext.E3) -> Array<Ext.E3>:
  match n:
    case 0n:
      (t,_) = got
      t
    case 1n+r:
      (t,+v) = got
      +h = times(v,hi)
      +j = U32.add(k,k)
      t2 = Array.set(Ext.E3,Array.set(Ext.E3,t,U32.add(j,1),h),j,low_weight(eq,v,lo,h))
      double(r,U32.sub(k,1),lo,hi,eq,Array.get(Ext.E3,t2,U32.sub(k,1)))

def last_level(n: Nat, +k: U32, +lo: Ext.E3, +hi: Ext.E3, +eq: Bool, got: Array<Ext.E3> & Ext.E3, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match n:
    case 0n: buf
    case 1n+r:
      (t,+v) = got
      +h = times(v,hi)
      +j = U32.add(k,k)
      +b1 = U32.add(j,1)
      upper = summed(Array.get(Ext.E3,buf,b1),b1,h)
      lower = summed(Array.get(Ext.E3,upper,j),j,low_weight(eq,v,lo,h))
      last_level(r,U32.sub(k,1),lo,hi,eq,Array.get(Ext.E3,t,U32.sub(k,1)),lower)

def level_end(+f: Factor, +k: U32, +size: Nat, t: Array<Ext.E3>, buf: Array<Ext.E3>) -> Array<Ext.E3> & Array<Ext.E3>:
  +lo = at_bit(f,False{})
  +hi = at_bit(f,True{})
  (Array.new(Ext.E3,0n,zero()),last_level(size,k,lo,hi,B.equal(lo,sub(one(),hi)),Array.get(Ext.E3,t,k),buf))

def level_mid(+f: Factor, +k: U32, +size: Nat, t: Array<Ext.E3>, buf: Array<Ext.E3>) -> Array<Ext.E3> & Array<Ext.E3>:
  +lo = at_bit(f,False{})
  +hi = at_bit(f,True{})
  (double(size,k,lo,hi,B.equal(lo,sub(one(),hi)),Array.get(Ext.E3,t,k)),buf)

def endpoints_of(last: Bool, f: Factor, +k: U32, +size: Nat, t: Array<Ext.E3>, buf: Array<Ext.E3>) -> Array<Ext.E3> & Array<Ext.E3>:
  match last:
    case True{}: level_end(f,k,size,t,buf)
    case False{}: level_mid(f,k,size,t,buf)

def levels(fs: Factors, +size: Nat, pair: Array<Ext.E3> & Array<Ext.E3>) -> Array<Ext.E3>:
  match fs:
    case []:
      (_,buf) = pair
      buf
    case f <> +tail:
      (t,buf) = pair
      +k = U32.sub(U32.from_nat(size),1)
      levels(tail,Nat.double(size),endpoints_of(List.is_empty(&2,Factor,tail),f,k,size,t,buf))

def general_count(fs: Factors, n: Nat) -> Nat:
  match fs:
    case []: n
    case Factor{_,_} <> tail: general_count(tail,1n+n)
    case _ <> _: 0n

def placed_by(dense: Bool, +n: Nat, high: Factors, w: Ext.E3, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match dense:
    case True{}: levels(high,1n,(Array.set(Ext.E3,Array.new(Ext.E3,n,zero()),0,w),buf))
    case False{}: deposit(high,0,w,buf)

# Dense filling pays off once a term spans a few general bits.
def place(w: Ext.E3, fs: Factors, buf: Array<Ext.E3>) -> Array<Ext.E3>:
  +high = List.reverse(&2,Factor,fs)
  +n = general_count(high,0n)
  placed_by(Nat.is_le(6n,n),n,high,w,buf)

def populate(main: Form,buf: Array<Ext.E3>) -> Array<Ext.E3>:
  match main:
    case []: buf
    case Term{w,fs} <> rest: populate(rest,place(w,fs,buf))

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
      good = Nat.is_lt(k,32n) && Nat.is_eq(count(Ext.E3,ys,0n),P2.pow2(k)) && fits(terms,k)
      sized(terms,ys,k,good)
