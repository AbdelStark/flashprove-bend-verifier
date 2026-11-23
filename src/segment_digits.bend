import Base
import ./segment_coverage.bend as Cover
import ./transcript.bend as T
import ./base_check.bend as B
import ./fold.bend as F
import ./extension.bend as X
import ./sumcheck.bend as E
import ./row_tensor.bend as Tensor
import ./segment_forest.bend as Forest
import ./segment_model.bend as M
import ./segment_tables.bend as S
import ./segment_planes.bend as Plane
import ./segment_layout.bend as Layout
import ./key_stage_lookup_rows.bend as L
import ./key_stage_matrix.bend as Shift
import ./oracle_sample.bend as Sample
import ./header.bend as Header

# In BZ, the highest five bits of the table-row index select the
# physical row; the (j,c,remaining t) coordinates index its columns.
def bz(row: L.Row, link: Nat, k: Nat) -> IO(M.Aff):
  match row:
    case L.Row{[L.Plane{_,F.Term{+w,+fs}}],m,t}:
      +cols = k
      factors = Layout.cat(List.drop(&2,F.Factor,fs,cols),List.take(&2,F.Factor,fs,cols))
      do IO<M.Aff>:
        live : Unit <- Header.require(Bool.not(T.is_zero(w)) && Cover.prefix(List.take(&2,F.Factor,fs,cols),Nat.pow(2n,cols),1n),
          "NO: segment-zero-BZ-column")
        return M.Aff{[M.Read{link,"BZ",[F.Term{w,factors}]}],m,t}
    case _: IO.die(M.Aff,1,"NO: segment-digits-planes")

def planes(rows: List<&2,L.Row>, +link: Nat, +bits: Nat) -> IO(M.Equations):
  match rows:
    case [a,b,c]:
      do IO<M.Equations>:
        first : M.Aff <- bz(a,link,bits)
        shown : M.Aff <- bz(b,link,bits)
        total : M.Aff <- bz(c,link,bits)
        return [first,Plane.bit_row(shown),total]
    case _: IO.die(M.Equations,1,"NO: segment-digits-rows")

def attach(+rows: F.Factors, forms: F.Form) -> F.Form:
  match forms:
    case []: []
    case F.Term{c,fs} <> tail: F.Term{c,Layout.cat(rows,fs)} <> attach(rows,tail)

type Digit is Data:
  Digit{forms: F.Form, call_weight: X.E3}

def digit(c: S.Call, +zy: B.Elements, +zx: B.Elements, +columns: Nat, offset: Nat) -> Digit:
  S.Call{_,_,first,+iota,_,_} = c
  +call_weight = Tensor.entry(Tensor.eq(List.drop(&2,X.E3,zy,iota)),Nat.div(first,Nat.pow(2n,iota)),F.one())
  +point = Layout.cat(Tensor.eq(zx),Tensor.eq(List.take(&2,X.E3,zy,iota)))
  +bits = Sample.row_bits(columns)
  low = List.take(&2,F.Factor,point,bits)
  +after = List.drop(&2,F.Factor,point,bits)
  rows = List.take(&2,F.Factor,after,7n)
  factor = Tensor.entry(List.drop(&2,F.Factor,after,7n),0n,E.negate(call_weight))
  +dest = Sample.row_bits(Nat.mul(2n,columns))
  form = Shift.stretch(1n+Nat.mul(2n,dest),dest,0n,offset,columns,low,factor,[])
  Digit{attach(rows,form),call_weight}

# Sampled key weights are required only on the two real digit
# rectangles. Coordinates above their occupied rows may equal zero.
def live(c: S.Call,+zy: B.Elements,zx: B.Elements,+columns: Nat) -> Bool:
  S.Call{_,_,first,+iota,_,_} = c
  e = Tensor.entry(Tensor.eq(List.drop(&2,X.E3,zy,iota)),Nat.div(first,Nat.pow(2n,iota)),F.one())
  +point = Layout.cat(Tensor.eq(zx),Tensor.eq(List.take(&2,X.E3,zy,iota)))
  +bits = Sample.row_bits(columns)
  Bool.not(T.is_zero(e)) && Cover.prefix(List.take(&2,F.Factor,point,bits),columns,1n) &&
    Cover.prefix(List.drop(&2,F.Factor,point,bits),128n,1n)

def joined(a: Digit, b: Digit, alpha: X.E3, theta: X.E3, masks: L.Masks, shown: X.E3, link: Nat) -> M.Aff:
  Digit{x,u} = a
  Digit{y,v} = b
  +alp = alpha
  constant = E.add(E.mul(u,alp),E.mul(v,F.sub(alp,theta)))
  M.Aff{[M.Read{link,"ZZ",List.append(&2,F.Term,x,y)}],masks,F.sub(shown,constant)}

def complete_trees(a: S.Call, b: S.Call, r: Nat) -> Bool:
  match a b:
    case S.Call{S.Range{},10n,first,n,0n,_} S.Call{S.Range{},8n,+next,m,0n,_}:
      Nat.is_eq(first,0n) && Nat.is_eq(next,Nat.pow(2n,n)) && Nat.is_eq(Nat.add(next,Nat.pow(2n,m)),Nat.pow(2n,r))
    case _ _: False{}

def join(link: Nat, +columns: Nat, shape: S.Forest, key: L.Point, alpha: X.E3, theta: X.E3) -> IO(M.Aff):
  match shape key:
    case S.Forest{_,_,+r,1n,[+low,+high]} L.Point{+coords,m,t}:
      +zy = List.take(&2,X.E3,coords,r)
      +zx = List.drop(&2,X.E3,coords,r)
      do IO<M.Aff>:
        ok : Unit <- Header.require(complete_trees(low,high,r),"NO: segment-digits-shape")
        yes : Unit <- Header.require(live(low,zy,zx,columns) && live(high,zy,zx,columns),"NO: segment-zero-ZZ-join")
        return joined(digit(low,zy,zx,columns,0n),digit(high,zy,zx,columns,columns),alpha,theta,m,t,link)
    case _ _: IO.die(M.Aff,1,"NO: segment-digits-call-shape")

def build(forest: Forest.Claims, +shape: S.Forest, +link: Nat, columns: Nat) -> IO(M.Equations):
  Forest.Claims{key,a,t,+rows} = forest
  S.Forest{_,k,_,c,_} = shape
  do IO<M.Equations>:
    joined : M.Aff <- join(link,columns,shape,key,a,t)
    tables : M.Equations <- planes(Plane.tables(rows),link,Nat.add(k,c))
    return List.append(&2,M.Aff,M.mask_only(rows),joined <> tables)
