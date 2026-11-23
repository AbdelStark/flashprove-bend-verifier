import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_shape.bend as S
import ./segment_attention_psc.bend as P
import ./segment_attention_points.bend as Z
import ./segment_attention_reads.bend as R
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./fold.bend as F
import ./extension.bend as X

def each(~Env: Data, ~f: Env -> Nat -> A.Aff,+env: Env,n: Nat, acc: A.Equations) -> A.Equations:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      each(Env,f,env,i,f(env,i) <> acc)

def both(~Env: Data,~a: Env -> Nat -> A.Aff,~b: Env -> Nat -> A.Aff,+env: Env,n: Nat,acc: A.Equations) -> A.Equations:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      both(Env,a,b,env,i,a(env,i) <> b(env,i) <> acc)

def cat(xs: A.Equations,ys: A.Equations) -> A.Equations: List.append(&2,A.Aff,xs,ys)
def plus(x: A.Aff,y: A.Aff) -> A.Aff: A.plus(x,y)
def minus(x: A.Aff,y: A.Aff) -> A.Aff: A.minus(x,y)
def scale(x: A.Aff,k: Nat) -> A.Aff: A.scale(x,A.nat(k))
def total(u: S.Unit_) -> X.E3: A.sum(S.weights(u),F.zero())
def power2(n: Nat) -> Nat: A.size(n)
def offset(+s: S.Shape, d: Bool, p: Nat) -> Nat: S.q(s,Nat.add(Nat.mul(2n,Bool.pick(Nat,d,1n,0n)),p))

def plane_row(+s: S.Shape,d: Bool,+u: S.Unit_,vs: A.Values,start: Nat,+x: Nat) -> A.Aff:
  rhs = R.planes(S.weights(u),s,0n,d,S.inner(u),x,0n,A.zero())
  minus(A.slot(vs,Nat.add(start,x)),rhs)

type PlaneSeries is Data:
  PlaneSeries{s: S.Shape, diag: Bool, unit: S.Unit_, values: A.Values, start: Nat}
def plane_at(data: PlaneSeries, x: Nat) -> A.Aff:
  PlaneSeries{s,d,u,v,j} = data
  plane_row(s,d,u,v,j,x)

def kr(s: S.Shape, d: Bool, u: S.Unit_, vs: A.Values,start: Nat) -> A.Equations:
  each(PlaneSeries,plane_at,PlaneSeries{s,d,u,vs,start},3n,[])

type Endpoints is Data:
  Endpoints{shape: S.Shape, diag: Bool, at: B.Elements, values: A.Values}

def endpoint(data: Endpoints,+b: Nat,+k: Nat,kind: R.TensorKind) -> A.Aff:
  Endpoints{+s,d,+at,vs} = data
  minus(A.slot(vs,Nat.add(Nat.mul(2n,b),k)),R.read(s,offset(s,d,k),kind,b,Z.take(at,S.lg(s)),S.tail(at,S.ld(s))))
def query(data: Endpoints,b: Nat) -> A.Aff: endpoint(data,b,0n,R.Query{})
def key(data: Endpoints,b: Nat) -> A.Aff: endpoint(data,b,1n,R.KeyVector{})

def score(+s: S.Shape,+d: Bool,+u: S.Unit_,+c: P.Check) -> A.Equations:
  +ofs = Bool.pick(Nat,d,0n,6n)
  +vs = P.prefix(c)
  +at = P.point(c)
  +unit = S.inner(u)
  +hz = Z.take(unit,S.lg(s))
  +ws = S.weights(u)
  +end = P.ends(c)
  mv = minus(A.slot(vs,Nat.add(ofs,5n)),R.batch(ws,s,S.h(s,Bool.pick(Nat,d,1n,0n)),R.Maximum{},hz,[],0n,[]))
  sc = P.product_row(c,A.slot(vs,Nat.add(ofs,6n)),Z.polys(ws,Z.tile_weight(s,d,unit,at)))
  each(PlaneSeries,plane_at,PlaneSeries{s,d,u,vs,ofs},5n,mv <> sc <> both(Endpoints,query,key,Endpoints{s,d,at,end},S.pairs(s),[]))

def biased(vs: A.Values,i: Nat,lw: X.E3) -> A.Aff:
  plus(A.slot(vs,i),A.const(E.mul(A.nat(128n),lw)))

def kr_key(+vs: A.Values,+start: Nat, +u: S.Unit_) -> A.Aff:
  +w = total(u)
  plus(plus(biased(vs,start,w),scale(biased(vs,Nat.add(start,1n),w),power2(20n))),scale(A.slot(vs,Nat.add(start,2n)),power2(40n)))

def causal(+s: S.Shape,+u: S.Unit_,+d: Bool,+step: Nat,pad: Nat) -> X.E3:
  +z = S.inner(u)
  +cut = Nat.sub(Nat.add(pad,step),power2(32n))
  m = E.mul(A.nat(cut),A.ones(Z.middle(z,Nat.add(S.lg(s),Nat.sub(S.tiles(s),1n)),S.tiles(s))))
  +i = Z.query_lo(s,z)
  +j = S.tail(z,S.lb(s))
  om = Nat.add(cut,Nat.mul(Nat.mul(Nat.mul(2n,A.size(S.ld(s))),2047n),2047n))
  diagonal = E.mul(A.nat(om),F.sub(F.one(),Z.le(A.rev(j),A.rev(i),F.one())))
  E.mul(total(u),Bool.pick(X.E3,d,diagonal,m))

def kf_key(+s: S.Shape,+d: Bool,+u: S.Unit_,c: P.Check,step: Nat,pad: Nat) -> A.Aff:
  +vs = P.prefix(c)
  +j = Bool.pick(Nat,d,0n,6n)
  +w = total(u)
  dp = plus(minus(A.slot(vs,Nat.add(j,5n)),A.slot(vs,Nat.add(j,6n))),A.const(causal(s,u,d,step,pad)))
  lo = minus(minus(dp,biased(vs,j,w)),scale(biased(vs,Nat.add(j,1n),w),256n))
  hi = plus(scale(A.slot(vs,Nat.add(j,2n)),power2(32n)),scale(plus(biased(vs,Nat.add(j,3n),w),scale(A.slot(vs,Nat.add(j,4n)),256n)),power2(33n)))
  plus(lo,hi)
