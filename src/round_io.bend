import Base
import ./hash_bytes.bend as H
import ./wire_reader.bend as R
import ./chain.bend as Bits
import ./header.bend as Header
import ./commitment.bend as Commitment
import ./plan.bend as Plan
import ./transcript.bend as T

type Step is Data:
  Step{message: H.Bytes, state: T.State, stream: T.Stream}

# R5.3, R12.8, R13.11. The RECORD entry belongs to a separate seed chain.
def kind(name: String) -> U32:
  match name:
    case "LKP": 1
    case "LKP shift": 1
    case "JOIN": 1
    case "LINE": 1
    case "ZERO": 1
    case "BAT": 1
    case "BAT-sigma": 1
    case "PSC round": 1
    case "PSC Y": 1
    case "FOLD round": 1
    case "BASE lambda": 1
    case "LIN point": 1
    case "LIN zeta": 1
    case "LINK point": 1
    case "LINK phi": 1
    case "PSC epsilon": 2
    case "FOLD epsilon": 2
    case "SEND seed": 3
    case "CS": 4
    case "LOC": 4
    case "LINK": 4
    case "BASE": 4
    case "RNG": 5
    case "SEAL": 6
    case "REPLY": 7
    case "SPLIT": 7
    case "PSC values": 7
    case "SEND answer": 7
    case _: 0

def accepted(round: Maybe<&2, T.Round>, reader: R.Reader, message: H.Bytes) -> IO(R.Reader & Step):
  match round:
    case Some{T.Round{state, stream}}: IO.pure(R.Reader & Step, (reader, Step{message,state,stream}))
    case None{}: IO.die(R.Reader & Step, 1, "NO: chain-round")

def with_nonce(value: H.Bytes, reader: R.Reader, +message: H.Bytes, state: T.State,
  kind: U32, work: U32, size: U32) -> IO(R.Reader & Step):
  match value:
    case [lo,hi]:
      accepted(T.close(state,kind,work,Bits.Bits64{hi,lo},U32.to_nat(size),message), reader, message)
    case _: IO.die(R.Reader & Step, 1, "NO: chain-nonce")

def nonce_read(pair: R.Reader & H.Bytes, message: H.Bytes, state: T.State,
  kind: U32, work: U32, size: U32) -> IO(R.Reader & Step):
  (r, b) = pair
  with_nonce(H.u32s(b),r,message,state,kind,work,size)

def nonce(work: U32, r: R.Reader, +message: H.Bytes, state: T.State,
  kind: U32, size: U32) -> IO(R.Reader & Step):
  match work:
    case 0: accepted(T.close(state,kind,0,Bits.Bits64{0,0},U32.to_nat(size),message), r, message)
    case +bits:
      do IO<R.Reader & Step>:
        raw : R.Reader & H.Bytes <- R.take(r, 8)
        nonce_read(raw,message,state,kind,bits,size)

def message_read(pair: R.Reader & H.Bytes, state: T.State, tag: U32, size: U32,
  work: U32, roots: U32) -> IO(R.Reader & Step):
  (r, +message) = pair
  fields = List.drop(&2,U32,message,Nat.mul(32n,U32.to_nat(roots)))
  do IO<R.Reader & Step>:
    ok : Unit <- Header.require(Commitment.canonical(H.u32s(fields)), "NO: noncanonical-element")
    nonce(work,r,message,state,tag,size)

def advance(r: R.Reader, state: T.State, round: Plan.Round) -> IO(R.Reader & Step):
  Plan.Round{name,_,work,+size,+roots,_,_,_,_,_,_,_} = round
  +tag = kind(name)
  do IO<R.Reader & Step>:
    ok : Unit <- Header.require(U32.is_ne(tag,0) && U32.is_zero(U32.and(size,7)) &&
      U32.is_le(roots,U32.shrn(size,5n)), "NO: round-plan")
    raw : R.Reader & H.Bytes <- R.take(r,size)
    message_read(raw,state,tag,size,work,roots)
