import Base
import ./ff_shape.bend as G
import ./ff_reads.bend as Read
import ./segment_attention_aff.bend as A
import ./fold.bend as F
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./extension.bend as X
import ./hash_bytes.bend as H

# Each lookup segment is evaluated on one layer. full contains the weights
# on its placed columns, blocks those on S2-column groups.
type Context is Data:
  Context{s: G.Shape, lam: Nat, base: Nat, scales: H.Bytes, full: B.Elements, blocks: B.Elements, mass: X.E3}

def word(xs:H.Bytes,i:Nat) -> Nat: U32.to_nat(Maybe.default(&2,U32,List.get(&2,U32,xs,i),0))
def kl(c:Context,j:Nat) -> Nat:
  Context{_,_,g,ws,_,_,_} = c
  word(ws,Nat.add(Nat.mul(13n,g),j))

def klm(c:Context,j:Nat) -> Nat:
  Context{s,_,g,ws,_,_,_} = c
  word(ws,Nat.add(Nat.mul(13n,G.field(s,"L")),Nat.add(Nat.mul(3n,Nat.div(g,2n)),j)))

def field(c:Context,name:String) -> Nat:
  Context{s,_,_,_,_,_,_} = c
  G.field(s,name)
def lam(c:Context) -> Nat:
  Context{_,l,_,_,_,_,_} = c
  l
def moe(c:Context) -> Bool: Nat.is_eq(Nat.mod(lam(c),2n),1n)

def scale(a:A.Aff,n:Nat) -> A.Aff: A.scale(a,A.nat(n))
def shift(w:X.E3,n:Nat) -> A.Aff: A.const(E.mul(w,A.nat(n)))
def power(x:A.Aff,k:Nat) -> A.Aff: scale(x,A.size(k))
def weight(c:Context) -> X.E3:
  Context{_,_,_,_,_,_,w} = c
  w
def wvec(c:Context) -> B.Elements:
  Context{_,_,_,_,ws,_,_} = c
  ws
def sum(c:Context,+lo:Nat,hi:Nat) -> X.E3:
  A.sum(F.take(X.E3,List.drop(&2,X.E3,wvec(c),lo),Nat.sub(hi,lo)),F.zero())
def whole(c:Context,name:String) -> A.Aff:
  Context{s,l,_,_,_,w,_} = c
  Read.whole(s,w,name,"Z",l)
def sub(c:Context,name:String,lo:Nat,hi:Nat,bias:Nat) -> A.Aff:
  Context{s,l,_,_,_,w,_} = c
  Read.bounded(s,w,name,"Z",l,lo,hi,bias)
def stream(c:Context,i:Nat) -> A.Aff:
  Context{s,_,_,_,_,w,_} = c
  Read.residual(s,w,"Z",i)

def weighted(ws:B.Elements,+s:G.Shape,+name:String,+layer:Nat,i:Nat,acc:A.Aff) -> A.Aff:
  match ws:
    case []: acc
    case v <> tail:
      +j = i
      weighted(tail,s,name,layer,1n+j,A.add(acc,Read.sh(s,name,"zt",layer,j),v))
def short(c:Context,name:String,layer:Nat) -> A.Aff:
  Context{s,_,_,_,ws,_,_} = c
  weighted(ws,s,name,layer,0n,A.zero())
def at(c:Context,name:String,layer:Nat,index:Nat) -> A.Aff:
  Context{s,_,_,_,_,_,_} = c
  Read.sh(s,name,"zt",layer,index)

def offset(form:Nat) -> Nat: Bool.pick(Nat,Nat.is_eq(form,1n),128n,32896n)
def site(+w:X.E3,q:A.Aff,+k:Nat,+form:Nat,rem:A.Aff) -> A.Aff:
  base = power(A.minus(shift(w,A.size(Nat.sub(k,1n))),power(q,k)),Nat.sub(16n,k))
  tail = Bool.pick(A.Aff,Nat.is_eq(form,0n),A.zero(),power(A.plus(shift(w,offset(form)),rem),16n))
  A.minus(base,tail)
def high(w:X.E3,r:A.Aff,k:Nat,+form:Nat) -> A.Aff:
  top = Bool.pick(Nat,Nat.is_eq(form,1n),24n,32n)
  power(A.plus(shift(w,offset(form)),r),Nat.sub(top,Nat.max(k,16n)))

def dispatch(+upper:Bool,w:X.E3,q:A.Aff,k:Nat,f:Nat,r:A.Aff) -> A.Aff:
  match upper:
    case True{}: high(w,r,k,f)
    case False{}: site(w,q,k,f,r)

