import Base
import ./key_stage_lookup_rows.bend as L
import ./key_stage_psc.bend as P
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F
import ./hash_bytes.bend as H
import ./key_stage_openings.bend as K
import ./row_tensor.bend as Tensor

type Pairing is Data:
  Pairing{point: L.Point, tape: L.Tape}

def member(xs: H.Bytes, +k: U32) -> Bool:
  match xs:
    case []: False{}
    case i <> tail: U32.is_eq(i,k) || member(tail,k)

def descending(n: Nat, +skip: H.Bytes) -> H.Bytes:
  match n:
    case 0n: []
    case 1n+k:
      +next = k
      +i = U32.from_nat(next)
      +tail = descending(next,skip)
      Bool.pick(H.Bytes,member(skip,i),tail,i <> tail)

def order(n: Nat, +first: H.Bytes) -> H.Bytes:
  H.cat([first,descending(n,first)])

def equals(order: H.Bytes, +point: B.Elements, +degree: Nat) -> IO(List<&2,P.Variable>):
  match order:
    case []: IO.pure(List<&2,P.Variable>,[])
    case n <> tail:
      do IO<List<&2,P.Variable>>:
        z : X.E3 <- K.need(X.E3,List.get(&2,X.E3,point,U32.to_nat(n)),"NO: key-lookup-coordinate")
        rest : List<&2,P.Variable> <- equals(tail,point,degree)
        return P.Variable{P.Equal{z},degree} <> rest

def undo(order: H.Bytes, rounds: B.Elements, point: B.Elements) -> B.Elements:
  match order rounds:
    case Con{i,rest} Con{g,tail}: undo(rest,tail,List.set(&2,X.E3,point,U32.to_nat(i),g))
    case _ _: point

def restore(+order: H.Bytes, rounds: B.Elements) -> B.Elements:
  undo(order,rounds,List.replicate(X.E3,H.length(order),F.zero()))

def joined(draw: L.Read, z: B.Elements, a: L.Masks, b: L.Masks, x: X.E3, y: X.E3) -> IO(Pairing):
  match draw:
    case L.Read{[],[+rho],t}:
      ms = L.sum(L.scale(a,F.sub(F.one(),rho)),L.scale(b,rho))
      point = List.append(&2,X.E3,z,[rho])
      IO.pure(Pairing,Pairing{L.Point{point,ms,F.mix(x,y,rho)},t})
    case _: IO.die(Pairing,1,"NO: key-lookup-line")

def line(result: L.RowsOut, order: H.Bytes) -> IO(Pairing):
  match result:
    case L.RowsOut{row,[L.Point{_,ms,x},L.Point{_,ns,y}],z,t}:
      do IO<Pairing>:
        d : L.Read <- L.take(L.keep(t,row),"LINE")
        joined(d,restore(order,z),ms,ns,x,y)
    case _: IO.die(Pairing,1,"NO: key-lookup-halves")

def level(pair: Pairing, +order: H.Bytes, index_ends: Bool) -> IO(Pairing):
  Pairing{+point,t} = pair
  L.Point{z,_,_} = point
  do IO<Pairing>:
    vars : List<&2,P.Variable> <- equals(order,z,2n)
    out : L.RowsOut <- L.shown(t,point,vars,L.Prod{},index_ends)
    line(out,order)

def chain(n: Nat, v: Nat, +last_order: H.Bytes, +own: Bool, pair: Pairing) -> IO(Pairing):
  match n:
    case 0n: IO.pure(Pairing,pair)
    case 1n+k:
      +left = k
      +last = Nat.is_eq(left,0n)
      +size = v
      do IO<Pairing>:
        next : Pairing <- level(pair,order(size,Bool.pick(H.Bytes,last,last_order,[])),own && last)
        chain(left,1n+size,last_order,own,next)

type Roots is Data:
  Roots{root: L.Point, planes: List<&2,L.Point>, tape: L.Tape}

def next_plane(out: L.RowsOut, old: Roots) -> IO(Roots):
  match out old:
    case L.RowsOut{row,Con{power,Con{plane,Nil{}}},_,t} Roots{root,Con{_,others},_}:
      IO.pure(Roots,Roots{root,power <> plane <> others,L.keep(t,row)})
    case _ _: IO.die(Roots,1,"NO: key-lookup-tie")

def ties(n: Nat, +current: Roots) -> IO(Roots):
  match n:
    case 0n: IO.pure(Roots,current)
    case 1n+k:
      Roots{_,planes,t} = current
      do IO<Roots>:
        prev : L.Point <- K.need(L.Point,List.head(&2,L.Point,planes),"NO: key-lookup-power")
        out : L.RowsOut <- L.shown(t,prev,[],L.NextTie{},False{})
        next : Roots <- next_plane(out,current)
        ties(k,next)

def first(out: L.RowsOut, live: Nat) -> IO(Roots):
  match out:
    case L.RowsOut{row,[r,p,g],_,t}:
      ties(Nat.sub(live,2n),Roots{r,[p,g],L.keep(t,row)})
    case _: IO.die(Roots,1,"NO: key-lookup-first-tie")

type Split is Data:
  Split{roots: List<&2,L.Point>, tape: L.Tape}

def halves(out: L.RowsOut, acc: List<&2,L.Point>) -> IO(Split):
  match out:
    case L.RowsOut{row,[left,right],_,t}: IO.pure(Split,Split{right <> left <> acc,L.keep(t,row)})
    case _: IO.die(Split,1,"NO: key-lookup-split")

def split(n: Nat, pair: Split) -> IO(Split):
  match n pair:
    case 0n Split{xs,t}: IO.pure(Split,Split{List.reverse(&2,L.Point,xs),t})
    case 1n+k Split{root <> acc,t}:
      do IO<Split>:
        out : L.RowsOut <- L.shown(t,root,[],L.Prod{},False{})
        next : Split <- halves(out,acc)
        split(k,next)
    case _ _: IO.die(Split,1,"NO: key-lookup-parts")

# Dead planes are committed zero, so their product trees contain the public
# constant one. Start at one and add eq(j,gamma) * (root[j]-1) for live planes.
def join(planes: List<&2,L.Point>, +factors: F.Factors, i: Nat, masks: L.Masks, total: X.E3, point: B.Elements) -> L.Point:
  match planes:
    case []: L.Point{point,masks,total}
    case L.Point{_,terms,v} <> rest:
      +j = i
      +w = Tensor.entry(factors,j,F.one())
      join(rest,factors,1n+j,L.sum(L.scale(terms,w),masks),E.add(total,E.mul(w,F.sub(v,F.one()))),point)
