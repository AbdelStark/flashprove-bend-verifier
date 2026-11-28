import Base
import ./segment_layout.bend as L
import ./segment_projection.bend as Project
import ./outer_source.bend as O
import ./fold.bend as F
import ./fold_frame.bend as Frame
import ./fold_request_shape.bend as Q
import ./key_stage_openings.bend as K
import ./row_tensor.bend as V
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./oracle_sample.bend as S
import ./pow2.bend as P2

type Tile is Data:
  Tile{block: L.Block, row: F.Factors, neutral: F.Factors, cb: Nat, dr: Nat, dc: Nat,w: X.E3}

def stable(bits: Nat) -> F.Factors:
  List.replicate(F.Factor,bits,F.Factor{F.one(),F.one()})

def tile(b: L.Block,row: F.Term,kr: Nat,kc: Nat,bits: Nat,dr: Nat,dc: Nat) -> Tile:
  F.Term{w,fs} = row
  Tile{b,L.cat(stable(kr),fs),stable(kc),bits,dr,dc,w}

def emit(t: Tile,i: Nat,endpoints: F.Factors,scale: X.E3,out: F.Form) -> F.Form:
  Tile{b,rs,prefix,bits,dr,dc,w} = t
  +value = E.mul(w,scale)
  cols = L.cat(prefix,L.cat(endpoints,V.choice(bits,i)))
  L.project(b,L.Axes{value,rs,cols},dr,dc,value) <> out

# Fold adjacent logical columns along the terminal coordinates assigned to
# this axis. A zero outside the real last column is the symbolic zero padding.
type Part is Data:
  Part{value: X.E3, rest: B.Elements}

def pair(a: X.E3,g: X.E3,right: Part) -> Part:
  Part{b,tail} = right
  Part{F.mix(a,b,g),tail}

def half(left: Part,g: X.E3,read: B.Elements -> Part) -> Part:
  Part{a,tail} = left
  pair(a,g,read(tail))

def read(gs: B.Elements,cs: B.Elements) -> Part:
  match gs cs:
    case Nil{} Con{x,tail}: Part{x,tail}
    case Nil{} Nil{}: Part{F.zero(),[]}
    case Con{g,+tail} all: half(read(tail,all),g,ys => read(tail,ys))

type Piece is Data:
  PairOf{a: X.E3,b: X.E3,tail: B.Elements}

def together(a: X.E3,y: Part) -> Piece:
  Part{b,tail} = y
  PairOf{a,b,tail}

def second(x: Part,gs: B.Elements) -> Piece:
  Part{a,tail} = x
  together(a,read(gs,tail))

def first(x: Part,t: Tile,out: F.Form) -> F.Form:
  Part{v,_} = x
  emit(t,0n,[],v,out)

type Work is Data:
  Work{out: F.Form,tail: B.Elements}

def unroll(pair: Piece,t: Tile,i: Nat,out: F.Form) -> Work:
  PairOf{a,b,tail} = pair
  Work{emit(t,i,[F.Factor{a,b}],F.one(),out),tail}

def fill(n: Nat,+t: Tile,+gs: B.Elements,idx: Nat,acc: Work) -> F.Form:
  match n acc:
    case 0n Work{out,_}: out
    case 1n+k Work{out,cs}:
      +i = idx
      fill(k,t,gs,1n+i,unroll(second(read(gs,cs),gs),t,i,out))

def slice(width: Nat,cs: B.Elements,gs: B.Elements,b: L.Block,row: F.Term,kr: Nat,kc: Nat,dr: Nat,dc: Nat,out: F.Form) -> F.Form:
  match width:
    case 0n: first(read(gs,cs),tile(b,row,kr,kc,0n,dr,dc),out)
    case 1n+k:
      +bits = k
      t = tile(b,row,kr,kc,bits,dr,dc)
      fill(P2.pow2(bits),t,gs,0n,Work{out,cs})

def single(+b: L.Block,+rs: F.Factors,cols: B.Elements,w: X.E3,+gamma: B.Elements,gr: Nat,dr: Nat,dc: Nat,out: F.Form) -> F.Form:
  L.Block{i,c,_,_,+bi,+bc,_,bp,+ilow} = b
  +take = Nat.min(bp,gr)
  +kr = Nat.min(bi,Bool.pick(Nat,ilow,take,Nat.sub(take,bc)))
  +kc = Nat.sub(take,kr)
  rg = List.take(&2,X.E3,List.drop(&2,X.E3,gamma,Bool.pick(Nat,ilow,0n,kc)),kr)
  cg = List.take(&2,X.E3,List.drop(&2,X.E3,gamma,Bool.pick(Nat,ilow,kr,0n)),kc)
  row = F.fix(rg,List.take(&2,F.Factor,rs,bi),L.upper(rs,i,bi,w))
  slice(Nat.sub(bc,kc),cols,List.reverse(&2,X.E3,cg),b,row,kr,kc,dr,dc,out)

