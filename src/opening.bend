import Base
import ./merkle.bend as Tree

# Positions and opened leaf digests come from the verifier. Only the siblings
# are supplied by the opening (R7.9–10). Positions are already deduplicated.
type Node is Data:
  Node{place: Nat, value: Tree.Digest}

def Nodes() -> Data:
  List<&2, Node>
def Siblings() -> Data:
  List<&2, Tree.Digest>

type Level is Data:
  Level{current: Nodes, given: Siblings, parents: Nodes}
  Invalid{}

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

def parent(tag: U32, config: Tree.Digest, i: Nat, left: Tree.Digest, right: Tree.Digest) -> Node:
  Node{Nat.div(i, 2n), Tree.parent(0, tag, 0, 0, config, left, right)}

def with_sibling(tag: U32, config: Tree.Digest, +i: Nat, v: Tree.Digest, xs: Nodes, given: Siblings, parents: Nodes, odd: Bool) -> Level:
  match given odd:
    case [] _: Invalid{}
    case other <> rest True{}:
      Level{xs, rest, parent(tag, config, i, other, v) <> parents}
    case other <> rest False{}:
      Level{xs, rest, parent(tag, config, i, v, other) <> parents}

def neighboring(tag: U32, config: Tree.Digest, +i: Nat, v: Tree.Digest, +j: Nat, w: Tree.Digest,
                rest: Nodes, given: Siblings, parents: Nodes, paired: Bool) -> Level:
  match paired:
    case True{}:
      Level{rest, given, parent(tag, config, i, v, w) <> parents}
    case False{}:
      with_sibling(tag, config, i, v, Node{j,w} <> rest, given, parents, Nat.is_eq(Nat.mod(i, 2n), 1n))

def advance(tag: U32, config: Tree.Digest, state: Level) -> Level:
  match state:
    case Invalid{}: Invalid{}
    case Level{[], g, ps}: Level{[], g, ps}
    case Level{Node{+i,v} <> [], g, ps}:
      with_sibling(tag, config, i, v, [], g, ps, Nat.is_eq(Nat.mod(i, 2n), 1n))
    case Level{Node{+i,v} <> Node{+j,w} <> rest, g, ps}:
      neighboring(tag, config, i, v, j, w, rest, g, ps, Nat.is_eq(Nat.div(i, 2n), Nat.div(j, 2n)))

def scan(fuel: Nat, +tag: U32, +config: Tree.Digest, state: Level) -> Level:
  match fuel state:
    case _ Invalid{}: Invalid{}
    case _ Level{[], g, ps}: Level{List.reverse(&2, Node, ps), g, []}
    case 0n _: Invalid{}
    case 1n+p Level{xs,g,ps}:
      scan(p, tag, config, advance(tag, config, Level{xs,g,ps}))

def scan_level(tag: U32, config: Tree.Digest, state: Level) -> Level:
  match state:
    case Invalid{}: Invalid{}
    case Level{+xs,g,ps}: scan(List.length(&2, Node, xs), tag, config, Level{xs,g,ps})

def walk(depth: Nat, +tag: U32, +config: Tree.Digest, state: Level) -> Level:
  match depth:
    case 0n: state
    case 1n+p: walk(p, tag, config, scan_level(tag, config, state))

def matches(state: Level, expected: Tree.Digest) -> Bool:
  match state:
    case Level{Node{0n, value} <> [], [], []}: digest_equal(value, expected)
    case _: False{}

def checked(valid: Bool, depth: Nat, binding: Bool, config: Tree.Digest, leaves: Nodes, given: Siblings, root: Tree.Digest) -> Bool:
  match valid:
    case False{}: False{}
    case True{}:
      matches(walk(depth, Bool.pick(U32, binding, 178, 166), config, Level{leaves, given, []}), root)

def check(+depth: Nat, binding: Bool, +config: Tree.Digest, +leaves: Nodes, given: Siblings, root: Tree.Digest) -> Bool:
  no_start = digest_equal(config, Tree.Digest{0,0,0,0,0,0,0,0})
  checked(Nat.is_le(depth, 48n) && ordered(leaves) && Bool.not(no_start), depth, binding, config, leaves, given, root)
