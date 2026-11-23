import Base
import ./segment_attention_aff.bend as A
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./extension.bend as X
import ./fold.bend as F
import ./oracle_sample.bend as S
import ./segment_tables.bend as Forest
import ./policy.bend as P
import ./policy_statement.bend as St
import ./header.bend as Header

# Dimensions come from the checked caller configuration. These published
# profiles use the four listed calls with one shift and a single score matrix.
type Shape is Data:
  Shape{lt: Nat, lb: Nat, lg: Nat, ld: Nat, la: Nat, lm: Nat, mb: Nat, heads: Nat, layers: Nat, ah: Nat, ao: Nat, qa: Nat}

def group(s: Shape) -> Nat:
  Shape{_,_,g,_,_,_,_,_,_,_,_,_} = s
  A.size(g)
def lt(s: Shape) -> Nat:
  Shape{n,_,_,_,_,_,_,_,_,_,_,_} = s
  n
def lb(s: Shape) -> Nat:
  Shape{_,n,_,_,_,_,_,_,_,_,_,_} = s
  n
def lg(s: Shape) -> Nat:
  Shape{_,_,n,_,_,_,_,_,_,_,_,_} = s
  n
def ld(s: Shape) -> Nat:
  Shape{_,_,_,n,_,_,_,_,_,_,_,_} = s
  n
def la(s: Shape) -> Nat:
  Shape{_,_,_,_,n,_,_,_,_,_,_,_} = s
  n
def lm(s: Shape) -> Nat:
  Shape{_,_,_,_,_,n,_,_,_,_,_,_} = s
  n
def mb(s: Shape) -> Nat:
  Shape{_,_,_,_,_,_,n,_,_,_,_,_} = s
  n
def heads(s: Shape) -> Nat:
  Shape{_,_,_,_,_,_,_,n,_,_,_,_} = s
  n
def layers(s: Shape) -> Nat:
  Shape{_,_,_,_,_,_,_,_,n,_,_,_} = s
  n
def ha(+s: Shape) -> Nat: Nat.div(heads(s),group(s))
def pairs(+s: Shape) -> Nat: Nat.mul(layers(s),ha(s))
def tiles(+s: Shape) -> Nat: Nat.sub(lt(s),lb(s))
def lanes(+s: Shape) -> Nat: Nat.sub(la(s),lt(s))
def main_region(+s: Shape) -> Nat: Nat.sub(Nat.add(Nat.add(lg(s),lt(s)),lt(s)),1n)
def diagonal(+s: Shape) -> Nat: Nat.add(Nat.add(lg(s),lt(s)),lb(s))
def ns(s: Shape, d: Bool) -> Nat:
  +shape = s
  Bool.pick(Nat,d,diagonal(shape),main_region(shape))

def rounded(n: Nat, +unit: Nat) -> Nat: Nat.mul(Nat.div(Nat.add(n,Nat.sub(unit,1n)),unit),unit)
def score_width(+s: Shape) -> Nat:
  Nat.div(rounded(Nat.mul(Nat.mul(5n,pairs(s)),Nat.add(A.size(main_region(s)),A.size(diagonal(s)))),A.size(lm(s))),A.size(lm(s)))
def h_width(+s: Shape) -> Nat:
  Shape{_,_,_,_,_,_,_,_,_,w,_,_} = s
  rounded(Nat.mul(Nat.mul(Nat.add(8n,lt(s)),layers(s)),heads(s)),A.size(Nat.sub(w,lt(s))))
def o_width(+s: Shape) -> Nat:
  Shape{_,_,_,_,_,_,_,_,_,_,w,_} = s
  Nat.div(rounded(Nat.mul(Nat.mul(Nat.mul(2n,layers(s)),heads(s)),A.size(ld(s))),A.size(Nat.sub(w,lt(s)))),A.size(lanes(s)))
def q_width(+s: Shape) -> Nat:
  Shape{_,_,_,_,_,_,_,_,_,_,_,w} = s
  n = Nat.mul(Nat.mul(Nat.mul(4n,layers(s)),Nat.add(heads(s),group(s))),A.size(ld(s)))
  Nat.div(rounded(n,A.size(Nat.sub(w,lt(s)))),A.size(lanes(s)))
def b_width(s: Shape) -> Nat: Nat.mul(4n,A.size(Nat.sub(21n,mb(s))))
def length(+s: Shape) -> Nat: Nat.add(Nat.add(Nat.add(Nat.add(Nat.mul(3n,score_width(s)),Nat.mul(8n,h_width(s))),o_width(s)),Nat.mul(9n,q_width(s))),Nat.mul(3n,b_width(s)))

# Parts of U3 in file order. The H and Q tables are numbered in their own matrix.
def h(+s: Shape, i: Nat) -> Nat: Nat.add(Nat.mul(3n,score_width(s)),Nat.mul(i,h_width(s)))
def o(s: Shape) -> Nat: h(s,8n)
def q(+s: Shape, i: Nat) -> Nat: Nat.add(Nat.add(o(s),o_width(s)),Nat.mul(i,q_width(s)))
def bits(+s: Shape, i: Nat) -> Nat: Nat.add(q(s,9n),Nat.mul(i,b_width(s)))

