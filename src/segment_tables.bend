import Base
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F
import ./hash_bytes.bend as H
import ./policy_tables.bend as T
import ./key_stage_lookup.bend as KL

# R11.2–11.4 table encodings at the four released configurations.
type TableKind is Data:
  Range{}
  Clamp{}
  Gate{}
  Sigmoid{}
  HeadExp{}
  KernelRange{step: Nat}
  Window{}
  KernelExp{step: Nat}

type Call is Data:
  Call{kind: TableKind, bits: Nat, first: Nat, iota: Nat, pad_value: Nat, pads: Nat}

type Forest is Data:
  Forest{key_bits: Nat, table_bits: Nat, tree_bits: Nat, call_bits: Nat, calls: List<&2,Call>}

def table_data(kind: TableKind, tables: T.Tables) -> H.Bytes:
  match kind tables:
    case Gate{} T.Tables{T.Table{w,_},_,_,_}: w
    case Sigmoid{} T.Tables{_,T.Table{w,_},_,_}: w
    case KernelExp{_} T.Tables{_,_,_,T.Table{w,_}}: w
    case _ _: []

type Scalar is Data:
  Scalar{value: Nat, rest: H.Bytes}

def row_words(i: Nat, +shift: Nat, +flag: Nat, data: H.Bytes) -> Scalar:
  match data:
    case w <> tail: Scalar{Nat.add(i,Nat.add(flag,Nat.mul(shift,U32.to_nat(w)))),tail}
    case []: Scalar{0n,[]}

# The packed integer remains below 2^48 under these profiles. R11.4's
# EX recurrence has G0=2^41 and N=484. Its rounded outputs are 2^24, 2, 1, 1, ...
def row(kind: TableKind, +i: Nat, +words: H.Bytes) -> Scalar:
  match kind:
    case Range{}: Scalar{i,words}
    case Clamp{}:
      v = Nat.min(4095n,Nat.add(1n,Nat.sub(i,30721n)))
      Scalar{Nat.add(i,Nat.mul(v,268435456n)),words}
    case Gate{}: row_words(i,268435456n,0n,words)
    case Sigmoid{}:
      +upper = Nat.is_ge(i,32768n)
      row_words(i,Bool.pick(Nat,upper,268435456n,131072n),Bool.pick(Nat,upper,Nat.pow(2n,40n),0n),words)
    case HeadExp{}:
      v = Bool.pick(Nat,Nat.is_eq(i,0n),16777216n,Bool.pick(Nat,Nat.is_eq(i,1n),2n,1n))
      Scalar{Nat.add(i,Nat.mul(65536n,v)),words}
    case Window{}: Scalar{Nat.add(Nat.mod(i,256n),Nat.mul(Nat.div(i,256n),1048576n)),words}
    case KernelRange{lim}:
      v = Nat.add(Nat.mod(i,256n),Nat.mul(Nat.div(i,256n),1048576n))
      Scalar{Nat.add(v,Bool.pick(Nat,Nat.is_ge(i,lim),Nat.pow(2n,40n),0n)),words}
    case KernelExp{+step}:
      # Texp holds u0=2307 words. rho, C and the coarse-bin count are public.
      +rho = Nat.sub(65536n,step)
      +bins = Nat.div(Nat.add(2145387009n,Nat.sub(rho,1n)),rho)
      +j = Nat.sub(i,2307n)
      +high = Nat.is_ge(j,bins)
      coarse = Nat.add(Nat.pow(2n,32n),Nat.add(Nat.mul(2306n,step),
        Nat.add(Nat.mul(rho,Bool.pick(Nat,high,Nat.sub(j,bins),j)),Bool.pick(Nat,high,Nat.div(rho,2n),0n))))
      action = Bool.pick(Unit -> Scalar,Nat.is_lt(i,2307n),
        _ => row_words(Nat.mul(i,step),Nat.pow(2n,33n),0n,words), _ => Scalar{coarse,words})
      action(Unit{})

type Value is Data:
  Value{v: X.E3, remaining: H.Bytes}

def leaf(s: Scalar) -> Value:
  Scalar{v,tail} = s
  Value{KL.small(v),tail}

def number(v: Value) -> X.E3:
  Value{n,_} = v
  n

def remaining(v: Value) -> H.Bytes:
  Value{_,w} = v
  w

def dense(high_first: B.Elements, +k: TableKind, i: Nat, words: H.Bytes) -> Value:
  match high_first:
    case []: leaf(row(k,i,words))
    case +g <> +rest:
      +keep = i
      +n = Nat.add(keep,keep)
      +left = dense(rest,k,n,words)
      +right = dense(rest,k,1n+n,remaining(left))
      Value{F.mix(number(left),number(right),g),remaining(right)}

def value(+k: TableKind, +low_first: B.Elements, tables: T.Tables) -> X.E3:
  match k:
    case Range{}: KL.index(low_first,F.one(),F.zero())
    case +packed:
      number(dense(List.reverse(&2,X.E3,low_first),packed,0n,table_data(packed,tables)))
