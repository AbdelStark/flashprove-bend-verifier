import Base
import ../src/opening.bend as Opening
import ../src/merkle.bend as Tree

# Upstream format-vectors.txt, R7.x tree with two main rows. The draw stream
# [6,1,6,3] opens sorted positions [1,3,6]. Siblings are (3,0),(3,2),(3,7),(2,2).
def config() -> Tree.Digest:
  Tree.Digest{2164831719, 3142626686, 1752119359, 347161300, 3901988369, 2803117039, 126878167, 1608206419}

def root() -> Tree.Digest:
  Tree.Digest{1123753355, 2929749762, 3214280483, 763333275, 3097501950, 3382159946, 4252285765, 714174201}

def binding_root() -> Tree.Digest:
  Tree.Digest{3551938662, 1137761445, 2136761402, 72479615, 3002229333, 1723888373, 2926327287, 11727020}

def leaf0() -> Tree.Digest:
  Tree.Digest{1104375679, 2769312657, 1155086565, 1301741419, 756846103, 1938547263, 1982931823, 476241287}

def leaf1() -> Tree.Digest:
  Tree.Digest{3717183719, 177507222, 2061807732, 3505232675, 2161901192, 2101870905, 131879165, 2389550486}

def leaf2() -> Tree.Digest:
  Tree.Digest{3017337222, 2349544843, 3969536101, 2052197876, 3915384656, 877480432, 1535651454, 2780093875}

def leaf3() -> Tree.Digest:
  Tree.Digest{2467456721, 1269507712, 4281678167, 3083290167, 2544700650, 3452925756, 59699903, 3715311125}

def leaf4() -> Tree.Digest:
  Tree.Digest{3960309256, 4189937372, 4236765552, 2791171736, 3352000006, 2181153389, 3974809006, 2919765254}

def leaf5() -> Tree.Digest:
  Tree.Digest{2843702307, 1432220014, 4005403639, 752790433, 2269996002, 381752585, 1291029552, 772870725}

def leaf6() -> Tree.Digest:
  Tree.Digest{2401184372, 1595337131, 4113186688, 3269582158, 1386807223, 1758848546, 3553365387, 2393539305}

def leaf7() -> Tree.Digest:
  Tree.Digest{2752617233, 3392001202, 2686153424, 4206717541, 1355193043, 141335910, 1993176341, 1368183928}

def sub2() -> Tree.Digest:
  Tree.Digest{3254344480, 3416808931, 1125479793, 3700367489, 1583076490, 856219229, 322296128, 2618911053}

def last_place() -> Nat:
  Nat.add(Nat.mul(4294967295n, 65536n), 65535n)

def high_root() -> Tree.Digest:
  Tree.Digest{3705891777, 4093106752, 2932463118, 2500145827, 663443500, 2927891234, 2125083432, 1468902147}

# Vertex keys stay distinct across the 2^32 boundary and between depth and place.
def keys_distinct() -> Bool:
  +big = Nat.mul(65536n,65536n)
  Bool.not(String.eq(Opening.key(0n,big),Opening.key(0n,0n))) &&
    Bool.not(String.eq(Opening.key(1n,0n),Opening.key(0n,1n))) &&
    Bool.not(String.eq(Opening.key(48n,last_place()),Opening.key(48n,Nat.mod(last_place(),big)))) &&
    String.eq(Opening.key(48n,last_place()),Opening.key(48n,last_place()))

def copies(n: Nat) -> Opening.Siblings:
  match n:
    case 0n: []
    case 1n+p: leaf0() <> copies(p)

def check(depth: Nat, leaves: Opening.Nodes, given: Opening.Siblings, expected: Tree.Digest) -> String:
  Bool.show(Opening.check(depth, False{}, config(), leaves, given, expected))

def main() -> IO(Unit):
  +ls: Opening.Nodes = [Opening.Node{1n, leaf1()}, Opening.Node{3n, leaf3()}, Opening.Node{6n, leaf6()}]
  +gs: Opening.Siblings = [leaf0(), leaf2(), leaf7(), sub2()]
  +pair: Opening.Nodes = [Opening.Node{0n, leaf0()}, Opening.Node{1n, leaf1()}]
  do IO<Unit>:
    IO.print(check(3n, ls, gs, root()))
    IO.print(check(3n, ls, [leaf0(), leaf2(), leaf7()], root()))
    IO.print(check(3n, ls, [leaf0(), leaf2(), leaf7(), sub2(), sub2()], root()))
    IO.print(check(3n, ls, [leaf2(), leaf0(), leaf7(), sub2()], root()))
    IO.print(check(3n, ls, gs, leaf4()))
    IO.print(check(3n, [Opening.Node{3n,leaf3()}, Opening.Node{1n,leaf1()}, Opening.Node{6n,leaf6()}], gs, root()))
    IO.print(check(3n, [Opening.Node{1n,leaf1()}, Opening.Node{1n,leaf1()}], gs, root()))
    IO.print(check(0n, [Opening.Node{0n,root()}], [], root()))
    IO.print(check(0n, [Opening.Node{1n,root()}], [], root()))
    IO.print(check(0n, [], [], root()))
    IO.print(check(1n, pair, [], binding_root()))
    IO.print(Bool.show(Opening.check(1n, True{}, config(), pair, [], binding_root())))
    IO.print(check(3n, [Opening.Node{0n,leaf0()}, Opening.Node{1n,leaf1()}, Opening.Node{2n,leaf2()}, Opening.Node{3n,leaf3()}, Opening.Node{4n,leaf4()}, Opening.Node{5n,leaf5()}, Opening.Node{6n,leaf6()}, Opening.Node{7n,leaf7()}], [], root()))
    IO.print(check(48n, [Opening.Node{last_place(),leaf0()}], copies(48n), high_root()))
    IO.print(check(48n, [Opening.Node{Nat.sub(last_place(), 2n),leaf0()}], copies(48n), high_root()))
    IO.print(check(47n, [Opening.Node{last_place(),leaf0()}], copies(47n), high_root()))
    IO.print(check(49n, [Opening.Node{0n,root()}], [], root()))
    IO.print(Bool.show(Opening.check(0n, False{}, Tree.Digest{0,0,0,0,0,0,0,0}, [Opening.Node{0n,root()}], [], root())))
    IO.print(Bool.show(keys_distinct()))

#|True
#|False
#|False
#|False
#|False
#|False
#|False
#|True
#|False
#|False
#|False
#|True
#|True
#|True
#|False
#|False
#|False
#|False
#|True
