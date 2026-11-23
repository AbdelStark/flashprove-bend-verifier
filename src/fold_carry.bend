import Base
import ./fold_frame.bend as R
import ./fold_cs.bend as C
import ./fold_open.bend as O
import ./fold.bend as F
import ./base_check.bend as B
import ./extension.bend as E
import ./sumcheck.bend as A
import ./goldilocks.bend as G
import ./row_tensor.bend as X
import ./code_eval.bend as Code
import ./transcript.bend as T

# R12.16. After a segment, g has exactly two extension main rows under the same code.
# Row 0 receives the old main message. Row 1 receives the rest, and reserves its last entry for SEND.
type Kept is Data:
  Kept{old_id: Nat, new_id: Nat, rows: Nat, degree: Nat, sample: F.Form, answer: E.E3}
def Keeps() -> Data: List<&2,Kept>
type Site is Data:
  Site{kept: Kept, tail_at: Nat, pad_at: Nat}
type Switch is Data:
  Switch{g: Nat, main: B.Code, mask: B.Code, sites: List<&2,Site>, main_tail: Nat, mask_tail: Nat}
type Opening is Data:
  Opening{folded: C.Draw, kept_symbols: B.Elements}
type Equations is Data:
  Equations{plain: List<&2,R.Equation>, generators: List<&2,R.Equation>}

def pad_count(deg: Nat) -> Nat: Bool.pick(Nat,Nat.is_eq(deg,1n),3n,1n)
def number(xs: Keeps, rows: Nat, pads: Nat) -> Nat & Nat:
  match xs:
    case []: (rows,pads)
    case Kept{_,_,n,d,_,_} <> more: number(more,Nat.add(rows,n),Nat.add(pads,pad_count(d)))

def sites(xs: Keeps, +r: Nat, +t: Nat, +p: Nat) -> List<&2,Site>:
  match xs:
    case []: []
    case Kept{a,b,+n,+d,form,y} <> tail:
      Site{Kept{a,b,n,d,form,y},t,p} <> sites(tail,r,Nat.add(t,Nat.mul(n,r)),Nat.add(p,pad_count(d)))

def lawful(xs: Keeps, +ell: Nat, +bits: Nat) -> Bool:
  match xs:
    case []: True{}
    case Kept{_,_,+n,+d,form,_} <> rest:
      Nat.is_lt(0n,n) && (Nat.is_eq(d,1n) || Nat.is_eq(d,3n)) && Nat.is_le(pad_count(d),ell) &&
        F.fits(form,Nat.add(bits,C.bits(O.ceil_power(n)))) && lawful(rest,ell,bits)

def make(n: Nat & Nat, g: Nat, main: B.Code, mask: B.Code, +ks: Keeps) -> Maybe<&2,Switch>:
  (rows,pads) = n
  B.Code{+a,+m,+r} = main
  B.Code{+b,+n,+s} = mask
  +main_t = Nat.mul(2n,n)
  +kept_t = Nat.add(main_t,r)
  +mask_t = Nat.add(kept_t,Nat.mul(rows,r))
  +pad = Nat.add(mask_t,Nat.mul(2n,s))
  ok = B.code_ok(B.Code{a,m,r}) && B.code_ok(B.Code{b,n,s}) && Nat.is_le(b,a) && C.power_two(m) && C.power_two(n) &&
    Nat.is_lt(Nat.add(pad,pads),m) && lawful(ks,m,C.bits(m))
  sw: Switch = Switch{g,B.Code{a,m,r},B.Code{b,n,s},sites(ks,r,kept_t,pad),main_t,mask_t}
  Bool.pick(Maybe<&2,Switch>,ok,Some{sw},None{})

def frame(g: Nat, main: B.Code, mask: B.Code, +kept: Keeps) -> Maybe<&2,Switch>:
  make(number(kept,0n,0n),g,main,mask,kept)

def on_row(fs: F.Form, row: Nat) -> F.Form: R.insert(fs,0n,1n,row,[])

# Dense parts of the carried claim skip zeros. The sparse terms fix their place before row embedding.
def weights(xs: B.Elements, +bits: Nat, +pos: Nat, +acc: F.Form) -> F.Form:
  match xs:
    case []: acc
    case +x <> rest:
      term = R.unit(bits,pos,x)
      weights(rest,bits,1n+pos,Bool.pick(F.Form,T.is_zero(x),acc,term <> acc))

def pad_index(+ell: Nat, +rows: Nat, +each: Nat, i: Nat) -> Nat:
  Nat.add(Nat.sub(rows,1n),Nat.mul(O.ceil_power(rows),Nat.add(Nat.sub(ell,each),i)))

# Subtract every old pad coefficient from the replacement oracle. Put the same coefficient
# at its assigned place in row 1 of g. The new oracle has its own independently sampled pad.
type Moved is Data:
  Moved{new_form: F.Form, rest: F.Form}
