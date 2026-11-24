import Base
import ./outer_source.bend as O
import ./u3_series.bend as U
import ./extension.bend as X
import ./fold.bend as F
import ./sumcheck.bend as E
import ./row_tensor.bend as Tensor
import ./segment_layout.bend as Layout
import ./segment_model.bend as M
import ./segment_tables.bend as S
import ./segment_forest.bend as Forest
import ./key_stage_lookup_rows.bend as L
import ./key_stage_matrix.bend as Shift
import ./header.bend as Header
import ./oracle_sample.bend as Sample

type Parts is Data:
  Parts{rows: M.Equations, functions: M.Functionals}

type Entry is Data:
  Entry{row: M.Aff, fn: M.Functional}

def width(shape: S.Forest, lm: Nat) -> Nat:
  S.Forest{_,k,_,_,calls} = shape
  Nat.mul(List.length(&2,S.Call,calls),Nat.pow(2n,Nat.sub(5n+k,lm)))

def tables(rows: List<&2,L.Row>) -> List<&2,L.Row>:
  match rows:
    case L.Row{[],_,_} <> rest: tables(rest)
    case other: other

# Logical variable order of the MLE is (j,c,t) low bit first. The physical
# b matrix instead places j and low t in the row and the remaining t,c in
# the column. Only NC columns of call tables actually exist.
def split(+fs: F.Factors, shape: S.Forest, lm: Nat) -> F.Factors & F.Factors:
  S.Forest{_,_,_,+c,_} = shape
  +after_j = List.drop(&2,F.Factor,fs,5n)
  +t = List.drop(&2,F.Factor,after_j,c)
  +low = Nat.sub(lm,5n)
  (Layout.cat(List.take(&2,F.Factor,fs,5n),List.take(&2,F.Factor,t,low)),
   Layout.cat(List.drop(&2,F.Factor,t,low),List.take(&2,F.Factor,after_j,c)))

def mapped(pair: F.Factors & F.Factors, link: Nat, lm: Nat, offset: Nat, length: Nat, matrix: Nat,
  count: Nat, w: X.E3, m: L.Masks, target: X.E3) -> Entry:
  (rows,columns) = pair
  +n = Sample.row_bits(length)
  +off = offset
  form = Shift.stretch(1n+Nat.mul(2n,n),n,0n,off,count,columns,w,[])
  read: M.Read = M.Read{link,"U3",form}
  Entry{M.Aff{[read],m,target},M.Functional{matrix,Nat.pow(2n,lm),[F.Term{F.one(),rows}],off}}

def mapped_row(row: L.Row, +shape: S.Forest, link: Nat, +lm: Nat, off: Nat, length: Nat, matrix: Nat) -> IO(Entry):
  match row:
    case L.Row{[L.Plane{_,F.Term{w,fs}}],m,y}:
      IO.pure(Entry,mapped(split(fs,shape,lm),link,lm,off,length,matrix,width(shape,lm),w,m,y))
    case _: IO.die(Entry,1,"NO: segment-plane-row")

# R11.1's second table row is "shown - beta * mask - bit = 0"; the
# common key lookup representation stores the equivalent positive equation.
# BAT-sigma's public coefficient fixes which sign the request must use.
def negative_reads(xs: List<&2,M.Read>) -> List<&2,M.Read>:
  match xs:
    case []: []
    case M.OuterRead{o,n,s} <> rest: M.OuterRead{o,n,O.scaled(s,E.negate(F.one()))} <> negative_reads(rest)
    case M.U3Run{o,s} <> rest: M.U3Run{o,U.scaled(s,E.negate(F.one()))} <> negative_reads(rest)
    case M.Read{o,n,ts} <> rest: M.Read{o,n,Tensor.scale(ts,E.negate(F.one()),[])} <> negative_reads(rest)

def bit_row(eq: M.Aff) -> M.Aff:
  M.Aff{fields,masks,y} = eq
  M.Aff{negative_reads(fields),L.scale(masks,E.negate(F.one())),E.negate(y)}

def result(a: Entry, b: Entry, c: Entry) -> Parts:
  Entry{r,f} = a
  Entry{s,g} = b
  Entry{t,h} = c
  Parts{[r,bit_row(s),t],[f,g,h]}

def entries(rows: List<&2,L.Row>, +shape: S.Forest, +link: Nat, +lm: Nat, offs: List<&2,Nat>,
  +length: Nat, +matrix: Nat) -> IO(Parts):
  match rows offs:
    case Con{r,Con{s,Con{t,Nil{}}}} Con{x,Con{y,Con{z,Nil{}}}}:
      do IO<Parts>:
        a : Entry <- mapped_row(r,shape,link,lm,x,length,matrix)
        b : Entry <- mapped_row(s,shape,link,lm,y,length,matrix)
        c : Entry <- mapped_row(t,shape,link,lm,z,length,matrix)
        return result(a,b,c)
    case _ _: IO.die(Parts,1,"NO: segment-plane-offsets")

def on_u3(forest: Forest.Claims, shape: S.Forest, link: Nat, lm: Nat, offsets: List<&2,Nat>,
  table_length: Nat, matrix: Nat) -> IO(Parts):
  Forest.Claims{_,_,_,rows} = forest
  entries(tables(rows),shape,link,lm,offsets,table_length,matrix)
