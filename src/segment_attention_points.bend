import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./segment_attention_shape.bend as S
import ./extension.bend as X
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./fold.bend as F
import ./row_tensor.bend as T

def take(xs: B.Elements,n: Nat) -> B.Elements: List.take(&2,X.E3,xs,n)
def cat(xs: B.Elements,ys: B.Elements) -> B.Elements: List.append(&2,X.E3,xs,ys)
def middle(xs: B.Elements,i: Nat,n: Nat) -> B.Elements: A.slice(xs,i,n)
def dot(xs: B.Elements,ys: B.Elements) -> X.E3: A.eqp(xs,ys,F.one())

type Tile is Data:
  Tile{row: Nat, column: Nat}
def cover(+p: Nat,+sg: Nat,n: Nat) -> Tile:
  Bool.pick(Tile,Nat.is_lt(sg,p),Tile{p,sg},Tile{Nat.sub(Nat.sub(n,1n),p),Nat.sub(sg,p)})
def index(t: Tile, col: Bool) -> Nat:
  Tile{i,j} = t
  Bool.pick(Nat,col,j,i)

# The last sg has no tile and contributes zero. The same map is used by the
# lookup-key identity and by the two marginals in the U3 evaluation tables.
def margin(n: Nat,+nt: Nat,+p: B.Elements,+sg: B.Elements,+col: Bool,+which: Nat,+acc: X.E3) -> X.E3:
  match n:
    case 0n: acc
    case 1n+k:
      +remaining = k
      +i = Nat.div(remaining,Nat.sub(nt,1n))
      +j = Nat.mod(remaining,Nat.sub(nt,1n))
      w = E.mul(A.eq(p,i),A.eq(sg,j))
      margin(remaining,nt,p,sg,col,which,Bool.pick(X.E3,Nat.is_eq(index(cover(i,j,nt),col),which),E.add(acc,w),acc))
def marginal(+s: S.Shape,+z: B.Elements,col: Bool,index_: Nat) -> X.E3:
  +h = S.tiles(s)
  +a = Nat.sub(h,1n)
  +nt = A.size(h)
  margin(Nat.mul(Nat.div(nt,2n),Nat.sub(nt,1n)),nt,middle(z,S.lg(s),a),middle(z,Nat.add(S.lg(s),a),h),col,index_,F.zero())
def both(+s: S.Shape,diag: Bool,+z: B.Elements,+col: Bool,+i: Nat) -> X.E3:
  choose = Bool.pick(Unit -> X.E3,diag,
    _ => A.eq(middle(z,S.lg(s),S.tiles(s)),i), _ => marginal(s,z,col,i))
  choose(Unit{})
def weighted_marginal(n: Nat,+s: S.Shape,+z: B.Elements,+row: B.Elements,acc: X.E3) -> X.E3:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      weighted_marginal(i,s,z,row,E.add(acc,E.mul(A.eq(row,i),marginal(s,z,False{},i))))

def tile_weight(+s: S.Shape,d: Bool,+z: B.Elements,+r: B.Elements) -> X.E3:
  +n = S.tiles(s)
  +g = S.lg(s)
  +p = Nat.sub(n,1n)
  +i = Nat.add(g,p)
  +zs = middle(z,i,n)
  +rs = middle(r,i,n)
  a = E.mul(dot(middle(z,g,p),middle(r,g,p)),F.sub(dot(zs,rs),E.mul(A.ones(zs),A.ones(rs))))
  b = dot(middle(z,g,n),middle(r,g,n))
  E.mul(dot(take(z,g),take(r,g)),Bool.pick(X.E3,d,b,a))

# Marginals are on the high tile index, eq(low) on the token within the tile.
def add_margins(n: Nat,+s: S.Shape,+z: B.Elements,+col: Bool,+lo: F.Factors,acc: F.Form) -> F.Form:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      w = marginal(s,z,col,i)
      fs = List.append(&2,F.Factor,lo,T.choice(S.tiles(s),i))
      add_margins(i,s,z,col,lo,F.Term{w,fs} <> acc)
def equality(z: B.Elements) -> F.Form: [F.Term{F.one(),T.eq(A.rev(z))}]
def token(+s: S.Shape,diag: Bool,+z: B.Elements,col: Bool,+lo: B.Elements) -> F.Form:
  choose = Bool.pick(Unit -> F.Form,diag,
    _ => equality(cat(middle(z,S.lg(s),S.tiles(s)),lo)),
    _ => add_margins(A.size(S.tiles(s)),s,z,col,T.eq(A.rev(lo)),[]))
  choose(Unit{})
def extend(forms: F.Form,+high: F.Factors) -> F.Form:
  match forms:
    case []: []
    case F.Term{w,lo} <> tail: F.Term{w,List.append(&2,F.Factor,lo,high)} <> extend(tail,high)
def lng(s: S.Shape,channel: B.Elements,tok: F.Form) -> F.Form:
  extend(tok,T.eq(A.rev(S.tail(channel,S.lanes(s)))))
def query_lo(+s: S.Shape,z: B.Elements) -> B.Elements:
  +b = S.lb(s)
  take(S.tail(z,Nat.mul(2n,b)),b)
def vm_point(+s: S.Shape,diag: Bool,+r: B.Elements,ziw: B.Elements) -> B.Elements:
  m = Nat.sub(Nat.add(S.lg(s),Nat.mul(2n,S.tiles(s))),1n)
  hi = take(r,Bool.pick(Nat,diag,Nat.add(S.lg(s),S.tiles(s)),m))
  cat(hi,cat(S.tail(ziw,S.lb(s)),S.tail(r,S.lb(s))))

def le(xs: B.Elements,ys: B.Elements,acc: X.E3) -> X.E3:
  match xs ys:
    case Con{+x,a} Con{+y,b}:
      +w = F.sub(F.one(),x)
      le(a,b,E.add(E.mul(w,y),E.mul(F.mix(w,x,y),acc)))
    case _ _: acc
def id(xs: B.Elements,acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case x <> tail:
      +v = acc
      id(tail,E.add(E.add(v,v),x))

def polys(ws: B.Elements,scale: X.E3) -> B.Elements: F.scaled(ws,scale)
