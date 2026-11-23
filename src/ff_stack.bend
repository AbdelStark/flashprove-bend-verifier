import Base
import ./ff_stack_panels.bend as S
import ./ff_shape.bend as G
import ./ff_reads.bend as Read
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./policy_statement.bend as Statement
import ./row_tensor.bend as T
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F
import ./header.bend as H

type DataAt is Data:
  At{shape:G.Shape,key:B.Elements,group:Nat,layers:Nat,scales:List<&2,U32>,term_ends:A.Values,
    stack:A.Values,point:B.Elements,delta:X.E3}

type Sides is Data:
  Sides{left:A.Aff,right:A.Aff,shown_left:X.E3,shown_right:X.E3}

def fold_eq(+z:B.Elements) -> B.Elements: F.factor_table(T.eq(z),F.one())
def shown(+vs:A.Values,+i:Nat) -> X.E3: A.scalar(A.at(vs,i))
def shift_word(+x: X.E3,+n:Nat,+word:U32,+acc:X.E3) -> X.E3:
  match n:
    case 0n: acc
    case 1n++k:
      +a = E.mul(acc,acc)
      +v = x
      shift_word(v,k,word,Bool.pick(X.E3,U32.is_zero(U32.and(1,U32.shrn(word,k))),a,E.mul(a,v)))

# Fermat inverse in F_(p^3); the exponent p^3-2 is split into 32-bit words.
def inverse(+x: X.E3) -> X.E3:
  a = shift_word(x,32n,4294967293,F.one())
  b = shift_word(x,32n,5,a)
  c = shift_word(x,32n,4294967289,b)
  d = shift_word(x,32n,5,c)
  e = shift_word(x,32n,4294967292,d)
  shift_word(x,32n,4294967295,e)

def indices(+s:G.Shape) -> Nat: Nat.add(2n,G.field(s,"LamM"))
def v0(+s:G.Shape) -> Nat: 1n+indices(s)

def short_read(+s:G.Shape,+name:String,+point:String,+lam:Nat,+w:B.Elements,+n:Nat) -> A.Aff:
  +tensor = G.tensor(s,name)
  Read.walk(w,n,tensor,Read.table(s,tensor,point),1n,lam,0n,[])

def token_index(+s:G.Shape,+lam:Nat,+k:Nat) -> Nat:
  match k:
    case 8n: Nat.mul(2n,lam)
    case 9n: 1n+Nat.mul(2n,lam)
    case _: Nat.add(Nat.mul(2n,G.field(s,"Lam")),Nat.div(lam,2n))

def short_name(+k:Nat) -> String:
  match k:
    case 2n: "o"
    case 4n: "a"
    case 6n: "xr"
    case 7n: "xr"
    case 11n: "a"
    case _: "m"

def ew_sum(+s:G.Shape,+key:B.Elements,+k:Nat) -> X.E3:
  +ws = Read.ws(s,key,S.name(k),0n)
  Bool.pick(X.E3,Nat.is_eq(k,13n),A.sum(ws,F.zero()),A.get(ws,0n))

def term_B(+s:G.Shape,+key:B.Elements,+k:Nat,+lam:Nat,+ys:B.Elements,+n:Nat) -> A.Aff:
  match k:
    case 8n: Read.xs(s,key,"N1","Y",Nat.mul(2n,lam))
    case 9n: Read.xs(s,key,"N2","Y",1n+Nat.mul(2n,lam))
    case 12n: short_read(s,"m","rt",lam,Read.ws(s,key,"XR",0n),G.field(s,"d"))
    case _: short_read(s,"lr","rt",Nat.div(lam,2n),ys,n)

def select_values(+vs:A.Values,+ys:B.Elements,+n:Nat,+start:Nat,+acc:X.E3) -> X.E3:
  match vs ys n start:
    case _ _ 0n _: acc
    case Con{v,tail} +weights +count 1n+k: select_values(tail,weights,count,k,acc)
    case Con{v,tail} Con{w,more} 1n+k 0n: select_values(tail,more,k,0n,B.masked(acc,w,A.scalar(v)))
    case _ _ _ _: acc

