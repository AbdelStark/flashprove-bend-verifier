import Base
import ./fold.bend as F
import ./base_check.bend as B
import ./code_eval.bend as Code
import ./extension.bend as Ext
import ./goldilocks.bend as Field
import ./sumcheck.bend as E
import ./leaf_shape.bend as S
import ./transcript.bend as T

# One column after folding its authenticated rows. The calling transcript preserves repeated draws.
type Draw is Data:
  Draw{pos: Nat, main: Ext.E3, mask: Ext.E3, fresh: Ext.E3}
def Draws() -> Data: List<&2,Draw>

# Field 2 admits at most 2^32 places. The upper endpoint does not fit U32.
def bits(+len: Nat) -> Nat:
  Bool.pick(Nat,Nat.is_eq(len,1n+4294967295n),32n,U32.log2(U32.from_nat(len)))
def size(k: Nat) -> Nat: Nat.pow(2n,k)
def zeros(len: Nat) -> B.Elements: F.fill(len,F.zero(),[])

def embed(x: Field.Gl) -> Ext.E3:
  Field.Gl{h,l} = x
  Ext.E3{h,l,0,0,0,0}

def scale(x: Field.Gl, y: Ext.E3) -> Ext.E3:
  Field.Gl{sh,sl} = x
  Ext.E3{ah,al,bh,bl,ch,cl} = y
  Ext.E3.scale(ah,al,bh,bl,ch,cl,sh,sl)

def pow_loop(fuel: Nat, n: U32, +z: Field.Gl, +acc: Field.Gl) -> Field.Gl:
  match fuel n:
    case _ 0: acc
    case 1n+left +word:
      more = Bool.pick(Field.Gl,U32.is_zero(U32.and(word,1)),acc,Ext.product(acc,z))
      pow_loop(left,U32.shr(word),Ext.product(z,z),more)
    case _ _: acc

def pow(z: Field.Gl, n: Nat) -> Field.Gl: pow_loop(32n,U32.from_nat(n),z,Field.Gl{0,1})

def factors(n: Nat, +z: Field.Gl) -> F.Factors:
  match n:
    case 0n: []
    case 1n+left: F.Factor{F.one(),embed(z)} <> factors(left,Ext.product(z,z))

# Add v, v*z, ... directly to the current coefficient vector. The list
# length sets the number of exponents and each draw starts at exponent zero.
def add_powers(xs: B.Elements, +z: Field.Gl, +v: Ext.E3, rev: B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,Ext.E3,rev)
    case x <> rest: add_powers(rest,z,scale(z,v),E.add(x,v) <> rev)

def concat(xs: List<&2,B.Elements>) -> B.Elements:
  match xs:
    case []: []
    case x <> more: F.cat(Ext.E3,x,concat(more))

def eqs(xs: B.Elements) -> F.Factors:
  match xs:
    case []: []
    case +x <> rest: F.Factor{F.sub(F.one(),x),x} <> eqs(rest)

def front(xs: B.Elements, acc: Ext.E3) -> Ext.E3:
  match xs:
    case []: acc
    case x <> rest: front(rest,E.mul(acc,F.sub(F.one(),x)))

type Seed is Data:
  Seed{coords: B.Elements, beta: Ext.E3}

def seed(n: Nat, acc: B.Elements, stream: T.Stream) -> Seed:
  match n:
    case 0n: Seed{List.reverse(&2,Ext.E3,acc),T.value(Ext.E3,T.nonzero(stream))}
    case 1n+left:
      +draw = T.element(stream)
      seed(left,T.value(Ext.E3,draw) <> acc,T.after(Ext.E3,draw))

# The high selector bit separates the sampled oracle's two tables. The last mask entry is its sole pad.
def sample_term(+z: B.Elements, +k: Nat, scalar: Ext.E3) -> F.Term:
  F.Term{front(List.drop(&2,Ext.E3,z,k),scalar),eqs(List.take(&2,Ext.E3,z,k))}

