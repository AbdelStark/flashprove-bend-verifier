import Base
import ./merkle.bend as Tree
import ./opening.bend as Path
import ./hash_bytes.bend as H
import ./chain.bend as Bits
import ./pow2.bend as P2

type Shape is Data:
  Shape{tag: U32, tree: U32, depth: Nat, width: Nat, salt: Nat, start: Tree.Digest}

type Column is Data:
  Column{place: Nat, limbs: H.Bytes}

def Places() -> Data:
  List<&2,Nat>
def Columns() -> Data:
  List<&2,Column>
def Session() -> Data:
  Map<&2,Path.Record>

type Opened is Data:
  Opened{columns: Columns, session: Session}

def empty_session() -> Session:
  Map.new(&2,Path.Record)

def digest_bytes(d: Tree.Digest) -> H.Bytes:
  Tree.Digest{a,b,c,d,e,f,g,h} = d
  H.cat([H.le(a),H.le(b),H.le(c),H.le(d),H.le(e),H.le(f),H.le(g),H.le(h)])

# A session names each root by its eight words.
def root_key(d: Tree.Digest) -> String:
  Tree.Digest{a,b,c,e,f,g,h,i} = d
  SCon{Chr{a},SCon{Chr{b},SCon{Chr{c},SCon{Chr{e},SCon{Chr{f},SCon{Chr{g},SCon{Chr{h},SCon{Chr{i},SNil{}}}}}}}}}

def as_digest(words: H.Bytes) -> Maybe<&2,Tree.Digest>:
  match words:
    case [a,b,c,d,e,f,g,h]: Some{Tree.Digest{a,b,c,d,e,f,g,h}}
    case _: None{}

def read_digest(+bytes: H.Bytes) -> Maybe<&2,Tree.Digest>:
  # u32s pads its last word, so an incomplete digest must be rejected first.
  Bool.pick(Maybe<&2,Tree.Digest>,Nat.is_eq(H.length(bytes),32n),as_digest(H.u32s(bytes)),None{})

def short(depth: Nat, place: Nat) -> Nat:
  match depth:
    case 48n: place
    case k: Nat.mod(place,P2.pow2(k))

def unique(xs: Places, previous: Maybe<&2,Nat>) -> Places:
  match xs previous:
    case [] _: []
    case +i <> tail None{}: i <> unique(tail,Some{i})
    case +i <> tail Some{j}:
      +rest = unique(tail,Some{i})
      Bool.pick(Places,Nat.is_eq(i,j),rest,i <> rest)

def reduce_places(xs: Places, +k: Nat) -> Places:
  match xs:
    case []: []
    case i <> tail: short(k,i) <> reduce_places(tail,k)

def positions(depth: Nat, raw: Places) -> Places:
  unique(List.sort(Nat,a => b => Nat.is_le(a,b),reduce_places(raw,Nat.min(depth,48n))),None{})

def valid_after(xs: Places, +depth: Nat, previous: Nat) -> Bool:
  match xs:
    case []: True{}
    case +i <> tail: Nat.is_lt(previous,i) && Nat.is_eq(i,short(depth,i)) && valid_after(tail,depth,i)

def valid_places(xs: Places, +depth: Nat) -> Bool:
  match xs:
    case []: False{}
    case +i <> tail: Nat.is_eq(i,short(depth,i)) && valid_after(tail,depth,i)

def parent_places(xs: Places) -> Places:
  match xs:
    case []: []
    case i <> tail: Nat.div(i,2n) <> parent_places(tail)

# R7.9. For each pair of children supporting a parent, the missing children are given.
def sibling_count(depth: Nat, +xs: Places) -> Nat:
  match depth:
    case 0n: 0n
    case 1n+p:
      +next = unique(parent_places(xs),None{})
      count = Nat.sub(Nat.mul(2n,List.length(&2,Nat,next)),List.length(&2,Nat,xs))
      Nat.add(count,sibling_count(p,next))

def valid_shape(shape: Shape) -> Bool:
  Shape{+tag,+tree,depth,+width,+salt,start} = shape
  tag_ok = (U32.is_eq(tag,164) && U32.is_lt(tree,65536)) ||
    (U32.is_eq(tag,174) && U32.is_zero(tree)) ||
    (U32.is_eq(tag,173) && U32.is_zero(tree) && Nat.is_eq(width,4n))
  tag_ok && Nat.is_le(depth,48n) && Nat.is_ge(width,1n) && Nat.is_lt(width,16777216n) &&
    Nat.is_ge(salt,40n) && Nat.is_le(salt,64n) && Nat.is_eq(Nat.mod(salt,8n),0n) &&
    Bool.not(Path.digest_equal(start,Tree.Digest{0,0,0,0,0,0,0,0}))

def bounded_size(depth: Nat, +xs: Places, stride: Nat, count: Nat, ok: Bool) -> Maybe<&2,Nat>:
  match ok:
    case False{}: None{}
    case True{}:
      +size = Nat.add(Nat.mul(stride,count),Nat.mul(32n,sibling_count(depth,xs)))
      Bool.pick(Maybe<&2,Nat>,Nat.is_le(size,4294967295n),Some{size},None{})

