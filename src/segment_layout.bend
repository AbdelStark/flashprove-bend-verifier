import Base
import ./base_check.bend as B
import ./fold.bend as F
import ./fold_frame.bend as Frame
import ./fold_request_shape.bend as Q
import ./sumcheck.bend as E
import ./row_tensor.bend as Tensor
import ./extension.bend as X
import ./hash_bytes.bend as H
import ./header.bend as Header
import ./key_stage_openings.bend as K
import ./policy.bend as P
import ./oracle_sample.bend as Sample

# R12.17 binary layout, already authenticated by Plan.load and compared to
# the admitted text by Layout.check. Each logical block is one dyadic tile.
type Block is Data:
  Block{i: Nat, c: Nat, r: Nat, p: Nat, bi: Nat, bc: Nat, br: Nat, bp: Nat, i_low: Bool}
# A dyadic tile lies on one side of any cut above its own size. Build a
# decision tree over logical row and column prefixes once per public matrix.
def Tiles() -> Data: List<&2,Block>
type Index is Data:
  Empty{}
  Leaf{block: Block}
  Rows{lo: Index,hi: Index}
  Cols{lo: Index,hi: Index}
  General{}

type Next is Data:
  CompleteIndex{tree: Index}
  CutTiles{row: Bool, rows: Nat, cols: Nat, lo: Tiles, hi: Tiles}

def row_bits(b: Block) -> Nat:
  Block{_,_,_,_,r,_,_,_,_} = b
  r

def col_bits(b: Block) -> Nat:
  Block{_,_,_,_,_,c,_,_,_} = b
  c

def free_cut(bs: Tiles,+row: Bool,+bits: Nat) -> Bool:
  match bs:
    case []: True{}
    case +b <> tail:
      Nat.is_lt(Bool.pick(Nat,row,row_bits(b),col_bits(b)),bits) && free_cut(tail,row,bits)

def coordinate(b: Block,row: Bool) -> Nat:
  Block{i,c,_,_,_,_,_,_,_} = b
  Bool.pick(Nat,row,i,c)

def divide(bs: Tiles,+row: Bool,+half: Nat,+lo: Tiles,+hi: Tiles) -> Tiles & Tiles:
  match bs:
    case []: (lo,hi)
    case +b <> tail:
      +upper = Nat.is_eq(Nat.mod(Nat.div(coordinate(b,row),half),2n),1n)
      divide(tail,row,half,Bool.pick(Tiles,upper,lo,b <> lo),Bool.pick(Tiles,upper,b <> hi,hi))

def cut(row: Bool,rows: Nat,cols: Nat,pair: Tiles & Tiles) -> Next:
  (lo,hi) = pair
  CutTiles{row,rows,cols,lo,hi}

def cut_axis(row: Bool,bs: Tiles,rows: Nat,cols: Nat) -> Next:
  match row:
    case True{}:
      +r = Nat.sub(rows,1n)
      cut(True{},r,cols,divide(bs,True{},Nat.pow(2n,r),[],[]))
    case False{}:
      +c = Nat.sub(cols,1n)
      cut(False{},rows,c,divide(bs,False{},Nat.pow(2n,c),[],[]))

def branch(+bs: Tiles,+r: Nat,+c: Nat) -> Next:
  +row = free_cut(bs,True{},r)
  go = Bool.pick(Unit -> Next,row || free_cut(bs,False{},c),_ => cut_axis(row,bs,r,c),_ => CompleteIndex{General{}})
  go(Unit{})

def split(bs: Tiles,+r: Nat,+c: Nat) -> Next:
  match bs:
    case []: CompleteIndex{Empty{}}
    case [+b]:
      go = Bool.pick(Unit -> Next,Nat.is_eq(row_bits(b),r) && Nat.is_eq(col_bits(b),c),
        _ => CompleteIndex{Leaf{b}},_ => branch([b],r,c))
      go(Unit{})
    case xs: branch(xs,r,c)

def node(row: Bool,lo: Index,hi: Index) -> Index:
  match row lo hi:
    case _ General{} _: General{}
    case _ _ General{}: General{}
    case True{} a b: Rows{a,b}
    case False{} a b: Cols{a,b}

def tree(budget: Nat,next: Next) -> Index:
  match budget next:
    case _ CompleteIndex{t}: t
    case 1n+m CutTiles{is_row,+r,+c,lo,hi}:
      +k = m
      node(is_row,tree(k,split(lo,r,c)),tree(k,split(hi,r,c)))
    case 0n _: General{}

def axis_valid(+at: Nat,+bits: Nat,limit: Nat) -> Bool:
  Nat.is_lt(at,limit) && Nat.is_eq(Nat.mod(at,Nat.pow(2n,bits)),0n)

