import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./segment_attention_shape.bend as S
import ./key_stage_trace.bend as Trace
import ./key_stage_lookup_rows.bend as L
import ./plan.bend as Plan
import ./base_check.bend as B
import ./extension.bend as X
import ./hash_bytes.bend as H
import ./header.bend as Header

# Round names and arities from R11.3. In these four profiles a call contains
# both score regions, with one common shift for every layer of a segment.
type Proof is Data:
  Proof{fm:P.Check,fd:P.Check,se:P.Check,vm:P.Check,vd:P.Check,zero:B.Elements,
    maxima:A.Values,sf:P.Check,sd:P.Check,hb:P.Check,gam:X.E3,om:X.E3,om4:X.E3,om5:X.E3,slots:Nat}

def declared(c: P.Coin) -> A.Values:
  P.Coin{v,_,_} = c
  v
def points(c: P.Coin) -> B.Elements:
  P.Coin{_,x,_} = c
  x
def next_coin(c: P.Coin) -> P.Cursor:
  P.Coin{_,_,c2} = c
  c2
def challenge(c: P.Coin) -> X.E3: A.get(points(c),0n)
def checked(r: P.Read) -> P.Check:
  P.Read{x,_} = r
  x
def next(r: P.Read) -> P.Cursor:
  P.Read{_,c} = r
  c
def used(r: P.Read) -> IO(Nat):
  match r:
    case P.Read{_,P.Cursor{[],s}}: IO.pure(Nat,s)
    case _: IO.die(Nat,1,"NO: attention-extra-rounds")

def parse(+s: S.Shape, c: P.Cursor) -> IO(Proof):
  +g = S.lg(s)
  +t = S.lt(s)
  +tile = S.tiles(s)
  +lo = S.lb(s)
  +ld = S.ld(s)
  +n = S.pairs(s)
  d = List.append(&2,Nat,List.replicate(Nat,t,2n),List.append(&2,Nat,List.replicate(Nat,g,Nat.add(2n,t)),List.replicate(Nat,t,Nat.add(1n,t))))
  +wide = Nat.sub(Nat.add(Nat.add(g,tile),tile),1n)
  do IO<Proof>:
    +km : P.Read <- P.sc3(c,13n,Nat.add(wide,ld),n)
    +kd : P.Read <- P.sc3(next(km),7n,Nat.add(Nat.add(g,tile),ld),n)
    +se : P.Read <- P.sc3(next(kd),Nat.add(7n,t),Nat.add(g,t),n)
    +gam : P.Coin <- P.coin(next(se),"BAT-sigma",0n,1n)
    +vm : P.Read <- P.sc3(next_coin(gam),2n,Nat.add(wide,lo),n)
    +vd : P.Read <- P.sc3(next(vm),0n,Nat.add(Nat.add(g,tile),lo),n)
    +z : P.Coin <- P.coin(next(vd),"ZERO",0n,Nat.add(Nat.add(Nat.mul(2n,g),Nat.mul(2n,t)),4n))
    +om : P.Coin <- P.coin(next_coin(z),"BAT-sigma",n,1n)
    +sf : P.Read <- P.sc3(next_coin(om),0n,Nat.add(Nat.add(t,g),ld),n)
    +o4 : P.Coin <- P.coin(next(sf),"BAT-sigma",0n,1n)
    +sd : P.Read <- P.parse(next_coin(o4),0n,d,Nat.add(1n,t),Nat.add(S.layers(s),Nat.mul(n,t)))
    +o5 : P.Coin <- P.coin(next(sd),"BAT-sigma",0n,1n)
    +hb : P.Read <- P.sc3(next_coin(o5),0n,Nat.add(Nat.add(t,g),4n),n)
    slot : Nat <- used(hb)
    return Proof{checked(km),checked(kd),checked(se),checked(vm),checked(vd),points(z),declared(om),checked(sf),checked(sd),checked(hb),
      challenge(gam),challenge(om),challenge(o4),challenge(o5),slot}

def scan(events: Trace.Events, +start: Nat, +acc: L.Events) -> IO(P.Cursor):
  match events:
    case Trace.Observed{Plan.Round{+name,_,_,_,_,_,n,nz,_,_,_,_},msg,st,_,_} <> tail:
      action = Bool.pick(Unit -> IO(P.Cursor),String.eq(name,"SEND seed"),
        _ => IO.pure(P.Cursor,P.Cursor{List.reverse(&2,L.AlgebraRound,acc),start}),
        _ => scan(tail,start,L.event(name,msg,st,n,nz) <> acc))
      action(Unit{})
    case _: IO.die(P.Cursor,1,"NO: attention-U3")

def first(events: Trace.Events, skip: Nat, slots: Nat) -> IO(P.Cursor):
  scan(List.drop(&2,Trace.Observed,events,skip),slots,[])
