import Base
import ./ff_shape.bend as G
import ./ff_reads.bend as Read
import ./ff_rounds.bend as R
import ./norm_digits.bend as D
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./segment_attention_scores.bend as C
import ./fold.bend as F
import ./extension.bend as X
import ./base_check.bend as B
import ./sumcheck.bend as E

# Absolute location of the first of a norm's 99 digits in U3.
def start(t:G.Tensor,i:Nat) -> Nat:
  G.Tensor{_,off,_,_,stride} = t
  Nat.add(off,Nat.mul(i,stride))
def digits(+s:G.Shape,point:String,i:Nat) -> Nat:
  Nat.add(G.head_cols(s,"ar",point),start(G.tensor(s,"row"),i))
def recip(s:G.Shape,point:String,i:Nat) -> A.Aff: D.recip(digits(s,point,i))

def product(+c:P.Check,start:A.Aff) -> A.Aff: P.product_row(c,start,[F.one()])
def scale_w(n:Nat,+rho:B.Elements,+vs:A.Values,+gp:B.Elements,+scale:X.E3,acc:A.Aff) -> A.Aff:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      w = E.mul(scale,A.eq(rho,i))
      v = A.weighted(vs,gp,1n,Nat.mul(i,9n),A.zero())
      scale_w(i,rho,vs,gp,scale,A.add(acc,v,w))

def lane(t:G.Tensor,i:Nat,l:Nat) -> Nat:
  G.Tensor{_,off,_,cnt,width} = t
  Nat.add(off,Nat.mul(Nat.add(Nat.mul(i,cnt),l),width))
def limbset(n:Nat,+t:G.Tensor,+unit:Nat,+point:B.Elements,+scl:X.E3,+base:Nat,+layer:Nat,+col:Nat,acc:A.Aff) -> A.Aff:
  # Gamma supplies the radix for this read. The index assigned to the
  # equality polynomial uses the padded layer stride Pd/S2.
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      addr = lane(t,i,layer)
      id = Nat.add(base,Nat.add(Nat.div(addr,unit),col))
      w = E.mul(scl,A.get(point,i))
      limbset(i,t,unit,point,scl,base,layer,col,A.add(acc,Read.cell(id,w),F.one()))
def pack(n:Nat,+s:G.Shape,+at:B.Elements,+gamma:B.Elements,acc:A.Aff) -> A.Aff:
  match n:
    case 0n: acc
    case 1n+k:
      +j = k
      +u = G.field(s,"S2")
      +width = Nat.div(G.field(s,"d"),u)
      +i = Nat.div(j,width)
      +col = Nat.mod(j,width)
      +first = Nat.is_eq(i,0n)
      weight = A.eq(at,Nat.add(Nat.mul(i,Nat.div(G.field(s,"Pd"),u)),col))
      t = G.tensor(s,Bool.pick(String,first,"xb","xs"))
      base = G.head_cols(s,Bool.pick(String,first,"xbI","af"),"Z_V")
      new = limbset(5n,t,u,gamma,weight,base,Nat.sub(i,1n),col,acc)
      pack(j,s,at,gamma,new)
def squares(+s:G.Shape,+r:R.Level,values:A.Values,+gam:X.E3,rho:B.Elements) -> A.Equations:
  +ni = G.field(s,"NI")
  +l = R.check(r)
  z = List.take(&2,X.E3,R.at(r),Nat.sub(Nat.add(G.field(s,"lNI"),G.field(s,"lPd")),G.field(s,"ls")))
  +vs = P.ends(l)
  gp = A.powers(9n,gam,F.one())
  init = scale_w(ni,rho,values,gp,D.powers(G.field(s,"lPd"),P.half(),F.one()),A.zero())
  used = Nat.mul(ni,Nat.div(G.field(s,"d"),G.field(s,"S2")))
  [product(l,init),A.minus(A.slot(vs,0n),A.slot(vs,1n)),A.minus(A.slot(vs,0n),pack(used,s,z,A.powers(5n,gam,F.one()),A.zero()))]

def drop(v:A.Values,n:Nat) -> A.Values: List.drop(&2,A.Value,v,n)
def produces(n:Nat,vs:A.Values,+omega:X.E3,+w:X.E3,+step:X.E3,acc:X.E3) -> X.E3:
  match n:
    case 0n: acc
    case 1n+k:
      +ends = vs
      produces(k,drop(ends,4n),omega,E.mul(w,step),step,E.add(acc,E.mul(w,D.products(ends,omega))))
type DigitData is Data:
  Digits{shape:G.Shape,shows:A.Values}
def showed(data:DigitData,j:Nat) -> A.Aff:
  Digits{s,v} = data
  +k = j
  +t = digits(s,"r_tV",Nat.div(k,4n))
  +z = Nat.mod(k,4n)
  rhs = Bool.pick(A.Aff,Nat.is_lt(z,2n),Bool.pick(A.Aff,Nat.is_eq(z,0n),D.low(t),D.high(t)),D.word(t,Nat.add(80n,Nat.mul(3n,Nat.sub(z,2n))),3n))
  A.minus(A.slot(v,k),rhs)
def carries(n:Nat,+s:G.Shape,+ws:A.Values,acc:A.Equations) -> A.Equations:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      carries(i,s,ws,C.cat(D.carries(digits(s,"P_V",i),drop(ws,Nat.mul(9n,i)),9n,0n),acc))
def mf(scales:List<&2,U32>,layer:Nat,kind:Nat) -> Nat:
  i = Nat.add(Nat.mul(13n,layer),Nat.add(7n,Nat.mul(2n,kind)))
  U32.to_nat(Maybe.default(&2,U32,List.get(&2,U32,scales,i),0))
def ledger(n:Nat,+s:G.Shape,+g:Nat,+scales:List<&2,U32>,+p:A.Values,acc:A.Equations) -> A.Equations:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      +sel = Nat.mod(i,2n)
      eps = G.field(s,Bool.pick(String,Nat.is_eq(sel,0n),"eps1","eps2"))
      layer = Nat.add(Nat.mul(g,G.field(s,"Lam")),Nat.div(i,2n))
      rs = D.lines(digits(s,"P_V",i),drop(p,Nat.mul(7n,i)),eps,mf(scales,layer,sel))
      ledger(i,s,g,scales,p,C.cat(rs,acc))
def rows(+s:G.Shape,group:Nat,scales:List<&2,U32>,+check:P.Check,p:A.Values,omega:X.E3,ws:A.Values) -> A.Equations:
  +ni = G.field(s,"NI")
  +vals = p
  +v = P.ends(check)
  +w = omega
  +cl = A.slot(P.prefix(check),0n)
  s0 = produces(ni,v,w,F.one(),D.powers(7n,w,F.one()),F.zero())
  st = D.weighted(vals,w,F.one(),A.zero())
  rest = carries(ni,s,ws,ledger(ni,s,group,scales,vals,[]))
  A.minus(cl,st) <> P.row(check,cl,s0) <> C.each(DigitData,showed,Digits{s,v},Nat.mul(4n,ni),rest)
