import Base
import ./key_stage_geometry.bend as G
import ./key_stage_trace.bend as Trace
import ./key_stage_base.bend as B
import ./hash_bytes.bend as H
import ./merkle.bend as M
import ./opening_bytes.bend as O
import ./wire_reader.bend as R

type Root is Data:
  Root{digest: M.Digest, number: U32, start: M.Digest}

def Book() -> Data:
  List<&2,Root>

def need(-A: Data, value: Maybe<&2,A>, error: String) -> IO(A):
  match value:
    case Some{x}: IO.pure(A,x)
    case None{}: IO.die(A,1,error)

def digest(raw: H.Bytes) -> IO(M.Digest):
  need(M.Digest,O.read_digest(raw),"NO: digest")

def add(count: Nat, +raw: H.Bytes, +run: M.Digest, book: Book, +next: Nat) -> IO(Book):
  match count:
    case 0n: IO.pure(Book,book)
    case 1n+k:
      do IO<Book>:
        root : M.Digest <- digest(List.take(&2,U32,raw,32n))
        add(k,List.drop(&2,U32,raw,32n),run,
          List.append(&2,Root,book,[Root{root,U32.from_nat(next),run}]),1n+next)

def at(book: Book, place: Nat) -> IO(Root):
  need(Root,List.get(&2,Root,book,place),"NO: tree-place")

type Published is Data:
  Published{shape: O.Shape, root: M.Digest}

def ordinary(root: Root, d: Nat, w: Nat, s: Nat) -> Published:
  Root{digest,number,start} = root
  Published{O.Shape{164,number,d,w,s,start},digest}

def select(tree: G.Tree, book: Book, table: M.Digest, config: M.Digest) -> IO(Published):
  match tree:
    case G.Tree{G.Table{},d,w,s}: IO.pure(Published,Published{O.Shape{174,0,d,w,s,config},table})
    case G.Tree{G.Local{i},d,w,s}:
      do IO<Published>:
        root : Root <- at(book,i)
        return ordinary(root,d,w,s)

def verified(pair: R.Reader & H.Bytes, shape: O.Shape, config: M.Digest, root: M.Digest,
  xs: O.Places, session: O.Session) -> IO(R.Reader & O.Opened):
  (r,raw) = pair
  do IO<R.Reader & O.Opened>:
    checked : O.Opened <- need(O.Opened,O.verify(shape,config,root,xs,raw,session),"NO: opening")
    return (r,checked)

def open_at(published: Published, +config: M.Digest, places: O.Places, r: R.Reader, session: O.Session) -> IO(R.Reader & O.Opened):
  Published{+shape,root} = published
  O.Shape{_,_,d,_,_,_} = shape
  +xs = O.positions(d,places)
  do IO<R.Reader & O.Opened>:
    size : Nat <- need(Nat,O.encoded_size(shape,xs),"NO: opening-size")
    data : R.Reader & H.Bytes <- R.take(r,U32.from_nat(size))
    verified(data,shape,config,root,xs,session)

type Group is Data:
  Group{session: O.Session, openings: Trace.Openings}

def retain(pair: R.Reader & O.Opened, mode: B.Check, xs: O.Places, tree: G.Tree, acc: Trace.Openings) -> IO(R.Reader & Group):
  (r,x) = pair
  O.Opened{+cols,session} = x
  do IO<R.Reader & Group>:
    eq : Unit <- B.check(mode,xs,cols)
    return (r,Group{session,Trace.Opening{tree,cols} <> acc})

def depth(tree: G.Tree) -> Nat:
  G.Tree{_,d,_,_} = tree
  d

def open_group(trees: List<&2,G.Tree>, +config: M.Digest, +table: M.Digest, +book: Book,
  +places: O.Places, +mode: B.Check, state: R.Reader & Group) -> IO(R.Reader & Group):
  match trees state:
    case Nil{} Tuple{r,Group{session,reverse}}:
      IO.pure(R.Reader & Group,(r,Group{session,List.reverse(&2,Trace.Opening,reverse)}))
    case Con{+tree,tail} Tuple{r,Group{session,acc}}:
      do IO<R.Reader & Group>:
        published : Published <- select(tree,book,table,config)
        pair : R.Reader & O.Opened <- open_at(published,config,places,r,session)
        next : R.Reader & Group <- retain(pair,mode,O.positions(depth(tree),places),tree,acc)
        open_group(tail,config,table,book,places,mode,next)
