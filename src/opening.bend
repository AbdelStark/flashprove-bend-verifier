import Base
import ./merkle.bend as Tree

# R7.8-10. Positions come from the verifier and siblings are in level order.
type Node is Data:
  Node{place: Nat, value: Tree.Digest}

def Nodes() -> Data:
  List<&2, Node>
def Siblings() -> Data:
  List<&2, Tree.Digest>

def digest_equal(a: Tree.Digest, b: Tree.Digest) -> Bool:
  Tree.Digest{a0,a1,a2,a3,a4,a5,a6,a7} = a
  Tree.Digest{b0,b1,b2,b3,b4,b5,b6,b7} = b
  U32.is_eq(a0,b0) && U32.is_eq(a1,b1) && U32.is_eq(a2,b2) && U32.is_eq(a3,b3) && U32.is_eq(a4,b4) && U32.is_eq(a5,b5) && U32.is_eq(a6,b6) && U32.is_eq(a7,b7)

def ordered_after(xs: Nodes, previous: Nat) -> Bool:
  match xs:
    case []: True{}
    case Node{+i,_} <> rest: Nat.is_lt(previous, i) && ordered_after(rest, i)

def ordered(xs: Nodes) -> Bool:
  match xs:
    case []: False{}
    case Node{i,_} <> rest: ordered_after(rest, i)

# R7.14. The outer caller shares one vertex record per root across the session.
# The pair depth/place also names vertices past Bend Nat's largest immediate.
def Value() -> Data:
  Maybe<&2, Tree.Digest>
def Record() -> Data:
  Map<&2, Value>

type Tracking is Data:
  Skip{}
  Track{record: Record}
  Conflict{}

def merging(record: Record, key: String, +v: Tree.Digest, found: Value) -> Tracking:
  match found:
    case None{}: Track{Map.set(&2,Value,record,key,Some{v})}
    case Some{old}: Bool.pick(Tracking,digest_equal(v,old),Track{record},Conflict{})

def insert(key: String, v: Tree.Digest, entry: Record & Value) -> Tracking:
  (r,found) = entry
  merging(r,key,v,found)

# One character each for the depth and the low and high words of the place.
# Map compares keys bit by bit, so a short fixed-width key is cheap.
def key(depth: Nat, +i: Nat) -> String:
  SCon{Chr{U32.from_nat(depth)},SCon{Chr{U32.from_nat(i)},SCon{Chr{U32.from_nat(Nat.div(Nat.div(i,65536n),65536n))},SNil{}}}}

def remember(book: Tracking, depth: Nat, i: Nat, v: Tree.Digest) -> Tracking:
  match book:
    case Skip{}: Skip{}
    case Conflict{}: Conflict{}
    case Track{r}:
      +k = key(depth,i)
      insert(k,v,Map.get(Value,None{},r,k))

type Level is Data:
  Level{current: Nodes, given: Siblings, parents: Nodes, book: Tracking}
  Invalid{}

def pair(+depth: Nat, tag: U32, config: Tree.Digest, +left_pos: Nat, +left: Tree.Digest, +right: Tree.Digest,
         rest: Nodes, given: Siblings, parents: Nodes, book: Tracking) -> Level:
  seen = remember(remember(book,depth,left_pos,left),depth,Nat.add(left_pos,1n),right)
  node: Node = Node{Nat.div(left_pos,2n),Tree.parent(0,tag,0,0,config,left,right)}
  Level{rest,given,node <> parents,seen}

def with_sibling(depth: Nat, tag: U32, config: Tree.Digest, +i: Nat, v: Tree.Digest,
                 xs: Nodes, given: Siblings, parents: Nodes, book: Tracking, odd: Bool) -> Level:
  match given odd:
    case [] _: Invalid{}
    case other <> rest True{}: pair(depth,tag,config,Nat.sub(i,1n),other,v,xs,rest,parents,book)
    case other <> rest False{}: pair(depth,tag,config,i,v,other,xs,rest,parents,book)

def neighboring(depth: Nat, tag: U32, config: Tree.Digest, +i: Nat, v: Tree.Digest, j: Nat, w: Tree.Digest,
                rest: Nodes, given: Siblings, parents: Nodes, book: Tracking, paired: Bool) -> Level:
  match paired:
    case True{}: pair(depth,tag,config,i,v,w,rest,given,parents,book)
    case False{}: with_sibling(depth,tag,config,i,v,Node{j,w} <> rest,given,parents,book,Nat.is_eq(Nat.mod(i,2n),1n))

def advance(depth: Nat, tag: U32, config: Tree.Digest, state: Level) -> Level:
  match state:
    case Invalid{}: Invalid{}
    case Level{[],g,ps,b}: Level{[],g,ps,b}
    case Level{Node{+i,v} <> [],g,ps,b}:
      with_sibling(depth,tag,config,i,v,[],g,ps,b,Nat.is_eq(Nat.mod(i,2n),1n))
    case Level{Node{+i,v} <> Node{+j,w} <> rest,g,ps,b}:
      neighboring(depth,tag,config,i,v,j,w,rest,g,ps,b,Nat.is_eq(Nat.div(i,2n),Nat.div(j,2n)))

def scan(fuel: Nat, +depth: Nat, +tag: U32, +config: Tree.Digest, state: Level) -> Level:
  match fuel state:
    case _ Invalid{}: Invalid{}
    case _ Level{[],g,ps,b}: Level{List.reverse(&2,Node,ps),g,[],b}
    case 0n _: Invalid{}
    case 1n+p Level{xs,g,ps,b}: scan(p,depth,tag,config,advance(depth,tag,config,Level{xs,g,ps,b}))

def scan_level(depth: Nat, tag: U32, config: Tree.Digest, state: Level) -> Level:
  match state:
    case Invalid{}: Invalid{}
    case Level{+xs,g,ps,b}: scan(List.length(&2,Node,xs),depth,tag,config,Level{xs,g,ps,b})

def walk(+depth: Nat, +tag: U32, +config: Tree.Digest, state: Level) -> Level:
  match depth:
    case 0n: state
    case 1n+p: walk(p,tag,config,scan_level(Nat.add(p,1n),tag,config,state))

def matches(state: Level, expected: Tree.Digest) -> Tracking:
  match state:
    case Level{Node{0n,v} <> [],[],[],b}: Bool.pick(Tracking,digest_equal(v,expected),b,Conflict{})
    case _: Conflict{}

def checked(valid: Bool, depth: Nat, binding: Bool, config: Tree.Digest, leaves: Nodes, given: Siblings, root: Tree.Digest, book: Tracking) -> Tracking:
  match valid:
    case False{}: Conflict{}
    case True{}: matches(walk(depth,Bool.pick(U32,binding,178,166),config,Level{leaves,given,[],book}),root)

def authenticate(+depth: Nat, binding: Bool, +config: Tree.Digest, +leaves: Nodes, given: Siblings, root: Tree.Digest, book: Tracking) -> Tracking:
  no_start = digest_equal(config,Tree.Digest{0,0,0,0,0,0,0,0})
  checked(Nat.is_le(depth,48n) && ordered(leaves) && Bool.not(no_start),depth,binding,config,leaves,given,root,book)

def ok(result: Tracking) -> Bool:
  match result:
    case Conflict{}: False{}
    case _: True{}

def check(depth: Nat, binding: Bool, config: Tree.Digest, leaves: Nodes, given: Siblings, root: Tree.Digest) -> Bool:
  ok(authenticate(depth,binding,config,leaves,given,root,Skip{}))
