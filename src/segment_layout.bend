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
# A matrix with one logical row partitions its columns into aligned dyadic
# intervals. Index these by their high bits so a selector visits only the
# intervals on which it can be nonzero. Other matrices use the general layout.
type Columns is Data:
  Empty{}
  Leaf{block: Block}
  Fork{lo: Columns, hi: Columns}
  General{}

def fork(lo: Columns, hi: Columns) -> Columns:
  match lo hi:
    case General{} _: General{}
    case _ General{}: General{}
    case a b: Fork{a,b}

def add_column(tree: Columns,path: Nat,+interval: Nat,+b: Block) -> Columns:
  match tree path:
    case Empty{} 0n: Leaf{b}
    case _ 0n: General{}
    case General{} 1n+_: General{}
    case Leaf{_} 1n+_: General{}
    case Empty{} 1n+m:
      +k = m
      +half = Nat.pow(2n,k)
      +pre = Nat.mod(interval,half)
      go = Bool.pick(Unit -> Columns,Nat.is_lt(interval,half),
        _ => Fork{add_column(Empty{},k,pre,b),Empty{}},_ => Fork{Empty{},add_column(Empty{},k,pre,b)})
      go(Unit{})
    case Fork{+lo,+hi} 1n+m:
      +k = m
      +half = Nat.pow(2n,k)
      +pre = Nat.mod(interval,half)
      go = Bool.pick(Unit -> Columns,Nat.is_lt(interval,half),
        _ => fork(add_column(lo,k,pre,b),hi),_ => fork(lo,add_column(hi,k,pre,b)))
      go(Unit{})

def insert_column(+tree: Columns,+bits: Nat,b: Block) -> Columns:
  match b:
    case Block{0n,+c,r,p,0n,+k,br,bp,dir}:
      +size = Nat.pow(2n,k)
      go = Bool.pick(Unit -> Columns,Nat.is_le(k,bits) && Nat.is_lt(c,Nat.pow(2n,bits)) && Nat.is_eq(Nat.mod(c,size),0n),
        _ => add_column(tree,Nat.sub(bits,k),Nat.div(c,size),Block{0n,c,r,p,0n,k,br,bp,dir}),_ => General{})
      go(Unit{})
    case _: General{}

def column_blocks(bs: List<&2,Block>,+width: Nat,tree: Columns) -> Columns:
  match bs tree:
    case _ General{}: General{}
    case Nil{} t: t
    case Con{b,tail} t: column_blocks(tail,width,insert_column(t,width,b))

def column_index(rows: Nat,cols: Nat,bs: List<&2,Block>) -> Columns:
  match rows:
    case 1n: column_blocks(bs,Sample.row_bits(cols),Empty{})
    case _: General{}

type Matrix is Data:
  Matrix{message: Nat, rows: Nat, columns: Nat, blocks: List<&2,Block>, index: Columns}
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
    return Cut{Map.set(&2,Maybe<&2,Matrix>,book,k,Some{Matrix{m,rows,cols,pieces,column_index(rows,cols,pieces)}}),tail}

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

def upper_value(fs:F.Factors,+index:Nat,w:X.E3) -> X.E3:
  match fs:
    case []: w
    case f <> tail:
      +p = F.at_bit(f,Nat.is_eq(Nat.mod(index,2n),1n))
      go = Bool.pick(Unit -> X.E3,B.equal(p,F.zero()),_ => F.zero(),
        _ => upper_value(tail,Nat.div(index,2n),multiply(p,w)))
      go(Unit{})

def upper(fs:F.Factors,at:Nat,+keep:Nat,w:X.E3) -> X.E3:
  upper_value(List.drop(&2,F.Factor,fs,keep),Nat.div(at,Nat.pow(2n,keep)),w)

type Axes is Data:
  Axes{weight:X.E3,rows:F.Factors,columns:F.Factors}

def axes(term:F.Term,+n:Nat) -> Axes:
  F.Term{w,+fs} = term
  Axes{w,List.take(&2,F.Factor,fs,n),List.drop(&2,F.Factor,fs,n)}

def weight(b:Block,a:Axes) -> X.E3:
  Block{i,c,_,_,bi,bc,_,_,_} = b
  Axes{w,rows,cols} = a
  +v = upper(rows,i,bi,w)
  go = Bool.pick(Unit -> X.E3,B.equal(v,F.zero()),_ => F.zero(),_ => upper(cols,c,bc,v))
  go(Unit{})

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

def tiles(bs:List<&2,Block>,+a:Axes,+dr:Nat,+dc:Nat,acc:F.Form) -> F.Form:
  match bs:
    case []: acc
    case +b <> tail:
      +w = weight(b,a)
      +out = acc
      go = Bool.pick(Unit -> F.Form,B.equal(w,F.zero()),_ => out,_ => project(b,a,dr,dc,w) <> out)
      tiles(tail,a,dr,dc,go(Unit{}))

def translate(ts:F.Form,+bs:List<&2,Block>,+src:Nat,+dr:Nat,+dc:Nat,acc:F.Form) -> F.Form:
  match ts:
    case []: acc
    case t <> tail: translate(tail,bs,src,dr,dc,tiles(bs,axes(t,src),dr,dc,acc))

# At a leaf the free low source coordinates are exactly the remaining ones.
# The prefix weight already includes every fixed high source coordinate.
def descend(tree: Columns,rev: F.Factors,w: X.E3,dr: Nat,dc: Nat,acc: F.Form) -> F.Form:
  match tree rev w:
    case _ _ X.E3{0,0,0,0,0,0}: acc
    case Fork{a,b} Con{F.Factor{l,h},+tail} +v:
      +r = dr
      +c = dc
      left = descend(a,tail,multiply(l,v),r,c,acc)
      descend(b,tail,multiply(h,v),r,c,left)
    case Leaf{b} xs +v: project(b,Axes{v,[],List.reverse(&2,F.Factor,xs)},dr,dc,v) <> acc
    case _ _ _: acc

def indexed_term(valid: Bool,tree: Columns,bs: List<&2,Block>,+dr: Nat,+dc: Nat,w: X.E3,fs: F.Factors,acc: F.Form) -> F.Form:
  match valid:
    case True{}: descend(tree,List.reverse(&2,F.Factor,fs),w,dr,dc,acc)
    case False{}: tiles(bs,Axes{w,[],fs},dr,dc,acc)

def indexed_terms(ts: F.Form,+tree: Columns,+bs: List<&2,Block>,+width: Nat,+dr: Nat,+dc: Nat,acc: F.Form) -> F.Form:
  match ts:
    case []: acc
    case F.Term{w,+fs} <> tail:
      valid = Nat.is_eq(width,List.length(&2,F.Factor,fs))
      indexed_terms(tail,tree,bs,width,dr,dc,indexed_term(valid,tree,bs,dr,dc,w,fs,acc))

def translate_matrix(tree: Columns,ts: F.Form,bs: List<&2,Block>,rows: Nat,cols: Nat,dr: Nat,dc: Nat) -> F.Form:
  match tree:
    case General{}: translate(ts,bs,Sample.row_bits(rows),dr,dc,[])
    case t: indexed_terms(ts,t,bs,Sample.row_bits(cols),dr,dc,[])

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