def checked_size(+shape: Shape, +xs: Places, ok: Bool) -> Maybe<&2,Nat>:
  match shape ok:
    case _ False{}: None{}
    case Shape{_,_,+depth,width,salt,_} True{}:
      +stride = Nat.add(Nat.mul(8n,width),salt)
      +count = List.length(&2,Nat,xs)
      bounded_size(depth,xs,stride,count,Nat.is_le(count,Nat.div(4294967295n,stride)) && valid_places(xs,depth))

def encoded_size(+shape: Shape, xs: Places) -> Maybe<&2,Nat>:
  checked_size(shape,xs,valid_shape(shape))

def width(shape: Shape) -> Nat:
  Shape{_,_,_,w,_,_} = shape
  w

def salt_bytes(shape: Shape) -> Nat:
  Shape{_,_,_,_,n,_} = shape
  n

# Leaf index can require 49 bits at depth 48. Keep it in two explicit limbs.
def leaf_index(+depth: Nat, +x: Nat) -> H.Bytes:
  high = U32.add(U32.from_nat(Nat.div(x,P2.pow2(32n))),Bool.pick(U32,Nat.is_ge(depth,32n),U32.shln(1,Nat.sub(depth,32n)),0))
  low = U32.add(U32.from_nat(x),Bool.pick(U32,Nat.is_lt(depth,32n),U32.shln(1,Nat.min(depth,31n)),0))
  H.cat([H.le(low),H.le(high)])

# R7.3. Fill never appears in the proof. Its length makes the salt fit in the final block.
def leaf(shape: Shape, place: Nat, column: H.Bytes, salt: H.Bytes) -> Maybe<&2,Tree.Digest>:
  Shape{tag,tree,depth,+w,+s,start} = shape
  +at = Nat.mod(Nat.add(16n,Nat.mul(8n,w)),128n)
  pad = Bool.pick(Nat,Nat.is_gt(Nat.add(at,s),128n),Nat.sub(128n,at),0n)
  lo = U32.or(tag,U32.shln(tree,16n))
  hi = U32.or(U32.from_nat(w),U32.shln(U32.from_nat(Nat.div(s,8n)),24n))
  label = H.cat([H.le(lo),H.le(hi),leaf_index(depth,place)])
  as_digest(H.u32s(H.digest(label,digest_bytes(start),H.cat([column,H.zero(pad),salt]),32)))

def canonical(words: H.Bytes) -> Bool:
  match words:
    case []: True{}
    case lo <> hi <> tail: U32.is_ne(Bits.field_candidate(hi,lo),0) && canonical(tail)
    case _: False{}

def is_binding(shape: Shape) -> Bool:
  Shape{tag,_,_,_,_,_} = shape
  U32.is_eq(tag,173)

type Parsed is Data:
  Parsed{leaves: Path.Nodes, columns: Columns, tail: H.Bytes}
  Bad{}

def prepend(+i: Nat, limbs: H.Bytes, digest: Maybe<&2,Tree.Digest>, rest: Parsed, valid: Bool) -> Parsed:
  match digest rest valid:
    case Some{d} Parsed{ls,cs,tail} True{}: Parsed{Path.Node{i,d} <> ls,Column{i,limbs} <> cs,tail}
    case _ _ _: Bad{}

# One place's column and salt, and the bytes after them.
type Piece is Data:
  Piece{column: H.Bytes, salt: H.Bytes, rest: H.Bytes}
  Remaining{rest: H.Bytes}

# Cut k column bytes, then m salt bytes, in one pass that never shares the input.
def cut(k: Nat, m: Nat, input: H.Bytes, col: H.Bytes, salt: H.Bytes) -> Piece:
  match k m input:
    case 1n+a _ Con{x,rest}: cut(a,m,rest,x <> col,salt)
    case 0n 1n+b Con{x,rest}: cut(0n,b,rest,col,x <> salt)
    case _ _ rest: Piece{List.reverse(&2,U32,col),List.reverse(&2,U32,salt),rest}

def next_piece(xs: Places, +shape: Shape, input: H.Bytes) -> Piece:
  match xs:
    case []: Remaining{input}
    case _: cut(Nat.mul(8n,width(shape)),salt_bytes(shape),input,[],[])

def columns_cut(xs: Places, +shape: Shape, piece: Piece) -> Parsed:
  match xs piece:
    case Con{+i,+tail} Piece{+col,salt,rest}:
      +limbs = H.u32s(col)
      more = columns_cut(tail,shape,next_piece(tail,shape,rest))
      prepend(i,limbs,leaf(shape,i,col,salt),more,is_binding(shape) || canonical(limbs))
    case Nil{} Remaining{rest}: Parsed{[],[],rest}
    case _ _: Bad{}

def columns(+xs: Places, +shape: Shape, input: H.Bytes) -> Parsed:
  columns_cut(xs,shape,next_piece(xs,shape,input))