def field(+lines: P.Lines, name: String) -> IO(Nat):
  do IO<Nat>:
    v : U32 <- P.field(lines,name)
    return U32.to_nat(v)

def shape(st: St.Statement) -> IO(Shape):
  St.Statement{_,_,_,_,_,_,_,+lines} = st
  do IO<Shape>:
    t : Nat <- field(lines,"lt")
    b : Nat <- field(lines,"lB")
    g : Nat <- field(lines,"G")
    d : Nat <- field(lines,"dh")
    a : Nat <- field(lines,"la")
    m : Nat <- field(lines,"lmS")
    bm : Nat <- field(lines,"lmbA")
    h : Nat <- field(lines,"H")
    l : Nat <- field(lines,"ll")
    ah : Nat <- field(lines,"lmh")
    ao : Nat <- field(lines,"lmo")
    qa : Nat <- field(lines,"lmq")
    return Shape{t,b,S.row_bits(g),S.row_bits(d),a,m,bm,h,A.size(l),ah,ao,qa}

type Unit_ is Data:
  Unit_{inner: B.Elements, weights: B.Elements, e: X.E3}

def tail(+xs: B.Elements,n: Nat) -> B.Elements: List.drop(&2,X.E3,xs,Nat.sub(List.length(&2,X.E3,xs),n))
def weight_loop(n: Nat, +first: Nat, +z: B.Elements, i: Nat, acc: B.Elements) -> B.Elements:
  match n:
    case 0n: A.rev(acc)
    case 1n+k:
      +b = i
      weight_loop(k,first,z,1n+b,A.eq(z,Nat.add(first,b)) <> acc)

# Each of the two score-region units and the two R16 units sorts by size before
# placement. WL precedes IX. All pairs in each unit are ordered by layer/head.
def unit_(point: B.Elements, d: Nat, c: Forest.Call, +width: Nat, start: Nat, n: Nat) -> Unit_:
  Forest.Call{_,_,first,+iota,_,_} = c
  +nc = Nat.add(d,iota)
  +z = point
  +zk = tail(z,nc)
  prefix = List.take(&2,X.E3,z,Nat.sub(List.length(&2,X.E3,z),nc))
  Unit_{tail(zk,width),weight_loop(n,Nat.div(start,A.size(width)),List.take(&2,X.E3,zk,Nat.sub(nc,width)),0n,[]),A.eq(prefix,Nat.div(first,A.size(iota)))}

def inner(u: Unit_) -> B.Elements:
  Unit_{z,_,_} = u
  z
def weights(u: Unit_) -> B.Elements:
  Unit_{_,w,_} = u
  w
def factor(u: Unit_) -> X.E3:
  Unit_{_,_,e} = u
  e

type Keys is Data:
  Keys{rm: Unit_, rd: Unit_, fm: Unit_, fd: Unit_, wl: Unit_, ix: Unit_, wh: Unit_, step: Nat, pad: Nat}

def call_step(c: Forest.Call) -> IO(Nat):
  match c:
    case Forest.Call{Forest.KernelRange{s},_,_,_,_,_}: IO.pure(Nat,s)
    case _: IO.die(Nat,1,"NO: attention-KR")
def call_pad(c: Forest.Call) -> IO(Nat):
  match c:
    case Forest.Call{Forest.KernelExp{_},_,_,_,pad,_}: IO.pure(Nat,pad)
    case _: IO.die(Nat,1,"NO: attention-KFD")

def keys(forest: Forest.Forest, +point: B.Elements, +s: Shape) -> IO(Keys):
  match forest:
    case Forest.Forest{+d,_,+rK,_,[+kr,+kf,+r,+w]}:
      # The shared forest stores zy and zx each low-first. A call's point uses
      # the remaining high-first zy prefix followed by high-first zx.
      +z = List.append(&2,X.E3,A.rev(List.take(&2,X.E3,point,rK)),A.rev(List.drop(&2,X.E3,point,rK)))
      +n = pairs(s)
      +m = main_region(s)
      +nd = diagonal(s)
      +big = Nat.mul(n,A.size(m))
      +base = Nat.add(lg(s),lt(s))
      +wide = Nat.add(base,ld(s))
      k = unit_(z,d,kf,m,0n,n)
      do IO<Keys>:
        step : Nat <- call_step(kr)
        pad : Nat <- call_pad(kf)
        return Keys{unit_(z,d,kr,m,0n,n),unit_(z,d,kr,nd,big,n),k,unit_(z,d,kf,nd,big,n),
          unit_(z,d,r,1n+wide,0n,n),unit_(z,d,r,base,Nat.mul(n,A.size(1n+wide)),n),unit_(z,d,w,wide,0n,n),step,pad}
    case _: IO.die(Keys,1,"NO: attention-lookup-layout")
