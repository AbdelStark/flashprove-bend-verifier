import Base
import ./ff_shape.bend as G
import ./segment_attention_psc.bend as P
import ./segment_attention_rounds.bend as R
import ./segment_attention_points.bend as Z
import ./segment_attention_aff.bend as A
import ./key_stage_lookup_levels.bend as V
import ./key_stage_psc.bend as PSC
import ./extension.bend as X
import ./fold.bend as F
import ./base_check.bend as B
import ./hash_bytes.bend as H

# G receives three product layers. Their public points are written high bit
# first. Restore that order after the two gated layers sample the low 9 bits first.
type Level is Data:
  Level{psc:P.Check,point:B.Elements}
type Reading is Data:
  Reading{layer:Level,next:P.Cursor}
type Levels is Data:
  Levels{squares:Level,gate:Level,routed:Level}
type Tokens is Data:
  Tokens{products:P.Check,terms:P.Check,stack:P.Check}
type Coins is Data:
  Coins{w:A.Values,p:A.Values,gamma:X.E3,omega:X.E3,delta:X.E3}
type Points is Data:
  Points{pv:B.Elements,rho:B.Elements,experts:B.Elements,ze:B.Elements,tkh:B.Elements}
type Heard is Data:
  Heard{levels:Levels,tokens:Tokens,coins:Coins,points:Points,merge:P.Coin}

def last(+p:B.Elements,n:Nat) -> B.Elements:
  List.drop(&2,X.E3,p,Nat.sub(List.length(&2,X.E3,p),n))
def suffix(+s:G.Shape,key:B.Elements,k:String) -> B.Elements:
  A.rev(A.slice(key,G.field(s,"forest_top"),G.field(s,k)))
def optional(cur:P.Cursor,name:String,n:Nat) -> IO(P.Coin):
  match n:
    case 0n: IO.pure(P.Coin,P.Coin{[],[],cur})
    case 1n+k: P.coin(cur,name,0n,1n+k)
def level(cur:P.Cursor,+rho:B.Elements,first:H.Bytes) -> IO(Reading):
  +order = V.order(List.length(&2,X.E3,rho),first)
  do IO<Reading>:
    vars : List<&2,PSC.Variable> <- V.equals(order,A.rev(rho),2n)
    +r : P.Read <- P.with_variables(cur,0n,vars,2n,2n)
    line : P.Coin <- P.coin(R.next(r),"LINE",0n,1n)
    +check : P.Check = R.checked(r)
    return Reading{Level{check,A.rev(V.restore(order,P.point(check)))},R.next_coin(line)}
def equality(cur:P.Cursor,pre:Nat,point:B.Elements,y:Nat,n:Nat) -> IO(P.Read):
  P.with_variables(cur,pre,P.eqs(point),y,n)
def result(p:Reading) -> Level:
  Reading{l,_} = p
  l
def after(p:Reading) -> P.Cursor:
  Reading{_,t} = p
  t
def ranges() -> H.Bytes: [2,1,0,5,4,3,8,7,6]
def check(l:Level) -> P.Check:
  Level{c,_} = l
  c
def at(l:Level) -> B.Elements:
  Level{_,p} = l
  p

def receive(cur:P.Cursor,+s:G.Shape,+key:B.Elements,+initial:Bool) -> IO(Heard):
  +lt = G.field(s,"lt")
  +d = G.field(s,"lPd")
  +ni = G.field(s,"NI")
  +ll = G.field(s,"ll")
  +mf = G.field(s,"LamM")
  +zt = suffix(s,key,"lt")
  +pre = Bool.pick(Nat,initial,1n,0n)
  nstack = Nat.sub(Nat.add(Nat.add(3n,mf),G.field(s,"NCL")),pre)
  nterms = Nat.add(ni,Nat.mul(mf,1n+G.field(s,"NE")))
  do IO<Heard>:
    +pv : P.Coin <- P.coin(cur,"ZERO",0n,lt)
    +ze : P.Coin <- optional(R.next_coin(pv),"ZERO",Bool.pick(Nat,initial,G.field(s,"la"),0n))
    +tkh : P.Coin <- optional(R.next_coin(ze),"ZERO",Bool.pick(Nat,initial,Nat.sub(d,G.field(s,"ls")),0n))
    +w : P.Coin <- P.coin(R.next_coin(tkh),"BAT-sigma",Nat.mul(G.field(s,"NS"),ni),1n)
    +rho : P.Coin <- optional(R.next_coin(w),"JOIN",G.field(s,"lNI"))
    +pair : Reading <- level(R.next_coin(rho),Z.cat(R.points(rho),Z.cat(List.replicate(X.E3,d,P.half()),R.points(pv))),[])
    squares : Level = result(pair)
    next : P.Cursor = after(pair)
    +p : P.Coin <- P.coin(next,"BAT-sigma",Nat.mul(G.field(s,"NPr"),ni),1n)
    +tv : P.Read <- equality(R.next_coin(p),1n,R.points(pv),2n,Nat.mul(ni,G.field(s,"NO")))
    +tt : P.Read <- equality(R.next(tv),1n,zt,1n,nterms)
    +delta : P.Coin <- P.coin(R.next(tt),"BAT-sigma",0n,1n)
    +stack : P.Read <- P.parse(R.next_coin(delta),0n,List.replicate(Nat,G.field(s,"lamS"),2n),2n,nstack)
    +rs : B.Elements = P.point(R.checked(stack))
    +gpair : Reading <- level(R.next(stack),Z.cat(last(rs,Nat.add(ll,G.field(s,"lPf"))),zt),ranges())
    gate : Level = result(gpair)
    next2 : P.Cursor = after(gpair)
    +expert : P.Coin <- optional(next2,"JOIN",Nat.sub(ll,1n))
    +epair : Reading <- level(R.next_coin(expert),Z.cat(R.points(expert),Z.cat(last(rs,G.field(s,"lfe")),P.point(R.checked(tt)))),ranges())
    routed : Level = result(epair)
    next3 : P.Cursor = after(epair)
    merge : P.Coin <- P.coin(next3,"BAT-sigma",pre,1n)
    return Heard{Levels{squares,gate,routed},Tokens{R.checked(tv),R.checked(tt),R.checked(stack)},
      Coins{R.declared(w),R.declared(p),R.challenge(w),R.challenge(p),R.challenge(delta)},
      Points{R.points(pv),R.points(rho),R.points(expert),R.points(ze),R.points(tkh)},merge}