def aligned(bs: Tiles,+rows: Nat,+cols: Nat) -> Bool:
  match bs:
    case []: True{}
    case Block{i,c,_,_,bi,bc,_,_,_} <> rest:
      axis_valid(i,bi,rows) && axis_valid(c,bc,cols) && aligned(rest,rows,cols)

def index(+rows: Nat,+cols: Nat,+bs: Tiles) -> Index:
  +r = Sample.row_bits(rows)
  +c = Sample.row_bits(cols)
  go = Bool.pick(Unit -> Index,aligned(bs,rows,cols),_ => tree(Nat.add(r,c),split(bs,r,c)),_ => General{})
  go(Unit{})

type Matrix is Data:
  Matrix{message: Nat, rows: Nat, columns: Nat, blocks: List<&2,Block>, index: Index}
def Book() -> Data: Map<&2,Maybe<&2,Matrix>>
type Cut<-A: Data> is Data:
  Cut{value: A, tail: H.Bytes}

def key(link: Nat, name: String) -> String: Nat.show(link) ++ "/" ++ name

def words(n: Nat, raw: H.Bytes, acc: List<&2,Nat>) -> IO(Cut<List<&2,Nat>>):
  match n raw:
    case 0n left: IO.pure(Cut<List<&2,Nat>>,Cut{List.reverse(&2,Nat,acc),left})
    case 1n+k a <> b <> c <> d <> e <> f <> 0 <> 0 <> more:
      hi = U32.to_nat(U32.or(e,U32.shln(f,8n)))
      lo = U32.to_nat(Header.le32(a,b,c,d))
      words(k,more,Nat.add(lo,Nat.mul(Nat.pow(2n,32n),hi)) <> acc)
    case _ _: IO.die(Cut<List<&2,Nat>>,1,"NO: segment-layout-integer")

def block_list(n: Nat, xs: List<&2,Nat>, acc: List<&2,Block>) -> IO(List<&2,Block>):
  match n xs:
    case 0n Nil{}: IO.pure(List<&2,Block>,List.reverse(&2,Block,acc))
    case 1n+k i <> c <> r <> p <> bi <> bc <> br <> bp <> low <> rest:
      block_list(k,rest,Block{i,c,r,p,bi,bc,br,bp,Nat.is_eq(low,1n)} <> acc)
    case _ _: IO.die(List<&2,Block>,1,"NO: segment-layout-block")

def placed(k: String, book: Book, m: Nat, +rows: Nat, +cols: Nat, n: Nat, cut: Cut<List<&2,Nat>>) -> IO(Cut<Book>):
  Cut{data,tail} = cut
  do IO<Cut<Book>>:
    +pieces : List<&2,Block> <- block_list(n,data,[])
    return Cut{Map.set(&2,Maybe<&2,Matrix>,book,k,Some{Matrix{m,rows,cols,pieces,index(rows,cols,pieces)}}),tail}

def metadata(k: String, book: Book, cut: Cut<List<&2,Nat>>) -> IO(Cut<Book>):
  match cut:
    case Cut{[m,rows,cols,+n],raw}:
      do IO<Cut<Book>>:
        data : Cut<List<&2,Nat>> <- words(Nat.mul(n,9n),raw,[])
        placed(k,book,m,rows,cols,n,data)
    case _: IO.die(Cut<Book>,1,"NO: segment-layout-matrix")

def matrix(link: Nat, book: Book, cut: Cut<List<&2,Nat>>) -> IO(Cut<Book>):
  match cut:
    case Cut{[+n],+raw}:
      k = key(link,P.ascii(List.take(&2,U32,raw,n)))
      do IO<Cut<Book>>:
        desc : Cut<List<&2,Nat>> <- words(4n,List.drop(&2,U32,raw,n),[])
        metadata(k,book,desc)
    case _: IO.die(Cut<Book>,1,"NO: segment-layout-name")

def matrices(n: Nat, +link: Nat, cut: Cut<Book>) -> IO(Cut<Book>):
  match n cut:
    case 0n done: IO.pure(Cut<Book>,done)
    case 1n+k Cut{book,raw}:
      do IO<Cut<Book>>:
        length : Cut<List<&2,Nat>> <- words(1n,raw,[])
        next : Cut<Book> <- matrix(link,book,length)
        matrices(k,link,next)

def arrays(length: Cut<List<&2,Nat>>, link: Nat, book: Book) -> IO(Cut<Book>):
  match length:
    case Cut{[n],raw}: matrices(n,link,Cut{book,raw})
    case _: IO.die(Cut<Book>,1,"NO: segment-layout-array-count")

def segments(n: Nat, link: Nat, cut: Cut<Book>) -> IO(Book):
  match n cut:
    case 0n Cut{book,[]}: IO.pure(Book,book)
    case 1n+k Cut{book,raw}:
      +j = link
      do IO<Book>:
        length : Cut<List<&2,Nat>> <- words(1n,raw,[])
        next : Cut<Book> <- arrays(length,j,book)
        segments(k,1n+j,next)
    case _ _: IO.die(Book,1,"NO: segment-layout-tail")