def pads(i: Nat, +ell: Nat, +rows: Nat, +each: Nat, +dest: Nat, +form: F.Form, acc: Moved) -> Moved:
  match i acc:
    case 0n st: st
    case 1n+old Moved{new,rest}:
      +j = old
      +at = pad_index(ell,rows,each,j)
      +val = R.weight(form,at,F.zero())
      rem = R.unit(Nat.add(C.bits(ell),C.bits(O.ceil_power(rows))),at,A.negate(val))
      add = R.unit(C.bits(ell),Nat.add(dest,j),val)
      pads(j,ell,rows,each,dest,form,Moved{rem <> new,add <> rest})

def unpack(moved: Moved, anew: Nat, g: Nat, acc: R.Forms) -> R.Forms:
  Moved{fs,rs} = moved
  R.On{anew,False{},fs} <> R.On{g,False{},on_row(rs,1n)} <> acc

def pieces(k: Site, +ell: Nat, +form: F.Form, g: Nat, acc: R.Forms) -> R.Forms:
  Site{Kept{_,anew,+rows,+d,_,_},_,start} = k
  moved = pads(pad_count(d),ell,rows,pad_count(d),start,form,Moved{form,[]})
  unpack(moved,anew,g,acc)

def member(+id: Nat, ks: List<&2,Site>) -> Maybe<&2,Site>:
  match ks:
    case []: None{}
    case Site{Kept{+old,anew,n,deg,fs,v},t,p} <> rest:
      Maybe.or(&2,Site,Bool.pick(Maybe<&2,Site>,Nat.is_eq(id,old),Some{Site{Kept{old,anew,n,deg,fs,v},t,p}},None{}),member(id,rest))

def transformed(site: Maybe<&2,Site>, ell: Nat, fs: F.Form, g: Nat, acc: R.Forms, mask: Bool) -> Maybe<&2,R.Forms>:
  match site mask:
    case Some{k} False{}: Some{pieces(k,ell,fs,g,acc)}
    case _ _: None{}

def transfer(xs: R.Forms, +ks: List<&2,Site>, +ell: Nat, +g: Nat, acc: Maybe<&2,R.Forms>) -> Maybe<&2,R.Forms>:
  match xs acc:
    case Nil{} st: st
    case Con{R.On{id,mask,fs},tail} Some{sofar}: transfer(tail,ks,ell,g,transformed(member(id,ks),ell,fs,g,sofar,mask))
    case _ _: None{}

def original(ks: List<&2,Site>, +ell: Nat, +g: Nat) -> List<&2,R.Equation>:
  match ks:
    case []: []
    case Site{Kept{a,b,n,d,+fs,+y},t,p} <> tail:
      site: Site = Site{Kept{a,b,n,d,[],F.zero()},t,p}
      R.Equation{pieces(site,ell,fs,g,[]),y} <> original(tail,ell,g)

def prepend(fs: Maybe<&2,R.Forms>, t: E.E3, tail: List<&2,R.Equation>, good: Bool) -> Maybe<&2,List<&2,R.Equation>>:
  match fs good:
    case Some{on} True{}: Some{R.Equation{on,t} <> tail}
    case _ _: None{}

def carried(sw: Switch, c: R.Closed) -> Maybe<&2,List<&2,R.Equation>>:
  Switch{+g,B.Code{_,+m,_},B.Code{_,+n,_},+ks,_,_} = sw
  R.Closed{F.Single{+fs,+d,+f,target},held} = c
  +bits = C.bits(m)
  rest = weights(f,bits,n,weights(d,bits,0n,[]))
  main = List.append(&2,F.Term,on_row(fs,0n),on_row(rest,1n))
  terms = transfer(held,ks,m,g,Some{[R.On{g,False{},main}]})
  good = F.fits(fs,bits) && Nat.is_eq(List.length(&2,E.E3,d),n) && Nat.is_eq(List.length(&2,E.E3,f),n)
  prepend(terms,target,original(ks,m,g),good)

# A stretch of code-generator coefficients on g's row 1. Represent each aligned dyadic
# piece as one tensor. The field step is a code point and the first coefficient is explicit.
def block(k: Nat, +i: Nat) -> Nat:
  match k:
    case 0n: 0n
    case 1n+left:
      +p = left
      Bool.pick(Nat,Nat.is_eq(Nat.mod(i,C.size(1n+p)),0n),1n+p,block(p,i))

def stretch(fuel: Nat, remaining: Nat, +bits: Nat, +pos: Nat, +z: G.Gl, +first: E.E3, acc: F.Form) -> F.Form:
  match fuel remaining:
    case _ 0n: acc
    case 1n+k 1n+left:
      +p = left
      +v = block(C.bits(1n+p),pos)
      +len = C.size(v)
      factors = List.append(&2,F.Factor,C.factors(v,z),X.choice(Nat.sub(bits,v),Nat.div(pos,len)))
      stretch(k,Nat.sub(1n+p,len),bits,Nat.add(pos,len),z,C.scale(C.pow(z,len),first),F.Term{first,factors} <> acc)
    case _ _: acc

def run(+bits: Nat, at: Nat, n: Nat, z: G.Gl, first: E.E3) -> F.Form:
  stretch(1n+Nat.mul(2n,bits),n,bits,at,z,first,[])

