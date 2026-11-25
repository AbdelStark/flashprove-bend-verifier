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

# Each real tile contributes once to its row or column. The final sg has
# no tile. The upstream cover enumerates p < nt/2 and sg < nt - 1.
def tile_sums(ws: B.Elements,+p: Nat,+nt: Nat,+col: Bool,j: Nat,+weight: X.E3,a: Array<X.E3>) -> Array<X.E3>:
  match ws:
    case []: a
    case x <> tail:
      +sg = j
      +at = U32.from_nat(index(cover(p,sg,nt),col))
      tile_sums(tail,p,nt,col,1n+sg,weight,F.summed(Array.get(X.E3,a,at),at,E.mul(weight,x)))
def tile_rows(ps: B.Elements,+sg: B.Elements,+nt: Nat,+col: Bool,i: Nat,a: Array<X.E3>) -> Array<X.E3>:
  match ps:
    case []: a
    case w <> tail:
      +p = i
      tile_rows(tail,sg,nt,col,1n+p,tile_sums(sg,p,nt,col,0n,w,a))
def marginals(+s: S.Shape,+z: B.Elements,col: Bool) -> B.Elements:
  +h = S.tiles(s)
  +a = Nat.sub(h,1n)
  +nt = A.size(h)
  ps = A.eq_range(A.rev(middle(z,S.lg(s),a)),0n,Nat.div(nt,2n))
  sg = A.eq_range(A.rev(middle(z,Nat.add(S.lg(s),a),h)),0n,Nat.sub(nt,1n))
  F.values(Array.to_list(X.E3,tile_rows(ps,sg,nt,col,0n,Array.new(X.E3,h,F.zero()))),[])

def weighted_marginal(+s: S.Shape,z: B.Elements,row: B.Elements) -> X.E3:
  ws = A.eq_range(A.rev(row),0n,A.size(S.tiles(s)))
  Maybe.default(&2,X.E3,B.dot(ws,marginals(s,z,False{}),F.zero()),F.zero())

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
def add_margins(ws: B.Elements,+bits: Nat,+lo: F.Factors,i: Nat) -> F.Form:
  match ws:
    case []: []
    case w <> tail:
      +j = i
      fs = List.append(&2,F.Factor,lo,T.choice(bits,j))
      F.Term{w,fs} <> add_margins(tail,bits,lo,1n+j)
def equality(z: B.Elements) -> F.Form: [F.Term{F.one(),T.eq(A.rev(z))}]
def token(+s: S.Shape,diag: Bool,+z: B.Elements,col: Bool,+lo: B.Elements) -> F.Form:
  choose = Bool.pick(Unit -> F.Form,diag,
    _ => equality(cat(middle(z,S.lg(s),S.tiles(s)),lo)),
    _ => add_margins(marginals(s,z,col),S.tiles(s),T.eq(A.rev(lo)),0n))
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
