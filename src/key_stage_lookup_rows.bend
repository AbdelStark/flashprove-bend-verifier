import Base
import ./base_check.bend as B
import ./extension.bend as E
import ./sumcheck.bend as A
import ./fold.bend as F
import ./hash_bytes.bend as H
import ./transcript.bend as T
import ./key_stage_psc.bend as PSC
import ./key_stage_openings.bend as K
import ./header.bend as Header

# A slot is its ordinal among the free entries of the named oracle. The row
# layout converts that ordinal to a physical row and entry (R13.8).
type Oracle is Data:
  Multiplicities{}
  IndexMask{}
type Mask is Data:
  Mask{oracle: Oracle, slot: Nat, coefficient: E.E3}
def Masks() -> Data: List<&2,Mask>

type Point is Data:
  Point{at: B.Elements, masks: Masks, value: E.E3}

type Plane is Data:
  Plane{lookup: Nat, term: F.Term}

type Row is Data:
  Row{planes: List<&2,Plane>, masks: Masks, target: E.E3}

type AlgebraRound is Data:
  AlgebraRound{name: String, values: B.Elements, draws: B.Elements}
def Events() -> Data: List<&2,AlgebraRound>

def challenges(n: Nat, stream: T.Stream) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k:
      +v = T.element(stream)
      T.value(E.E3,v) <> challenges(k,T.after(E.E3,v))

def event(name: String, message: H.Bytes, stream: T.Stream, n: U32, nz: U32) -> AlgebraRound:
  +zero = U32.is_zero(nz)
  +input = stream
  vals = B.elements(H.u32s(message),[])
  ds = Bool.pick(B.Elements,zero,challenges(U32.to_nat(n),input),[T.value(E.E3,T.nonzero(input))])
  AlgebraRound{name,vals,ds}

type Tape is Data:
  Tape{events: Events, multiplicity: Nat, index: Nat, rows: List<&2,Row>}
type Read is Data:
  Read{message: B.Elements, draws: B.Elements, tape: Tape}

def take(tape: Tape, expected: String) -> IO(Read):
  match tape:
    case Tape{AlgebraRound{n,m,d} <> tail,a,b,rows}:
      do IO<Read>:
        ok : Unit <- Header.require(String.eq(n,expected),"NO: key-lookup-round")
        return Read{m,d,Tape{tail,a,b,rows}}
    case _: IO.die(Read,1,"NO: short-key-lookup")

def scaled(+mode: U32, terms: Masks, +s: E.E3) -> Masks:
  match terms:
    case []: []
    case Mask{o,i,w} <> tail: Mask{o,i,A.by(mode,s,w)} <> scaled(mode,tail,s)

def scale(terms: Masks, +s: E.E3) -> Masks: scaled(A.unit(s),terms,s)

def next(slots: B.Elements, +oracle: Oracle, at: Nat) -> Masks:
  match slots:
    case []: []
    case w <> tail:
      +i = at
      Mask{oracle,i,w} <> next(tail,oracle,1n+i)

def keep(tape: Tape, row: Row) -> Tape:
  Tape{events,a,b,rows} = tape
  Tape{events,a,b,row <> rows}

def sum(xs: Masks, ys: Masks) -> Masks:
  List.append(&2,Mask,xs,ys)

type RowsOut is Data:
  RowsOut{row: Row, ends: List<&2,Point>, point: B.Elements, tape: Tape}

def points(values: B.Elements, +at: B.Elements, +oracle: Oracle, i: Nat, +beta: E.E3) -> List<&2,Point>:
  match values:
    case []: []
    case v <> tail:
      +slot = i
      Point{at,[Mask{oracle,slot,beta}],v} <> points(tail,at,oracle,1n+slot,beta)

type State is Data:
  State{claim: PSC.Claim, point_rev: B.Elements, tape: Tape}

def started(r: Read, target: E.E3) -> IO(State):
  match r:
    case Read{[hiding],[eps],t}: IO.pure(State,State{PSC.begin(hiding,eps,target),[],t})
    case _: IO.die(State,1,"NO: key-lookup-epsilon")

def begin(t: Tape, target: E.E3) -> IO(State):
  do IO<State>:
    r : Read <- take(t,"PSC epsilon")
    started(r,target)