def msg(+bits: Nat, +z: G.Gl, r: Nat) -> F.Form:
  [F.Term{C.embed(C.pow(z,r)),C.factors(bits,z)}]

def main_generator(g: Nat, +bits: Nat, +z: G.Gl, at: Nat, +r: Nat, target: E.E3) -> R.Equation:
  terms = List.append(&2,F.Term,on_row(msg(bits,z,r),0n),on_row(run(bits,at,r,z,F.one()),1n))
  R.Equation{[R.On{g,False{},terms}],target}

def mask_generator(g: Nat, +bits: Nat, +z: G.Gl, msg_at: Nat, n: Nat, tail_at: Nat, +s: Nat, target: E.E3) -> R.Equation:
  table = run(bits,msg_at,n,z,C.embed(C.pow(z,s)))
  terms = on_row(List.append(&2,F.Term,table,run(bits,tail_at,s,z,F.one())),1n)
  R.Equation{[R.On{g,False{},terms}],target}

type Gens is Data:
  Gens{rows: List<&2,R.Equation>, remaining: B.Elements}
def kept_rows(count: Nat, +i: Nat, +g: Nat, +bits: Nat, +z: G.Gl, +r: Nat, +site: Site, +ell: Nat, +n: Nat, +at: Nat, st: Maybe<&2,Gens>) -> Maybe<&2,Gens>:
  match count st:
    case 0n acc: acc
    case 1n+k Some{Gens{acc,Con{x,rest}}}:
      fs = R.insert(msg(bits,z,r),0n,C.bits(O.ceil_power(n)),i,[])
      tail = on_row(run(bits,Nat.add(at,Nat.mul(i,r)),r,z,F.one()),1n)
      eq: R.Equation = R.Equation{pieces(site,ell,fs,g,[R.On{g,False{},tail}]),x}
      kept_rows(k,1n+i,g,bits,z,r,site,ell,n,at,Some{Gens{eq <> acc,rest}})
    case _ _: None{}

def kept_generators(ks: List<&2,Site>, +g: Nat, +bits: Nat, +z: G.Gl, +r: Nat, +ell: Nat, st: Maybe<&2,Gens>) -> Maybe<&2,Gens>:
  match ks:
    case []: st
    case Site{Kept{old,anew,+n,d,fs,v},+at,p} <> tail:
      site: Site = Site{Kept{old,anew,n,d,fs,v},at,p}
      kept_generators(tail,g,bits,z,r,ell,kept_rows(n,0n,g,bits,z,r,site,ell,n,at,st))

def mask_end(st: Maybe<&2,Gens>, +g: Nat, +bits: Nat, +z: G.Gl, +n: Nat, +s: Nat, +at: Nat, y: E.E3, f: E.E3) -> Maybe<&2,List<&2,R.Equation>>:
  match st:
    case Some{Gens{rest,Nil{}}}:
      old = mask_generator(g,bits,z,0n,n,at,s,y)
      fresh = mask_generator(g,bits,z,n,n,Nat.add(at,s),s,f)
      Some{fresh <> old <> rest}
    case _: None{}

def at(sw: Switch, d: Opening, p: Maybe<&2,G.Gl>, q: Maybe<&2,G.Gl>, st: Maybe<&2,List<&2,R.Equation>>) -> Maybe<&2,List<&2,R.Equation>>:
  match sw d p q st:
    case Switch{+g,B.Code{_,+m,+r},B.Code{_,n,s},ks,t,u} Opening{C.Draw{_,x,y,f},more} Some{+z} Some{mask} Some{acc}:
      +bits = C.bits(m)
      main = main_generator(g,bits,z,t,r,x)
      kept = kept_generators(ks,g,bits,z,r,m,Some{Gens{main <> acc,more}})
      mask_end(kept,g,bits,mask,n,s,u,y,f)
    case _ _ _ _ _: None{}

def symbol_rows(+sw: Switch, xs: List<&2,Opening>, +a: Nat, +b: Nat, acc: Maybe<&2,List<&2,R.Equation>>) -> Maybe<&2,List<&2,R.Equation>>:
  match xs:
    case []: acc
    case Opening{C.Draw{+i,x,y,f},more} <> rest:
      v = at(sw,Opening{C.Draw{i,x,y,f},more},Code.point(a,i),Code.point(b,Nat.mod(i,C.size(b))),acc)
      symbol_rows(sw,rest,a,b,v)

def combine(plain: Maybe<&2,List<&2,R.Equation>>, gens: Maybe<&2,List<&2,R.Equation>>) -> Maybe<&2,Equations>:
  match plain gens:
    case Some{p} Some{g}: Some{Equations{p,List.reverse(&2,R.Equation,g)}}
    case _ _: None{}

def switch(+sw: Switch, closed: R.Closed, xs: List<&2,Opening>) -> Maybe<&2,Equations>:
  Switch{_,B.Code{a,_,_},B.Code{b,_,_},_,_,_} = sw
  combine(carried(sw,closed),symbol_rows(sw,xs,a,b,Some{[]}))
