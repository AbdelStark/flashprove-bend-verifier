import Base
import ./fold.bend as F
import ./fold_cs.bend as C
import ./fold_open.bend as O
import ./row_tensor.bend as X
import ./base_check.bend as B
import ./extension.bend as E
import ./sumcheck.bend as A
import ./transcript.bend as T

# A link's oracle messages in increasing sending order. Kept main rows are a separate table.
type Member is Data:
  Member{id: Nat, main_rows: Nat, main_deg: Nat, mask_rows: Nat, kept: Bool}
def Members() -> Data: List<&2,Member>
type On is Data:
  On{id: Nat, mask: Bool, form: F.Form}
def Forms() -> Data: List<&2,On>
type Equation is Data:
  Equation{forms: Forms, target: E.E3}
type Batched is Data:
  Batched{forms: Forms, target: E.E3, power: E.E3}

def scale(xs: Forms, +w: E.E3, acc: Forms) -> Forms:
  match xs:
    case []: acc
    case On{id,mask,form} <> rest: scale(rest,w,On{id,mask,X.scale(form,w,[])} <> acc)

def batch(rows: List<&2,Equation>, +theta: E.E3, state: Batched) -> Batched:
  match rows state:
    case Nil{} st: st
    case Con{Equation{terms,y},more} Batched{old,t,+p}:
      batch(more,theta,Batched{scale(terms,p,old),B.masked(t,p,y),A.mul(theta,p)})

def weight(fs: F.Form, +i: Nat, acc: E.E3) -> E.E3:
  match fs:
    case []: acc
    case F.Term{w,f} <> more: weight(more,i,A.add(acc,X.entry(f,i,w)) )

def unit(bits: Nat, pos: Nat, coeff: E.E3) -> F.Term: F.Term{coeff,X.choice(bits,pos)}

# Insert the group's aligned block selector above an oracle's own low row bits.
def insert(fs: F.Form, +at: Nat, +n: Nat, +idx: Nat, acc: F.Form) -> F.Form:
  match fs:
    case []: acc
    case F.Term{w,+f} <> rest:
      f2 = List.append(&2,F.Factor,List.take(&2,F.Factor,f,at),List.append(&2,F.Factor,X.choice(n,idx),List.drop(&2,F.Factor,f,at)))
      insert(rest,at,n,idx,F.Term{w,f2} <> acc)

def used(part: Bool, member: Member) -> Nat:
  Member{_,n,_,m,kept} = member
  Bool.pick(Nat,part,m,Bool.pick(Nat,kept,0n,n))

def rank(ms: Members, +before: Bool, +part: Bool, +id: Nat, +block: Nat, acc: Nat) -> Nat:
  match ms:
    case []: acc
    case Member{+j,n,d,m,k} <> tail:
      +len = O.ceil_power(used(part,Member{j,n,d,m,k}))
      +earlier = before && Bool.not(Nat.is_eq(id,j))
      inc = Nat.is_lt(block,len) || (earlier && Nat.is_eq(block,len))
      rank(tail,earlier,part,id,block,Nat.add(acc,Bool.pick(Nat,inc,len,0n)))

def lookup(+id: Nat, ms: Members) -> Maybe<&2,Member>:
  match ms:
    case []: None{}
    case Member{+j,n,d,m,k} <> rest:
      Maybe.or(&2,Member,Bool.pick(Maybe<&2,Member>,Nat.is_eq(id,j),Some{Member{j,n,d,m,k}},None{}),lookup(id,rest))

type Layout is Data:
  Layout{members: Members, row_bits: Nat, mask_bits: Nat, col_bits: Nat, mask_col_bits: Nat}
type Group is Data:
  Group{main: F.Form, mask: F.Form, kept: Forms, target: E.E3}

def assigned(id: Nat, mask: Bool, stays: Bool, fs: F.Form, v: Nat, bits: Nat, which: Nat, group: Group, valid: Bool) -> Maybe<&2,Group>:
  match mask stays group valid:
    case _ _ _ False{}: None{}
    case True{} _ Group{m,ds,k,t} True{}: Some{Group{m,insert(fs,v,bits,which,ds),k,t}}
    case False{} True{} Group{m,ds,k,t} True{}: Some{Group{m,ds,On{id,False{},fs} <> k,t}}
    case False{} False{} Group{m,ds,k,t} True{}: Some{Group{insert(fs,v,bits,which,m),ds,k,t}}

def place(+lay: Layout, +o: On, mem: Maybe<&2,Member>, group: Group) -> Maybe<&2,Group>:
  match lay o mem group:
    case Layout{+ms,k,h,p,q} On{+id,+mask,+fs} Some{Member{_,n,_,m,+keep}} Group{main,masks,kept,target}:
      +length = Bool.pick(Nat,mask,m,n)
      +v = C.bits(O.ceil_power(length))
      +bits = Bool.pick(Nat,mask,h,k)
      +offset = rank(ms,True{},mask,id,O.ceil_power(length),0n)
      +stays = keep && Bool.not(mask)
      good = Nat.is_lt(0n,length) && F.fits(fs,Nat.add(v,Bool.pick(Nat,mask,q,p))) &&
        (stays || Nat.is_le(Nat.add(offset,O.ceil_power(length)),C.size(bits)))
      assigned(id,mask,stays,fs,v,Nat.sub(bits,v),Nat.div(offset,C.size(v)),Group{main,masks,kept,target},good)
    case _ _ _ _: None{}

def place_all(+lay: Layout, fs: Forms, acc: Maybe<&2,Group>) -> Maybe<&2,Group>:
  match lay fs acc:
    case _ Nil{} old: old
    case Layout{+ms,+k,+h,+p,+q} Con{On{+id,mask,f},tail} Some{st}:
      +ctx: Layout = Layout{ms,k,h,p,q}
      place_all(ctx,tail,place(ctx,On{id,mask,f},lookup(id,ms),st))
    case _ _ _: None{}

def grouped(lay: Layout, row: Batched) -> Maybe<&2,Group>:
  Batched{fs,target,_} = row
  place_all(lay,fs,Some{Group{[],[],[],target}})

type Closed is Data:
  Closed{single: F.Single, kept: Forms}

# FOLD scales every kept main table by epsilon times the product of (1 - gamma_i).
def close(row: Group, +gamma: B.Elements, +h: Nat, +mask_len: Nat, +eps: E.E3, target: E.E3) -> Closed:
  Group{m,mask,keep,_} = row
  initial: F.Claim = F.Claim{m,F.expand(mask,C.zeros(Nat.mul(mask_len,C.size(h)))),F.zero()}
  Closed{F.finish(initial,gamma,h,mask_len,eps,target),scale(keep,C.front(gamma,eps),[])}