def panel(+c:Context,+up:Bool,upper:Bool,+lo:Nat,+hi:Nat,k:Nat) -> A.Aff:
  rem = sub(c,Bool.pick(String,up,"ru","rg"),lo,hi,0n)
  q = Bool.pick(Unit -> A.Aff,up,_ => sub(c,"u",lo,hi,0n),
    _ => A.plus(sub(c,"g0",lo,hi,0n),scale(sub(c,"gh",lo,hi,0n),256n)))
  dispatch(upper,sum(c,lo,hi),q(Unit{}),k,field(c,Bool.pick(String,up,"fU","fG")),rem)

def gate(+c:Context,+up:Bool,+upper:Bool) -> A.Aff:
  +f = field(c,"f")
  +fe = field(c,"fe")
  +k = kl(c,Bool.pick(Nat,up,5n,4n))
  run = Bool.pick(Unit -> A.Aff,moe(c),
    _ => A.plus(panel(c,up,upper,0n,fe,k),panel(c,up,upper,fe,f,klm(c,Bool.pick(Nat,up,2n,1n)))),
    _ => panel(c,up,upper,0n,f,k))
  run(Unit{})

def qpart(+c:Context,upper:Bool,+lo:Nat,+hi:Nat,k:Nat) -> A.Aff:
  dispatch(upper,sum(c,lo,hi),sub(c,"qkw",lo,hi,0n),k,field(c,"fQK"),sub(c,"rqk",lo,hi,0n))
def nqk(+c:Context) -> Nat: Nat.mul(Nat.add(field(c,"H"),field(c,"G")),field(c,"dh"))
def queries(+c:Context,+upper:Bool) -> A.Aff:
  +d = field(c,"dq")
  A.plus(qpart(c,upper,0n,d,kl(c,0n)),qpart(c,upper,d,nqk(c),kl(c,1n)))

def normal(+c:Context,+first:Bool,upper:Bool) -> A.Aff:
  dispatch(upper,weight(c),whole(c,Bool.pick(String,first,"aw","mw")),kl(c,Bool.pick(Nat,first,8n,10n)),2n,
    whole(c,Bool.pick(String,first,"ra","rm")))
def residual(+c:Context,delta:Nat,form:String,shift_col:Nat,rem:String) -> A.Aff:
  +j = Nat.add(Nat.mul(2n,lam(c)),delta)
  site(weight(c),A.minus(stream(c,1n+j),stream(c,j)),kl(c,shift_col),field(c,form),whole(c,rem))

def query_clamp(+c:Context) -> A.Aff:
  +d = field(c,"dq")
  A.plus(sub(c,"q",0n,d,0n),sub(c,"kx",d,nqk(c),d))
def clamp(c:Context,value:A.Aff,clipped:A.Aff) -> A.Aff:
  A.plus(A.plus(value,power(clipped,28n)),shift(weight(c),Nat.add(32768n,A.size(39n))))

# The ROW segment is two 99-digit, five-limb norm instances for a layer.
def mu(n:Nat) -> Nat:
  match n:
    case 9n: 4n
    case 58n: 2n
    case 59n: 128n
    case 63n: 2n
    case 76n: 2n
    case 79n: 32n
    case _: 1n
def row_(ws:B.Elements,+off:Nat,i:Nat,acc:A.Aff) -> A.Aff:
  match ws:
    case []: acc
    case v <> tail:
      +j = i
      entry = A.plus(Read.cell(Nat.add(off,j),F.one()),A.const(A.nat(128n)))
      row_(tail,off,1n+j,A.add(acc,entry,E.mul(v,A.nat(mu(Nat.mod(j,99n))))))
def tensor_off(t:G.Tensor) -> Nat:
  G.Tensor{_,o,_,_,_} = t
  o
def row(c:Context) -> A.Aff:
  Context{+s,l,_,_,ws,_,_} = c
  off = Nat.add(G.head_cols(s,"ar","zt"),tensor_off(G.tensor(s,"row")))
  row_(ws,Nat.add(off,Nat.mul(Nat.mul(G.field(s,"NN"),l),99n)),0n,A.zero())

def descend(ws:B.Elements,+c:Context,+l:Nat,left:Nat,rest:A.Aff,acc:A.Aff) -> A.Aff:
  match ws:
    case []: acc
    case v <> tail:
      +i = Nat.sub(left,1n)
      +remaining = rest
      next = A.add(acc,A.plus(at(c,"lr",l,i),remaining),E.negate(v))
      descend(tail,c,l,i,A.plus(remaining,at(c,"sel",l,i)),next)