def bound(r: Read, variable: PSC.Variable, claim: PSC.Claim, rev: B.Elements) -> IO(State):
  match r:
    case Read{coeff,[+g],t}:
      do IO<State>:
        next : PSC.Claim <- K.need(PSC.Claim,PSC.bind(claim,variable,coeff,g),"NO: key-lookup-polynomial")
        return State{next,g <> rev,t}
    case _: IO.die(State,1,"NO: key-lookup-challenge")

def bind(state: State, name: String, variable: PSC.Variable) -> IO(State):
  State{claim,rev,tape} = state
  do IO<State>:
    r : Read <- take(tape,name)
    bound(r,variable,claim,rev)

def rounds(vars: List<&2,PSC.Variable>, state: State) -> IO(State):
  match vars:
    case []: IO.pure(State,state)
    case x <> tail:
      do IO<State>:
        n : State <- bind(state,"PSC round",x)
        rounds(tail,n)

type Sum is Data:
  Prod{}
  FirstTie{factor: E.E3}
  NextTie{}
  Bits{}

def evaluated(kind: Sum, y: B.Elements) -> IO(E.E3):
  match kind y:
    case Prod{} Con{a,Con{b,Nil{}}}: IO.pure(E.E3,A.mul(a,b))
    case FirstTie{factor} Con{z,Con{+p,Con{g,Nil{}}}}: IO.pure(E.E3,F.sub(z,A.mul(factor,A.mul(A.mul(p,p),g))))
    case NextTie{} Con{+p,Con{g,Nil{}}}: IO.pure(E.E3,A.mul(A.mul(p,p),g))
    case Bits{} Con{+x,Nil{}}: IO.pure(E.E3,F.sub(A.mul(x,x),x))
    case _ _: IO.die(E.E3,1,"NO: key-lookup-end-values")

def degree(kind: Sum) -> Nat:
  match kind:
    case Prod{}: 2n
    case Bits{}: 2n
    case _: 3n

def assemble(row: PSC.Obligation, +y: B.Elements, +at: B.Elements, beta: E.E3, previous: Masks,
  tape: Tape, +own: Bool) -> RowsOut:
  PSC.Obligation{target,+fresh,carry,_} = row
  Tape{events,+m,+i,rows} = tape
  +n = Nat.add(m,List.length(&2,E.E3,fresh))
  +c = List.length(&2,E.E3,y)
  slot = Bool.pick(Nat,own,i,n)
  who = Bool.pick(Oracle,own,IndexMask{},Multiplicities{})
  masks = sum(next(fresh,Multiplicities{},m),scale(previous,carry))
  final: Tape = Tape{events,Bool.pick(Nat,own,n,Nat.add(n,c)),Bool.pick(Nat,own,Nat.add(i,c),i),rows}
  RowsOut{Row{[],masks,target},points(y,at,who,slot,beta),at,final}

def ends(read: Read, kind: Sum, claim: PSC.Claim, rev: B.Elements, previous: Masks, own: Bool) -> IO(RowsOut):
  match read rev:
    case Read{+vals,[],t} Con{beta,xs}:
      do IO<RowsOut>:
        constant : E.E3 <- evaluated(kind,vals)
        return assemble(PSC.obligation(claim,constant,[]),vals,List.reverse(&2,E.E3,xs),beta,previous,t,own)
    case _ _: IO.die(RowsOut,1,"NO: key-lookup-end-round")

def opened(s: State, kind: Sum, prev: Masks, own: Bool) -> IO(RowsOut):
  State{claim,rev,t} = s
  do IO<RowsOut>:
    got : Read <- take(t,"PSC values")
    ends(got,kind,claim,rev,prev,own)

def shown(t: Tape, incoming: Point, vars: List<&2,PSC.Variable>, +kind: Sum, index_ends: Bool) -> IO(RowsOut):
  Point{_,masks,target} = incoming
  do IO<RowsOut>:
    s : State <- begin(t,target)
    x : State <- rounds(vars,s)
    y : State <- bind(x,"PSC Y",PSC.Variable{PSC.Equal{F.zero()},degree(kind)})
    opened(y,kind,masks,index_ends)