def digests(words: H.Bytes) -> Path.Siblings:
  match words:
    case a <> b <> c <> d <> e <> f <> g <> h <> tail:
      Tree.Digest{a,b,c,d,e,f,g,h} <> digests(tail)
    case _: []

def save(session: Session, key: String, cs: Columns, tracking: Path.Tracking) -> Maybe<&2,Opened>:
  match tracking:
    case Path.Track{r}: Some{Opened{cs,Map.set(&2,Path.Record,session,key,r)}}
    case _: None{}

def verify_parsed(shape: Shape, config: Tree.Digest, root: Tree.Digest, key: String, parsed: Parsed, stored: Session & Path.Record) -> Maybe<&2,Opened>:
  match shape parsed stored:
    case _ Bad{} _: None{}
    case Shape{tag,_,depth,_,_,_} Parsed{ls,cs,tail} Tuple{session,record}:
      saved = Path.authenticate(depth,U32.is_eq(tag,173),config,ls,digests(H.u32s(tail)),root,Path.Track{record})
      save(session,key,cs,saved)

def verify_length(+shape: Shape, config: Tree.Digest, +root: Tree.Digest, xs: Places, input: H.Bytes, session: Session, ok: Bool) -> Maybe<&2,Opened>:
  match ok:
    case False{}: None{}
    case True{}:
      +key = root_key(root)
      stored = Map.get(Path.Record,Map.new(&2,Path.Value),session,key)
      verify_parsed(shape,config,root,key,columns(xs,shape,input),stored)

def bound_start(shape: Shape, config: Tree.Digest) -> Bool:
  Shape{tag,_,_,_,_,start} = shape
  U32.is_eq(tag,164) || Path.digest_equal(config,start)

def verify_size(+shape: Shape, +config: Tree.Digest, root: Tree.Digest, xs: Places, +input: H.Bytes, session: Session, expected: Maybe<&2,Nat>) -> Maybe<&2,Opened>:
  match expected:
    case None{}: None{}
    case Some{n}: verify_length(shape,config,root,xs,input,session,bound_start(shape,config) && Nat.is_eq(n,H.length(input)))

# The exact opening slice has no counts, positions, directions or padding in its encoding.
def verify(+shape: Shape, config: Tree.Digest, root: Tree.Digest, +xs: Places, input: H.Bytes, session: Session) -> Maybe<&2,Opened>:
  verify_size(shape,config,root,xs,input,session,encoded_size(shape,xs))

# R7.18. A binding path carries one slot, an opaque seal column and raw siblings.
# Its computed root goes into the shared chain's statement and randomness.
def bind_parent(+config: Tree.Digest, here: Tree.Digest, other: Tree.Digest, right: Bool) -> Tree.Digest:
  match right:
    case False{}: Tree.parent(0,178,0,0,config,here,other)
    case True{}: Tree.parent(0,178,0,0,config,other,here)

def binding_walk(path: Path.Siblings, +config: Tree.Digest, +slot: Nat, here: Tree.Digest) -> Tree.Digest:
  match path:
    case []: here
    case other <> tail:
      binding_walk(tail,config,Nat.div(slot,2n),bind_parent(config,here,other,Nat.is_eq(Nat.mod(slot,2n),1n)))

def binding_leaf(config: Tree.Digest, slot: Nat, path: Path.Siblings, leaf: Maybe<&2,Tree.Digest>) -> Maybe<&2,Tree.Digest>:
  match leaf:
    case None{}: None{}
    case Some{v}: Some{binding_walk(path,config,slot,v)}

def binding_checked(depth: Nat, +slot: Nat, +config: Tree.Digest, seal: H.Bytes, +salt: H.Bytes, path: Path.Siblings, valid: Bool) -> Maybe<&2,Tree.Digest>:
  match valid:
    case False{}: None{}
    case True{}:
      shape: Shape = Shape{173,0,depth,4n,H.length(salt),config}
      binding_leaf(config,slot,path,leaf(shape,slot,seal,salt))

def binding_root(+depth: Nat, +slot: Nat, +config: Tree.Digest, +seal: H.Bytes, +salt: H.Bytes, +salt_size: Nat, +path: Path.Siblings) -> Maybe<&2,Tree.Digest>:
  shape: Shape = Shape{173,0,depth,4n,salt_size,config}
  valid = valid_shape(shape) && Nat.is_eq(H.length(seal),32n) && Nat.is_eq(H.length(salt),salt_size) &&
    Nat.is_eq(List.length(&2,Tree.Digest,path),depth) && Nat.is_eq(slot,short(Nat.min(depth,48n),slot))
  binding_checked(depth,slot,config,seal,salt,path,valid)

def retained(opened: Opened) -> Session:
  Opened{_,session} = opened
  session

# R7.14 also covers the below-root vertices of the computed R7.18 binding root.
def binding_record(depth: Nat,slot: Nat,+config: Tree.Digest,root: Tree.Digest,salt_size: Nat,opening: H.Bytes,session: Session) -> Maybe<&2,Opened>:
  verify(Shape{173,0,depth,4n,salt_size,config},config,root,[slot],opening,session)