def line(id:Nat,+c:Context) -> IO(A.Aff):
  match id:
    case 0n: IO.pure(A.Aff,gate(c,False{},False{}))
    case 1n: IO.pure(A.Aff,gate(c,True{},False{}))
    case 2n: IO.pure(A.Aff,gate(c,False{},True{}))
    case 3n: IO.pure(A.Aff,gate(c,True{},True{}))
    case 4n: IO.pure(A.Aff,A.plus(whole(c,"u"),shift(weight(c),A.size(field(c,"up_bound")))))
    case 5n: IO.pure(A.Aff,queries(c,False{}))
    case 6n: IO.pure(A.Aff,queries(c,True{}))
    case 7n: IO.pure(A.Aff,normal(c,True{},False{}))
    case 8n: IO.pure(A.Aff,normal(c,False{},False{}))
    case 9n: IO.pure(A.Aff,normal(c,True{},True{}))
    case 10n: IO.pure(A.Aff,normal(c,False{},True{}))
    case 11n: IO.pure(A.Aff,residual(c,0n,"fO",3n,"ro"))
    case 12n: IO.pure(A.Aff,residual(c,1n,"fD",6n,"rd"))
    case 13n: IO.pure(A.Aff,site(weight(c),whole(c,"vw"),kl(c,2n),field(c,"fV"),whole(c,"rv")))
    case 14n: IO.pure(A.Aff,high(weight(c),whole(c,"ro"),kl(c,3n),field(c,"fO")))
    case 15n: IO.pure(A.Aff,high(weight(c),whole(c,"rd"),kl(c,6n),field(c,"fD")))
    case 16n: IO.pure(A.Aff,high(weight(c),whole(c,"rv"),kl(c,2n),field(c,"fV")))
    case 17n: IO.pure(A.Aff,row(c))
    case 18n: IO.pure(A.Aff,clamp(c,whole(c,"aw"),short(c,"a",lam(c))))
    case 19n: IO.pure(A.Aff,clamp(c,whole(c,"mw"),short(c,"m",lam(c))))
    case 20n: IO.pure(A.Aff,clamp(c,whole(c,"qkw"),query_clamp(c)))
    case 21n: IO.pure(A.Aff,clamp(c,whole(c,"vw"),whole(c,"v")))
    case 22n:
      key = A.plus(whole(c,"g0"),scale(whole(c,"gc"),256n))
      IO.pure(A.Aff,A.plus(A.plus(key,power(whole(c,"s"),28n)),shift(weight(c),Nat.add(32768n,A.size(40n)))))
    case 23n: IO.pure(A.Aff,A.plus(whole(c,"g0"),shift(weight(c),128n)))
    case 24n: IO.pure(A.Aff,A.plus(A.plus(whole(c,"gh"),power(whole(c,"gc"),28n)),shift(weight(c),Nat.add(49152n,Nat.add(A.size(35n),A.size(40n))))))
    case 25n: IO.pure(A.Aff,A.minus(shift(weight(c),32768n),power(short(c,"xr",Nat.div(lam(c),2n)),16n)))
    case 26n:
      +layer = Nat.div(lam(c),2n)
      q = A.plus(scale(short(c,"ly",layer),8n),short(c,"l3",layer))
      IO.pure(A.Aff,site(weight(c),q,klm(c,0n),field(c,"fR"),short(c,"rl",layer)))
    case 27n: IO.pure(A.Aff,scale(A.plus(short(c,"lr",Nat.div(lam(c),2n)),shift(weight(c),16384n)),2n))
    case 28n: IO.pure(A.Aff,descend(A.rev(wvec(c)),c,Nat.div(lam(c),2n),field(c,"NE"),A.zero(),A.zero()))
    case 29n: IO.pure(A.Aff,high(weight(c),short(c,"rl",Nat.div(lam(c),2n)),klm(c,0n),field(c,"fR")))
    case 30n: IO.pure(A.Aff,scale(short(c,"sel",Nat.div(lam(c),2n)),128n))
    case 31n: IO.pure(A.Aff,A.scale(A.plus(A.const(A.nat(16384n)),power(at(c,"sc",Nat.div(lam(c),2n),0n),17n)),A.get(wvec(c),0n)))
    case 32n: IO.pure(A.Aff,scale(short(c,"l3",Nat.div(lam(c),2n)),32n))
    case 33n:
      +layer = Nat.div(lam(c),2n)
      IO.pure(A.Aff,A.plus(A.plus(short(c,"ly",layer),power(A.minus(short(c,"lr",layer),short(c,"l3",layer)),25n)),
        shift(weight(c),Nat.add(32768n,A.size(39n)))))
    case _: IO.die(A.Aff,1,"NO: unknown-G-segment")