def dense(t: F.Term) -> B.Elements:
  F.Term{w,fs} = t
  F.factor_table(fs,w)

def sample_at(main_bits: Nat, +mask_bits: Nat, +theta: Ext.E3, coords: B.Elements, +top: Ext.E3, beta: Ext.E3) -> F.Claim:
  +z = coords
  main = sample_term(z,main_bits,E.mul(theta,F.sub(F.one(),top)))
  ws = dense(sample_term(z,mask_bits,E.mul(theta,top)))
  +last = Nat.sub(size(mask_bits),1n)
  mask = F.cat(Ext.E3,F.take(Ext.E3,ws,last),[E.mul(theta,beta)])
  F.Claim{[main],mask,F.zero()}

def sample(main_bits: Nat, mask_bits: Nat, theta: Ext.E3, coords: B.Elements, beta: Ext.E3) -> Maybe<&2,F.Claim>:
  match coords:
    case top <> rev: Some{sample_at(main_bits,mask_bits,theta,List.reverse(&2,Ext.E3,rev),top,beta)}
    case []: None{}

# The rest of a stage switch is stored column-major in the new mask table, skipping the pad.
# One answer and complete power-of-two row counts put that pad at the table's very last index.
type State is Data:
  State{main: F.Form, tail_weights: B.Elements, mask_weights: B.Elements, target: Ext.E3, power: Ext.E3}

def generator(main: B.Code, mask: B.Code, +theta: Ext.E3, d: Draw, st: State,
              zp: Maybe<&2,Field.Gl>, zm: Maybe<&2,Field.Gl>) -> Maybe<&2,State>:
  match main mask d st zp zm:
    case B.Code{_,m,+r} B.Code{_,_,_} Draw{_,x,y,f} State{terms,tails,masks,target,+p} Some{+z} Some{+b}:
      +q = E.mul(p,theta)
      +v = E.mul(q,theta)
      term: F.Term = F.Term{scale(pow(z,r),p),factors(bits(m),z)}
      sum = B.masked(B.masked(B.masked(target,p,x),q,y),v,f)
      Some{State{term <> terms,add_powers(tails,z,p,[]),add_powers(masks,b,q,[]),sum,E.mul(v,theta)}}
    case _ _ _ _ _ _: None{}

def generators(+main: B.Code, +mask: B.Code, +theta: Ext.E3, ds: Draws, acc: Maybe<&2,State>) -> Maybe<&2,State>:
  match main mask ds acc:
    case _ _ Nil{} v: v
    case B.Code{+a,+m,+r} B.Code{+b,+n,+s} Con{Draw{+p,x,y,f},more} Some{st}:
      next = generator(B.Code{a,m,r},B.Code{b,n,s},theta,Draw{p,x,y,f},st,Code.point(a,p),Code.point(b,Nat.mod(p,size(b))))
      generators(B.Code{a,m,r},B.Code{b,n,s},theta,more,next)
    case _ _ _ _: None{}

# The old and fresh masks use the same evaluation point b for every draw.
# If M[j] = sum_i q_i * b_i^j, the fresh coefficients are theta * M[j].
# Accumulate M once, then split it at s (the parity tail length) and restore
# the protocol's five column blocks. This also works at theta = 0.
def finish(st: Maybe<&2,State>, sampled: Maybe<&2,F.Claim>, +len: Nat,
           d: B.Elements, f: B.Elements, +s: Nat, +theta: Ext.E3) -> Maybe<&2,F.Claim>:
  match st sampled:
    case Some{State{main,tails,+masks,target,_}} Some{F.Claim{form,ws,_}}:
      +parity = F.take(Ext.E3,masks,s)
      +message = List.drop(&2,Ext.E3,masks,s)
      +rest = concat([F.plus(d,message),F.plus(f,F.scaled(message,theta)),tails,parity,F.scaled(parity,theta)])
      +used = F.count(Ext.E3,rest,0n)
      mask = F.plus(F.cat(Ext.E3,rest,zeros(Nat.sub(len,used))),ws)
      row: F.Claim = F.Claim{F.cat(F.Term,main,form),mask,target}
      Bool.pick(Maybe<&2,F.Claim>,Nat.is_lt(used,len),Some{row},None{})
    case _ _: None{}