def start(cut: Cut<List<&2,Nat>>) -> IO(Book):
  match cut:
    case Cut{[n],raw}: segments(n,0n,Cut{Map.new(&2,Maybe<&2,Matrix>),raw})
    case _: IO.die(Book,1,"NO: segment-layout-size")

def parse(raw: H.Bytes) -> IO(Book):
  do IO<Book>:
    n : Cut<List<&2,Nat>> <- words(1n,raw,[])
    start(n)

def cat(xs: F.Factors, ys: F.Factors) -> F.Factors:
  List.append(&2,F.Factor,xs,ys)

# Most logical U3 reads fix a cell. Reject a tile as soon as a fixed
# coordinate disagrees, before allocating its destination factor list.
def multiply(p:X.E3,w:X.E3) -> X.E3:
  match p:
    case X.E3{0,0,0,0,0,0}: F.zero()
    case X.E3{0,1,0,0,0,0}: w
    case +v: E.mul(w,v)

# A zero endpoint ends the walk with weight zero.
def upper_value(fs:F.Factors,dead:Bool,+index:Nat,w:X.E3) -> X.E3:
  match fs dead:
    case _ True{}: F.zero()
    case [] False{}: w
    case Con{f,tail} False{}:
      +p = F.at_bit(f,Nat.is_eq(Nat.mod(index,2n),1n))
      upper_value(tail,B.equal(p,F.zero()),Nat.div(index,2n),multiply(p,w))

def upper(fs:F.Factors,at:Nat,+keep:Nat,w:X.E3) -> X.E3:
  upper_value(List.drop(&2,F.Factor,fs,keep),False{},Nat.div(at,Nat.pow(2n,keep)),w)

type Axes is Data:
  Axes{weight:X.E3,rows:F.Factors,columns:F.Factors}

def axes(term:F.Term,+n:Nat) -> Axes:
  F.Term{w,+fs} = term
  Axes{w,List.take(&2,F.Factor,fs,n),List.drop(&2,F.Factor,fs,n)}

def then_upper(zero:Bool,cols:F.Factors,c:Nat,bc:Nat,v:X.E3) -> X.E3:
  match zero:
    case True{}: F.zero()
    case False{}: upper(cols,c,bc,v)

def weight(b:Block,a:Axes) -> X.E3:
  Block{i,c,_,_,bi,bc,_,_,_} = b
  Axes{w,rows,cols} = a
  +v = upper(rows,i,bi,w)
  then_upper(B.equal(v,F.zero()),cols,c,bc,v)

def project(b:Block,a:Axes,dest_rows:Nat,dest_columns:Nat,w:X.E3) -> F.Term:
  Block{_,_,r,p,bi,bc,+br,+bp,low} = b
  Axes{_,ir,ic} = a
  +rows = List.take(&2,F.Factor,ir,bi)
  +cols = List.take(&2,F.Factor,ic,bc)
  +inside = Bool.pick(F.Factors,low,cat(rows,cols),cat(cols,rows))
  rf = cat(List.drop(&2,F.Factor,inside,bp),Tensor.choice(Nat.sub(dest_rows,br),Nat.div(r,Nat.pow(2n,br))))
  cf = cat(List.take(&2,F.Factor,inside,bp),Tensor.choice(Nat.sub(dest_columns,bp),Nat.div(p,Nat.pow(2n,bp))))
  F.Term{w,cat(rf,cf)}

def tile(+b:Block,term:F.Term,row_bits:Nat,dest_rows:Nat,dest_columns:Nat) -> F.Term:
  +a = axes(term,row_bits)
  project(b,a,dest_rows,dest_columns,weight(b,a))

def tile_unless(zero:Bool,b:Block,a:Axes,dr:Nat,dc:Nat,w:X.E3,out:F.Form) -> F.Form:
  match zero:
    case True{}: out
    case False{}: project(b,a,dr,dc,w) <> out

def tiles(bs:List<&2,Block>,+a:Axes,+dr:Nat,+dc:Nat,acc:F.Form) -> F.Form:
  match bs:
    case []: acc
    case +b <> tail:
      +w = weight(b,a)
      tiles(tail,a,dr,dc,tile_unless(B.equal(w,F.zero()),b,a,dr,dc,w,acc))

def translate(ts:F.Form,+bs:List<&2,Block>,+src:Nat,+dr:Nat,+dc:Nat,acc:F.Form) -> F.Form:
  match ts:
    case []: acc
    case t <> tail: translate(tail,bs,src,dr,dc,tiles(bs,axes(t,src),dr,dc,acc))

