import Base
import ./head_types.bend as G
import ./head_rounds.bend as R
import ./head_catalog.bend as C
import ./segment_attention_aff.bend as A
import ./key_stage_matrix.bend as M
import ./extension.bend as X
import ./sumcheck.bend as E
import ./base_check.bend as B
import ./fold.bend as F
import ./row_tensor.bend as T
import ./hash_bytes.bend as H
import ./policy_statement.bend as S

type Covered is Data:
  Covered{start: Nat, end: Nat, costs_end: Nat, winners: H.Bytes}

def checked(times: H.Bytes, +tokens: H.Bytes, y: U32, +t: Nat) -> IO(Covered):
  match times:
    case [r,e]:
      +lo = U32.to_nat(r)
      +hi = U32.to_nat(e)
      next = F.cat(U32,F.take(U32,List.drop(&2,U32,tokens,1n),Nat.sub(t,1n)),[y])
      return_: Covered = Covered{lo,hi,Nat.min(Nat.sub(t,1n),hi),F.take(U32,List.drop(&2,U32,next,lo),Nat.sub(hi,lo))}
      IO.pure(Covered,return_)
    case _: IO.die(Covered,1,"NO: head-coverage")

def load(st: S.Statement, s: G.Shape) -> IO(Covered):
  S.Statement{_,+req,y,_,_,_,_,_} = st
  +t = A.size(C.lt(s))
  checked(List.drop(&2,U32,req,t),req,y,t)

def interval(+low: B.Elements, a: Nat, b: Nat) -> X.E3:
  F.sub(M.below(low,b,F.zero()),M.below(low,a,F.zero()))

def on(cov: Covered, high: B.Elements) -> X.E3:
  Covered{a,b,_,_} = cov
  interval(A.rev(high),a,b)

def cost(cov: Covered, high: B.Elements) -> X.E3:
  Covered{+a,_,b,_} = cov
  interval(A.rev(high),a,Nat.max(a,b))

def ncost(cov: Covered) -> Nat:
  Covered{a,_,b,_} = cov
  Nat.sub(b,a)

# The head column map packs segment pieces into dyadic runs. A vocabulary
# prefix can be evaluated by summing their interval masses at its column point.
def prefix(rs: List<&2,G.Run>, +p: B.Elements, +n: Nat, acc: X.E3) -> X.E3:
  match rs:
    case []: acc
    case G.Run{+a,+size} <> tail:
      q = interval(p,a,Nat.add(a,Nat.min(n,size)))
      prefix(tail,p,Nat.sub(n,size),E.add(acc,q))

def mass(g: G.Segment, +k: R.Keys, lt: Nat, n: Nat) -> X.E3:
  G.Segment{_,w,_,rs} = g
  prefix(rs,R.column(k,lt,w),n,F.zero())

def tie_walk(xs: H.Bytes, +rs: List<&2,G.Run>, +cols: B.Elements, +tok: F.Factors, i: Nat, acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case win <> tail:
      +j = i
      v = E.mul(T.entry(tok,j,F.one()),prefix(rs,cols,U32.to_nat(win),F.zero()))
      tie_walk(tail,rs,cols,tok,1n+j,E.add(acc,v))

def tie(cov: Covered, g: G.Segment, +k: R.Keys, lt: Nat) -> X.E3:
  Covered{start,_,_,xs} = cov
  G.Segment{_,w,_,rs} = g
  tie_walk(xs,rs,R.column(k,lt,w),T.eq(A.rev(R.tokens(k))),start,F.zero())

def values(rs: List<&2,G.Run>, +table: B.Elements, acc: B.Elements) -> B.Elements:
  match rs:
    case []: List.reverse(&2,X.E3,acc)
    case G.Run{j,n} <> tail:
      part = F.take(X.E3,List.drop(&2,X.E3,table,j),n)
      values(tail,table,List.reverse.go(&2,X.E3,part,acc))

def weights(g: G.Segment, k: R.Keys, lt: Nat) -> B.Elements:
  G.Segment{_,width,_,rs} = g
  values(rs,F.factor_table(T.eq(R.column(k,lt,width)),F.one()),[])

def window(cov: Covered, +point: F.Factors) -> F.Form:
  Covered{+start,_,stop,_} = cov
  end = T.below(point,Nat.max(start,stop),F.one())
  F.cat(F.Term,end,T.below(point,start,E.negate(F.one())))

def value(p: Map<&2,X.E3> & X.E3) -> X.E3:
  (_,x) = p
  x

def winner_map(xs: H.Bytes, +tok: F.Factors, +w: X.E3, i: Nat, +acc: Map<&2,X.E3>) -> Map<&2,X.E3>:
  match xs:
    case []: acc
    case win <> tail:
      +name = U32.show(win)
      +j = i
      v = E.add(value(Map.get(X.E3,F.zero(),acc,name)),T.entry(tok,j,w))
      winner_map(tail,tok,w,1n+j,Map.set(&2,X.E3,acc,name,v))

def combined(xs: B.Elements, +by_token: Map<&2,X.E3>, +s: X.E3, i: Nat, acc: B.Elements) -> B.Elements:
  match xs:
    case []: List.reverse(&2,X.E3,acc)
    case x <> tail:
      +j = i
      v = F.sub(value(Map.get(X.E3,F.zero(),by_token,Nat.show(j))),E.mul(x,s))
      combined(tail,by_token,s,1n+j,v <> acc)

def vocabulary(+cov: Covered, g: G.Segment, +k: R.Keys, +lt: Nat, +vocab: Nat, +rH: B.Elements) -> B.Elements:
  Covered{start,_,_,xs} = cov
  +seg = g
  table = winner_map(xs,T.eq(A.rev(rH)),mass(seg,k,lt,vocab),start,Map.new(&2,X.E3))
  combined(F.take(X.E3,weights(seg,k,lt),vocab),table,on(cov,rH),0n,[])