def selector(+s:G.Shape,+terms:A.Values,+lm:Nat,+ys:B.Elements) -> X.E3:
  +n = G.field(s,"NE")
  offset = Nat.add(Nat.add(Nat.mul(2n,G.field(s,"Lam")),G.field(s,"LamM")),Nat.mul(lm,n))
  select_values(terms,ys,n,offset,F.zero())

def project(+s:G.Shape,+ts:A.Values,+lam:Nat,+k:Nat,+ys:B.Elements,+n:Nat) -> A.Aff:
  match k:
    case 8n: A.const(shown(ts,token_index(s,lam,k)))
    case 9n: A.const(shown(ts,token_index(s,lam,k)))
    case 12n: A.const(shown(ts,token_index(s,lam,k)))
    case 13n: A.const(selector(s,ts,Nat.div(lam,2n),ys))
    case 14n: A.const(selector(s,ts,Nat.div(lam,2n),ys))
    case _:
      short_read(s,short_name(k),Bool.pick(String,S.second(k),"rt","zt"),lam,ys,n)

def projected(+d:DataAt,+k:Nat,+row:Nat,+ys:B.Elements,+n:Nat) -> A.Aff:
  At{s,_,_,_,_,ts,_,_,_} = d
  project(s,ts,S.layer(k,row,0n),k,ys,n)

def row_weight(+d:DataAt,+k:Nat,+lam:Nat) -> X.E3:
  At{+s,+key,g,layers,kl,_,_,_,_} = d
  index = Nat.add(Nat.mul(g,G.field(s,"Lam")),lam)
  factor = Bool.pick(Unit -> X.E3,Nat.is_le(13n,k),_ => ew_sum(s,key,k),_ => S.shift(kl,layers,index,k))
  E.mul(G.el(s,key,S.name(k),lam),factor(Unit{}))

def regular_right(+d:DataAt,+k:Nat,+row:Nat,+n:Nat,+ys:B.Elements,+scale:X.E3,+right:A.Aff) -> A.Aff:
  At{s,key,_,_,_,_,_,_,_} = d
  A.add(right,term_B(s,key,k,S.layer(k,row,0n),ys,n),scale)

def regular(+d:DataAt,+k:Nat,+row:Nat,+nv:Nat,+n:Nat,+ys:B.Elements,+sb:X.E3,+ec:X.E3,+co:X.E3,+ei:X.E3,+ss:Sides) -> Sides:
  At{+s,_,_,_,_,_,ends,_,_} = d
  Sides{l,r,a,b} = ss
  +p = row_weight(d,k,S.layer(k,row,0n))
  +sw = E.mul(sb,ei)
  +v = shown(ends,Nat.add(v0(s),Nat.add(nv,row)))
  +weighted = S.weighted(k)
  write = Bool.pick(Unit -> A.Aff,weighted,_ => r,_ => regular_right(d,k,row,n,ys,sw,r))
  rhs = Bool.pick(X.E3,weighted,B.masked(b,sw,v),b)
  term = Bool.pick(Unit -> A.Aff,Nat.is_eq(k,3n),_ => l,_ => A.add(l,projected(d,k,row,ys,n),E.mul(co,E.mul(ei,p))))
  Sides{term(Unit{}),write(Unit{}),a,Bool.pick(X.E3,Nat.is_eq(k,3n),B.masked(b,E.mul(sw,E.mul(ec,p)),v),rhs)}

def row_loop(+d:DataAt,+k:Nat,+nv:Nat,+n:Nat,+ys:B.Elements,+sb:X.E3,+ec:X.E3,+co:X.E3,
    +is_:B.Elements,+left:Nat,+i:Nat,+ss:Sides) -> Sides:
  match is_ left:
    case Con{x,tail} 1n+j:
      +idx = i
      row_loop(d,k,nv,n,ys,sb,ec,co,tail,j,1n+idx,regular(d,k,idx,nv,n,ys,sb,ec,co,x,ss))
    case _ _: ss

