import Base
import ../src/transcript.bend as T
import ../src/hash_bytes.bend as H
import ../src/chain.bend as Bits
import ../src/extension.bend as Ext

# Field-2 six-round trace in the pinned docs/format/format-vectors.txt, R4-R6.
def params() -> H.Bytes:
  [245,64,196,106,219,159,37,70,45,176,164,41,53,102,51,4,208,102,183,138,146,191,196,218,157,63,170,89,44,237,168,241]
def statement() -> H.Bytes:
  [10,0,0,0,0,0,0,0,116,111,121,58,32,99,108,97,105,109,24,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,9,0,0,0,0,0,0,0,116,111,121,58,32,110,97,109,101,11,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,97,98,99]

def pattern(count: Nat, +at: Nat, +a: Nat, +b: Nat) -> H.Bytes:
  match count:
    case 0n: []
    case 1n+p:
      U32.from_nat(Nat.mod(Nat.add(Nat.mul(at,a),b),251n)) <> pattern(p,Nat.add(at,1n),a,b)

def state(r: T.Round) -> T.State:
  T.Round{s,_} = r
  s

def stream(r: T.Round) -> T.Stream:
  T.Round{_,s} = r
  s

def show_state(s: T.State) -> IO(Unit):
  T.State{_,_,rho} = s
  IO.print(H.hex(rho))

def require_start(s: Maybe<&2,T.Start>) -> IO(T.State):
  match s:
    case Some{T.Start{+st,Some{run}}}:
      do IO<T.State>:
        IO.print(H.hex(run))
        show_state(st)
        return st
    case _: IO.die(T.State,1,"start failed")

def require_round(v: Maybe<&2,T.Round>) -> IO(T.Round):
  match v:
    case Some{+r}:
      do IO<T.Round>:
        show_state(state(r))
        return r
    case None{}: IO.die(T.Round,1,"round failed")

def failed(v: Maybe<&2,T.Round>) -> String:
  match v:
    case Some{_}: "accepted"
    case None{}: "rejected"

def e_wire(e: Ext.E3) -> H.Bytes:
  Ext.E3{ah,al,bh,bl,ch,cl} = e
  H.cat([H.le(al),H.le(ah),H.le(bl),H.le(bh),H.le(cl),H.le(ch)])

def show_e(v: T.Read<Ext.E3>) -> IO(Unit):
  IO.print(H.hex(e_wire(T.value(Ext.E3,v))))

def positions(xs: List<&2,Nat>) -> String:
  match xs:
    case []: ""
    case x <> []: Nat.show(x)
    case x <> y <> tail: Nat.show(x) ++ " " ++ positions(y <> tail)

def show_positions(+r: T.Round) -> IO(Unit):
  +xs = T.draws(5n,10n,stream(r))
  do IO<Unit>:
    IO.print(positions(T.value(List<&2,Nat>,xs)))
    show_e(T.element(T.after(List<&2,Nat>,xs)))

def show_seed(r: T.Round) -> IO(Unit):
  +p = T.element(stream(r))
  +q = T.element(T.after(Ext.E3,p))
  f = T.nonzero(T.after(Ext.E3,q))
  do IO<Unit>:
    show_e(p)
    show_e(q)
    show_e(f)

def sign(w: U32) -> String:
  match w:
    case 0: "0"
    case 1: "+"
    case 4294967295: "-"
    case _: "?"

def signs(ws: H.Bytes) -> String:
  match ws:
    case []: ""
    case w <> tail: sign(w) ++ signs(tail)

def main() -> IO(Unit):
  +z: Bits.Bits64 = Bits.Bits64{0,0}
  m1 = H.cat([H.word(4),H.word(5),H.word(6),H.word(7),H.word(8),H.word(9)])
  m2 = H.cat([H.word(1),H.word(1),H.word(1)])
  +m3 = pattern(32n,0n,11n,2n)
  m5 = H.cat([H.word(9),H.word(9),H.word(9)])
  do IO<Unit>:
    s : T.State <- require_start(T.begin(7n,params(),statement(),Some{pattern(32n,0n,5n,1n)}))
    +r1 : T.Round <- require_round(T.close(s,1,0,z,48n,m1))
    show_e(T.element(stream(r1)))
    +r2 : T.Round <- require_round(T.close(state(r1),7,0,z,24n,m2))
    IO.print(failed(T.close(state(r2),4,8,Bits.Bits64{0,115},32n,m3)))
    IO.print(failed(T.close(state(r2),4,8,Bits.Bits64{0,116},24n,m3)))
    IO.print(failed(T.close(state(r2),6,8,Bits.Bits64{0,116},32n,m3)))
    IO.print(failed(T.close(state(r2),7,0,Bits.Bits64{0,1},32n,m3)))
    +r3 : T.Round <- require_round(T.close(state(r2),4,8,Bits.Bits64{0,116},32n,m3))
    show_positions(r3)
    +r4 : T.Round <- require_round(T.close(state(r3),3,0,z,0n,[]))
    show_seed(r4)
    +r5 : T.Round <- require_round(T.close(state(r4),5,0,z,24n,m5))
    IO.print(signs(T.value(H.Bytes,T.trits(40n,stream(r5)))))
    r6 : T.Round <- require_round(T.close(state(r5),6,0,z,8n,H.word(77)))
    IO.print(H.hex(T.seal(stream(r6))))

#|700cd5f8c6809036bab546f63e6fd0de6846695ee9772955436353db91d45986
#|9a4c85fc23558196c3ee866b926a660f13af5df9a757f1483fcf0bb70aa3fe72
#|3c98919bc70e2dca17b612fdf29be0f6b6f26efcdc04e845a11038260a5861fd
#|622e49d2f47ffc3f9733f94b0937ba3de4601433b322e9b3
#|ed50d6b77518037aa4dfcfd7bae987e6761391c089e349575d6ccac53aa3556f
#|rejected
#|rejected
#|rejected
#|rejected
#|28d010de3f0b0b8da2ccdd36f9c476eb062e1e416389eb81f6a4eb0c60268495
#|69 895 454 526 842
#|2906eda77d19bc153eba9b8e8b0cea51d795a2de0b932f54
#|ad311297fb7c851c0561be363deb88aede14295352d4fcf8f478ed607c8ca10a
#|75a4215ec380248e0f12add26a6b54c3cfb46fd77a1434ac
#|f25c7a23355e0b328eb1bdf196c8b9e613009ff2d1b3f7fc
#|dca9152a98bba1a9eac189ff3e87659f25731916879eef62
#|1377c2217a2329b555a3bc638f2d842dfd01f57cf089aca2cea169d21e70fead
#|0+00--00-+-000++00-++0+---+0+--0000+0-0+
#|70b365d8f0bda8f239fa4a9417b2ddddf69a25197785dd096c937c5d05064dad
#|0b5ec9235d31cb34c68dd2f4f50a59b3b0fd28c246389e8f59cd0350416cfdd6