# Reverse each axis once. On entry to a leaf, the remaining factors are
# exactly its free low bits. The accumulated weight includes its fixed prefix.
def descend(tree: Index,live: Bool,rows: F.Factors,cols: F.Factors,w: X.E3,dr: Nat,dc: Nat,acc: F.Form) -> F.Form:
  match tree live rows cols:
    case _ False{} _ _: acc
    case Rows{a,b} True{} Con{+f,+tail} +xs:
      +r = dr
      +c = dc
      +v = w
      +lo = F.at_bit(f,False{})
      +hi = F.at_bit(f,True{})
      left = descend(a,Bool.not(B.equal(lo,F.zero())),tail,xs,multiply(lo,v),r,c,acc)
      descend(b,Bool.not(B.equal(hi,F.zero())),tail,xs,multiply(hi,v),r,c,left)
    case Cols{a,b} True{} +xs Con{+f,+tail}:
      +r = dr
      +c = dc
      +v = w
      +lo = F.at_bit(f,False{})
      +hi = F.at_bit(f,True{})
      left = descend(a,Bool.not(B.equal(lo,F.zero())),xs,tail,multiply(lo,v),r,c,acc)
      descend(b,Bool.not(B.equal(hi,F.zero())),xs,tail,multiply(hi,v),r,c,left)
    case Leaf{b} True{} rs cs:
      +v = w
      project(b,Axes{v,List.reverse(&2,F.Factor,rs),List.reverse(&2,F.Factor,cs)},dr,dc,v) <> acc
    case _ _ _ _: acc

def indexed_term(valid: Bool,tree: Index,bs: Tiles,+dr: Nat,+dc: Nat,a: Axes,acc: F.Form) -> F.Form:
  match valid a:
    case True{} Axes{+w,rs,cs}: descend(tree,Bool.not(B.equal(w,F.zero())),List.reverse(&2,F.Factor,rs),List.reverse(&2,F.Factor,cs),w,dr,dc,acc)
    case False{} x: tiles(bs,x,dr,dc,acc)

def indexed_terms(ts: F.Form,+tree: Index,+bs: Tiles,+rb: Nat,+width: Nat,+dr: Nat,+dc: Nat,acc: F.Form) -> F.Form:
  match ts:
    case []: acc
    case F.Term{w,+fs} <> tail:
      valid = Nat.is_eq(width,List.length(&2,F.Factor,fs))
      a = axes(F.Term{w,fs},rb)
      indexed_terms(tail,tree,bs,rb,width,dr,dc,indexed_term(valid,tree,bs,dr,dc,a,acc))

def translate_matrix(tree: Index,ts: F.Form,bs: Tiles,rows: Nat,cols: Nat,dr: Nat,dc: Nat) -> F.Form:
  match tree:
    case General{}: translate(ts,bs,Sample.row_bits(rows),dr,dc,[])
    case t:
      +rb = Sample.row_bits(rows)
      indexed_terms(ts,t,bs,rb,Nat.add(rb,Sample.row_bits(cols)),dr,dc,[])

def addressed(m: Matrix, link: Nat, terms: F.Form, width: Nat, member: Frame.Member) -> Frame.On:
  Matrix{msg,n,cols,bs,tree} = m
  Frame.Member{_,rows,_,_,_} = member
  Frame.On{Q.label(link,msg),False{},translate_matrix(tree,terms,bs,n,cols,Sample.row_bits(rows),width)}

def lookup(found: Book & Maybe<&2,Matrix>) -> IO(Matrix):
  (_,m) = found
  K.need(Matrix,m,"NO: segment-layout-array")

def labels(ns: Q.Notices) -> Frame.Members:
  match ns:
    case []: []
    case Q.Notice{m,_,_} <> tail: m <> labels(tail)

def member(link: Q.Link, n: Nat) -> IO(Frame.Member):
  Q.Link{_,ns} = link
  K.need(Frame.Member,List.get(&2,Frame.Member,labels(ns),n),"NO: segment-layout-message")

def columns(c: B.Code) -> Nat:
  B.Code{_,ell,_} = c
  Sample.row_bits(ell)

def on_member(q: Q.Shape, +mat: Matrix, +link: Nat, terms: F.Form) -> IO(Frame.On):
  Q.Shape{code,_,links,_} = q
  Matrix{msg,_,_,_,_} = mat
  do IO<Frame.On>:
    shape : Q.Link <- K.need(Q.Link,List.get(&2,Q.Link,links,link),"NO: segment-layout-link")
    message : Frame.Member <- member(shape,msg)
    return addressed(mat,link,terms,columns(code),message)

def on_main(book: Book, shape: Q.Shape, +link: Nat, name: String, terms: F.Form) -> IO(Frame.On):
  do IO<Frame.On>:
    m : Matrix <- lookup(Map.get(Maybe<&2,Matrix>,None{},book,key(link,name)))
    on_member(shape,m,link,terms)