def routed(+d:DataAt,+k:Nat,+lm:Nat,+nv:Nat,+n:Nat,+ys:B.Elements,+is_:B.Elements,+sb:X.E3,+co:X.E3,+ss:Sides) -> Sides:
  At{+s,_,_,_,_,ts,+ends,_,_} = d
  Sides{l,r,a,b} = ss
  +w = E.mul(co,E.mul(row_weight(d,k,1n+Nat.mul(2n,lm)),selector(s,ts,lm,is_)))
  +v = B.masked(b,sb,shown(ends,Nat.add(v0(s),nv)))
  call = Bool.pick(Unit -> Sides,Nat.is_eq(k,10n),_ => Sides{l,r,B.masked(a,w,shown(ends,2n+lm)),v},
    _ => Sides{A.add(l,short_read(s,"xr","rt",lm,ys,n),w),r,a,v})
  call(Unit{})

def ordinary(+d:DataAt,+k:Nat,+nv:Nat,+ni:Nat,+ny:Nat,+ys:B.Elements,+is_:B.Elements,+sb:X.E3,+ec:X.E3,+co:X.E3,+hh:X.E3,+ss:Sides) -> Sides:
  Sides{l,r,a,b} = ss
  s : Sides = Sides{l,r,Bool.pick(X.E3,Nat.is_eq(k,3n),B.masked(a,sb,hh),a),b}
  row_loop(d,k,nv,ny,ys,sb,ec,co,is_,ni,0n,s)

def panel(+d:DataAt,+all:S.Panels,+p:S.Panel,+ss:Sides) -> Sides:
  At{+s,+key,_,_,_,_,+ends,+point,delta} = d
  S.Panel{S.Spec{+k,lm},+nv,+ni,+ny,+width,+wy,ordinal} = p
  idx = Nat.div(S.offset(all,width,ordinal,0n),A.size(width))
  +sb = T.entry(T.eq(List.drop(&2,X.E3,point,width)),idx,F.one())
  +ec = G.ec(s,key,S.name(k))
  +co = E.mul(sb,E.mul(ec,Bool.pick(X.E3,S.second(k),delta,F.one())))
  +ys = fold_eq(F.take(X.E3,point,wy))
  +is_ = fold_eq(A.slice(point,wy,Nat.sub(width,wy)))
  go = Bool.pick(Unit -> Sides,S.route(k),_ => routed(d,k,lm,nv,ny,ys,is_,sb,co,ss),
    _ => ordinary(d,k,nv,ni,ny,ys,is_,sb,ec,co,shown(ends,1n),ss))
  go(Unit{})

def walk(+xs:S.Panels,+all:S.Panels,+d:DataAt,+ss:Sides) -> Sides:
  match xs:
    case []: ss
    case p <> tail: walk(tail,all,d,panel(d,all,p,ss))

def result(+out:Sides,+c:P.Check,+start:A.Aff,+first:A.Aff,+last:A.Aff) -> A.Equations:
  Sides{a,b,x,y} = out
  [P.row(c,start,E.mul(x,y)),A.minus(first,a),A.minus(last,b)]

def run(+s:G.Shape,+link:Nat,+key:B.Elements,+st:Statement.Statement,+join:A.Aff,+terms:P.Check,+delta:X.E3,+stack:P.Check) -> IO(A.Equations):
  Statement.Statement{_,_,_,_,+kl,_,_,_} = st
  P.Check{_,_,ts,_,relation} = terms
  +eps = A.get(relation,1n)
  +ends = P.ends(stack)
  +b = indices(s)
  +cl = A.slot(P.prefix(terms),0n)
  kt = P.row(terms,cl,F.zero())
  start = A.add(A.minus(join,cl),kt,E.negate(E.mul(delta,inverse(eps))))
  +panels = S.panels(s)
  d : DataAt = At{s,key,Nat.div(link,2n),Nat.div(Nat.mul(F.count(U32,kl,0n),2n),29n),kl,ts,ends,A.rev(P.point(stack)),delta}
  do IO<A.Equations>:
    ok : Unit <- H.require(Bool.not(B.equal(eps,F.zero())),"NO: g-stack-inverse")
    out : Sides = walk(panels,panels,d,Sides{A.zero(),A.zero(),shown(ends,0n),shown(ends,b)})
    return result(out,stack,start,A.slot(ends,0n),A.slot(ends,b))