# The columns from c on. Tiles usually ascend, so continue from the previous
# tile's offset at instead of walking the shared list from its start.
def seek(ahead: Bool,cols: B.Elements,rest: B.Elements,at: Nat,c: Nat) -> B.Elements:
  match ahead:
    case True{}: List.drop(&2,X.E3,rest,Nat.sub(c,at))
    case False{}: List.drop(&2,X.E3,cols,c)

def column(b: L.Block) -> Nat:
  L.Block{_,c,_,_,_,_,_,_,_} = b
  c

def blocks(bs: L.Tiles,+rs: F.Factors,+cols: B.Elements,+w: X.E3,+gs: B.Elements,+gr: Nat,+dr: Nat,+dc: Nat,
    +at: Nat,rest: B.Elements,out: F.Form) -> F.Form:
  match bs:
    case []: out
    case +b <> tail:
      +c = column(b)
      +here = seek(Nat.is_le(at,c),cols,rest,at,c)
      blocks(tail,rs,cols,w,gs,gr,dr,dc,c,here,single(b,rs,here,w,gs,gr,dr,dc,out))

# For irregular public layouts, keep the complete general form.
def valid(bs: L.Tiles,+rb: Nat,+cb: Nat,+dr: Nat,+dc: Nat) -> Bool:
  match bs:
    case []: True{}
    case L.Block{+i,+c,+r,+p,+bi,+bc,+br,+bp,_} <> tail:
      Nat.is_eq(Nat.add(bi,bc),Nat.add(br,bp)) && Nat.is_le(bi,rb) && Nat.is_le(bc,cb) &&
        Nat.is_le(br,dr) && Nat.is_le(bp,dc) && L.axis_valid(i,bi,P2.pow2(rb)) &&
        L.axis_valid(c,bc,P2.pow2(cb)) && L.axis_valid(r,br,P2.pow2(dr)) &&
        L.axis_valid(p,bp,P2.pow2(dc)) && valid(tail,rb,cb,dr,dc)

def translated(source: O.Source,table: L.Matrix,link: Nat,dc: Nat,dr: Nat,basis: Project.Basis) -> Frame.On:
  O.Outer{rs,+cs,_,w} = source
  L.Matrix{msg,_,_,bs,_} = table
  Project.Basis{gs,gr,_} = basis
  Frame.On{Q.label(link,msg),False{},blocks(bs,rs,cs,w,gs,gr,dr,dc,0n,cs,[])}

def checked(yes: Bool,source: O.Source,table: L.Matrix,m: Frame.Member,link: Nat,dc: Nat,dr: Nat,basis: Project.Basis) -> Frame.On:
  match yes:
    case True{}: translated(source,table,link,dc,dr,basis)
    case False{}: L.addressed(table,link,O.expand(source),dc,m)

def pick(+source: O.Source,+table: L.Matrix,+m: Frame.Member,link: Nat,+dc: Nat,basis: Project.Basis) -> Frame.On:
  O.Outer{rs,cs,bits,_} = source
  L.Matrix{_,r,c,bs,_} = table
  Frame.Member{_,rows,_,_,held} = m
  +rb = S.row_bits(r)
  +cb = S.row_bits(c)
  +dr = S.row_bits(rows)
  ok = Bool.not(held) && Nat.is_eq(List.length(&2,F.Factor,rs),rb) &&
    Nat.is_eq(bits,cb) && Nat.is_le(F.count(X.E3,cs,0n),P2.pow2(cb)) && valid(bs,rb,cb,dr,dc)
  checked(ok,source,table,m,link,dc,dr,basis)

def on_matrix(source: O.Source,+table: L.Matrix,+m: Frame.Member,link: Nat,+dc: Nat,b: Maybe<&2,Project.Basis>) -> Frame.On:
  match b:
    case None{}: L.addressed(table,link,O.expand(source),dc,m)
    case Some{basis}: pick(source,table,m,link,dc,basis)

def located(shape: Q.Shape,+table: L.Matrix,source: O.Source,+link: Nat,b: Maybe<&2,Project.Basis>) -> IO(Frame.On):
  Q.Shape{code,_,links,_} = shape
  L.Matrix{msg,_,_,_,_} = table
  do IO<Frame.On>:
    l : Q.Link <- K.need(Q.Link,List.get(&2,Q.Link,links,link),"NO: segment-layout-link")
    m : Frame.Member <- L.member(l,msg)
    return on_matrix(source,table,m,link,L.columns(code),b)