def switch_valid(old: S.Stage, next: S.Stage, single: F.Single, +theta: Ext.E3, draw: Draws, source: Seed, answer: Ext.E3) -> Maybe<&2,F.Claim>:
  S.Stage{B.Code{a,m,+r},B.Code{b,+n,+s},_,_} = old
  S.Stage{B.Code{_,u,_},B.Code{_,v,_},k,h} = next
  F.Single{main,d,f,target} = single
  Seed{+z,beta} = source
  +main_bits = Nat.add(U32.to_nat(k),bits(u))
  +mask_bits = Nat.add(U32.to_nat(h),bits(v))
  sample_row = sample(main_bits,mask_bits,theta,List.reverse(&2,Ext.E3,z),beta)
  st: State = State{main,zeros(r),zeros(Nat.add(n,s)),B.masked(target,theta,answer),E.mul(theta,theta)}
  acc = generators(B.Code{a,m,r},B.Code{b,n,s},theta,draw,Some{st})
  finish(acc,sample_row,size(mask_bits),d,f,s,theta)


def power_two(+n: Nat) -> Bool: Nat.is_eq(n,size(bits(n)))

def stage_ok(stage: S.Stage) -> Bool:
  S.Stage{B.Code{+a,+m,r},B.Code{+b,+n,s},+k,h} = stage
  B.code_ok(B.Code{a,m,r}) && B.code_ok(B.Code{b,n,s}) && Nat.is_le(b,a) &&
    power_two(m) && power_two(n) && U32.is_le(h,k) && U32.is_le(k,32)

def admissible(old: S.Stage, next: S.Stage, row: F.Single, src: Seed) -> Bool:
  S.Stage{B.Code{_,+m,r},B.Code{_,+n,s},_,_} = old
  S.Stage{B.Code{_,+u,_},B.Code{_,+v,_},+k,+h} = next
  F.Single{form,d,f,_} = row
  Seed{z,beta} = src
  mbits = Nat.add(bits(u),U32.to_nat(k))
  nbits = Nat.add(bits(v),U32.to_nat(h))
  used = Nat.add(Nat.mul(2n,n),Nat.add(r,Nat.mul(2n,s)))
  Nat.is_eq(m,Nat.mul(u,size(U32.to_nat(k)))) && Nat.is_lt(used,Nat.mul(v,size(U32.to_nat(h)))) &&
    F.fits(form,bits(m)) && Nat.is_eq(F.count(Ext.E3,d,0n),n) && Nat.is_eq(F.count(Ext.E3,f,0n),n) &&
    Nat.is_eq(F.count(Ext.E3,z,0n),1n+Nat.max(mbits,nbits)) && Bool.not(T.is_zero(beta))

def switch_ready(old: S.Stage, next: S.Stage, row: F.Single, theta: Ext.E3, ds: Draws, src: Seed, answer: Ext.E3, okay: Bool) -> Maybe<&2,F.Claim>:
  match okay:
    case False{}: None{}
    case True{}: switch_valid(old,next,row,theta,ds,src,answer)

def validated(+old: S.Stage, +next: S.Stage, +row: F.Single, theta: Ext.E3, ds: Draws, +src: Seed, answer: Ext.E3, okay: Bool) -> Maybe<&2,F.Claim>:
  match okay:
    case False{}: None{}
    case True{}: switch_ready(old,next,row,theta,ds,src,answer,admissible(old,next,row,src))

def switch(+old: S.Stage, +next: S.Stage, row: F.Single, theta: Ext.E3, ds: Draws, src: Seed, answer: Ext.E3) -> Maybe<&2,F.Claim>:
  validated(old,next,row,theta,ds,src,answer,stage_ok(old) && stage_ok(next))
