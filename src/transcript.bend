import Base
import ./chain.bend as Bits
import ./hash_bytes.bend as H
import ./hashlib.bend as Kernel
import ./extension.bend as Ext
import ./goldilocks.bend as Field
import ./pow2.bend as P2

# Bend 2.0.40 native Nat already restricts a chain label to 48 bits.
# Numeric words are (high, low); H's digest and message byte strings are in wire order.
def wire(word: Bits.Bits64) -> H.Bytes:
  Bits.Bits64{hi,lo} = word
  H.cat([H.le(lo), H.le(hi)])

def from_nat(+n: Nat) -> Bits.Bits64:
  Bits.Bits64{U32.from_nat(Nat.div(n, P2.pow2(32n))), U32.from_nat(n)}

def packed(tag: U32, +value: Nat) -> H.Bytes:
  H.cat([H.le(U32.or(tag, U32.shln(U32.from_nat(value), 16n))), H.le(U32.from_nat(Nat.div(value, 65536n)))])

type State is Data:
  State{label: Nat, round: Bits.Bits64, rho: H.Bytes}

type Start is Data:
  Start{state: State, run: Maybe<&2, H.Bytes>}

# R4.5-6. params is the checked 32-byte parameters digest; statement is the full encoding.
def run_suffix(run: Maybe<&2,H.Bytes>) -> H.Bytes:
  match run:
    case None{}: H.word(0)
    case Some{v}: H.cat([H.word(1), v])

def first_value(+label: Nat, body: H.Bytes, run: Maybe<&2,H.Bytes>, ok: Bool) -> Maybe<&2,Start>:
  match ok:
    case False{}: None{}
    case True{}:
      rho = H.digest(H.cat([H.word(160),wire(from_nat(label))]),H.zero(32n),body,32)
      Some{Start{State{label,Bits.Bits64{0,0},rho},run}}

def start_run(label: Nat, params: H.Bytes, +statement: H.Bytes, +run: Maybe<&2, H.Bytes>) -> Maybe<&2, Start>:
  +body = H.cat([params, wire(from_nat(H.length(statement))), statement, H.word(0), run_suffix(run)])
  first_value(label, body, run, Nat.is_le(H.length(body),4294967152n))

def randomized(label: Nat, params: H.Bytes, statement: H.Bytes, run: H.Bytes, all_zero: Bool) -> Maybe<&2,Start>:
  match all_zero:
    case True{}: None{}
    case False{}: start_run(label, params, statement, Some{run})

def with_random(+label: Nat, +params: H.Bytes, statement: H.Bytes, bytes: H.Bytes, correct_size: Bool) -> Maybe<&2,Start>:
  match correct_size:
    case False{}: None{}
    case True{}:
      +run = H.digest(H.cat([H.word(172),wire(from_nat(label))]),H.zero(32n),H.cat([params,bytes]),32)
      randomized(label,params,statement,run,List.all(&2,U32,x => U32.is_zero(x),run))

def begin_checked(label: Nat, params: H.Bytes, statement: H.Bytes, random: Maybe<&2,H.Bytes>, valid: Bool) -> Maybe<&2,Start>:
  match random valid:
    case _ False{}: None{}
    case None{} True{}: start_run(label,params,statement,None{})
    case Some{+bytes} True{}: with_random(label,params,statement,bytes,Nat.is_eq(H.length(bytes),32n))

def begin(+label: Nat, +params: H.Bytes, statement: H.Bytes, random: Maybe<&2,H.Bytes>) -> Maybe<&2,Start>:
  valid = Nat.is_eq(H.length(params),32n)
  begin_checked(label,params,statement,random,valid)

# Cache the message hash prefix for every subsequent round expansion (R2.6).
type Query is Data:
  Query{prefix: H.Context, meta: U32, nonce: Bits.Bits64}

def expand_state(query: Query, j: Nat) -> Kernel.H8:
  Query{prefix, meta, nonce} = query
  H.finish_state(H.update(prefix,H.cat([packed(meta,j),wire(nonce)])))

type Stream is Data:
  Stream{query: Query, next_call: Nat, words: List<&2,Bits.Bits64>}

type Round is Data:
  Round{state: State, draws: Stream}

def worked(label: Nat, round: Bits.Bits64, query: Query, block: H.Bytes, good: Bool) -> Maybe<&2,Round>:
  match good:
    case False{}: None{}
    case True{}:
      next: State = State{label,round,List.drop(&2,U32,block,32n)}
      Some{Round{next,Stream{query,1n,[]}}}

def tested(label: Nat, round: Bits.Bits64, work: U32, query: Query, state: Kernel.H8) -> Maybe<&2,Round>:
  Kernel.H8{+hi,+lo,a,b,c,d,e,f,g,h,i,j,k,l,m,n} = state
  bytes = H.output(Kernel.H8{hi,lo,a,b,c,d,e,f,g,h,i,j,k,l,m,n},64)
  worked(label,round,query,bytes,U32.is_ne(Bits.has_work(hi,lo,U32.to_nat(work)),0))

def unworked(label: Nat, round: Bits.Bits64, query: Query, state: Kernel.H8) -> Round:
  Kernel.H8{a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p} = state
  rho = H.cat([H.le(b),H.le(a),H.le(d),H.le(c),H.le(f),H.le(e),H.le(h),H.le(g)])
  Round{State{label,round,rho},Stream{query,1n,[Bits.Bits64{i,j},Bits.Bits64{k,l},Bits.Bits64{m,n},Bits.Bits64{o,p}]}}

def accept_query(label: Nat, round: Bits.Bits64, work: U32, query: Query, state: Kernel.H8) -> Maybe<&2,Round>:
  match work:
    case 0: Some{unworked(label,round,query,state)}
    case w: tested(label,round,w,query,state)

def close_checked(+label: Nat, +next: Bits.Bits64, rho: H.Bytes, kind: U32, +work: U32, nonce: Bits.Bits64, message: H.Bytes, good: Bool) -> Maybe<&2, Round>:
  match good:
    case False{}: None{}
    case True{}:
      label_bytes = H.cat([packed(162,label),wire(next)])
      prefix = H.update(H.Context{H.initial(H.u32s(rho),64),label_bytes,0},message)
      +q: Query = Query{prefix,U32.or(kind,U32.shln(work,8n)),nonce}
      accept_query(label,next,work,q,expand_state(q,0n))

# R5.2-7. kind, work and expected_bytes come from the verifier's checked plan.
def close(state: State, +kind: U32, +work: U32, +nonce: Bits.Bits64, +expected_bytes: Nat, +message: H.Bytes) -> Maybe<&2, Round>:
  State{+label, Bits.Bits64{+hi,+lo}, +rho} = state
  +next_lo = U32.add(lo,1)
  +next_hi = U32.add(hi, Bool.to_u32(U32.is_zero(next_lo)))
  good = U32.is_lt(next_hi,2147483648) &&
    U32.is_lt(hi,2147483648) && Nat.is_eq(H.length(rho),32n) &&
    U32.is_ge(kind,1) && U32.is_le(kind,7) && U32.is_le(work,64) &&
    (U32.is_zero(work) || U32.is_lt(kind,6)) && (U32.is_ne(work,0) || Bits.zero(nonce)) &&
    Nat.is_le(expected_bytes,4294967136n) && Nat.is_eq(Nat.mod(expected_bytes,8n),0n) &&
    Nat.is_eq(expected_bytes,H.length(message))
  close_checked(label,Bits.Bits64{next_hi,next_lo},rho,kind,work,nonce,message,good)

# The stream originates in close. Its eight whole words per expansion are consumed
# in order. The checked plan bounds the requested draws below 2^48 expansion calls.
type Read<-A: Data> is Data:
  Read{value: A, stream: Stream}

def value(-A: Data, read: Read<A>) -> A:
  Read{v,_} = read
  v

def after(-A: Data, read: Read<A>) -> Stream:
  Read{_,s} = read
  s

def expanded_word(q: Query, j: Nat, state: Kernel.H8) -> Read<Bits.Bits64>:
  Kernel.H8{a,b,c,d,e,f,g,h,i,jj,k,l,m,n,o,p} = state
  Read{Bits.Bits64{a,b},Stream{q,Nat.add(j,1n),[Bits.Bits64{c,d},Bits.Bits64{e,f},Bits.Bits64{g,h},Bits.Bits64{i,jj},Bits.Bits64{k,l},Bits.Bits64{m,n},Bits.Bits64{o,p}]}}

def next_word(s: Stream) -> Read<Bits.Bits64>:
  match s:
    case Stream{q,j,v <> rest}: Read{v,Stream{q,j,rest}}
    case Stream{+q,+j,[]}: expanded_word(q,j,expand_state(q,j))

def canonical(word: Bits.Bits64) -> Bool:
  Bits.Bits64{hi,lo} = word
  U32.is_ne(Bits.field_candidate(hi,lo),0)

def as_field(word: Bits.Bits64) -> Field.Gl:
  Bits.Bits64{hi,lo} = word
  Field.Gl{hi,lo}

def base_attempt(remaining: Nat, previous: Bits.Bits64, stream: Stream, valid: Bool) -> Read<Field.Gl>:
  match remaining valid:
    case _ True{}: Read{as_field(previous),stream}
    case 0n False{}: Read{Field.Gl{0,0},stream}
    case 1n+p False{}:
      +taken = next_word(stream)
      +w = value(Bits.Bits64,taken)
      base_attempt(p,w,after(Bits.Bits64,taken),canonical(w))

def base(stream: Stream) -> Read<Field.Gl>:
  base_attempt(6n,Bits.Bits64{0,0},stream,False{})

def element(stream: Stream) -> Read<Ext.E3>:
  +a = base(stream)
  +b = base(after(Field.Gl,a))
  +c = base(after(Field.Gl,b))
  Read{Ext.pack(value(Field.Gl,a),value(Field.Gl,b),value(Field.Gl,c)),after(Field.Gl,c)}

def is_zero(v: Ext.E3) -> Bool:
  Ext.E3{a,b,c,d,e,f} = v
  U32.is_zero(U32.or(U32.or(U32.or(a,b),U32.or(c,d)),U32.or(e,f)))

def nonzero_first(first: Read<Ext.E3>, zero: Bool) -> Read<Ext.E3>:
  match zero:
    case False{}: first
    case True{}:
      +second = element(after(Ext.E3,first))
      +v = value(Ext.E3,second)
      Read{Bool.pick(Ext.E3,is_zero(v),Ext.E3{0,1,0,0,0,0},v),after(Ext.E3,second)}

def nonzero(stream: Stream) -> Read<Ext.E3>:
  +first = element(stream)
  nonzero_first(first,is_zero(value(Ext.E3,first)))

def word_nat(w: Bits.Bits64) -> Nat:
  Bits.Bits64{h,l} = w
  Nat.add(Nat.mul(U32.to_nat(h),P2.pow2(32n)),U32.to_nat(l))

def low_bits(w: Bits.Bits64, k: Nat) -> Nat:
  Bits.Bits64{h,l} = w
  word_nat(Bits.position(h,l,k))

# R6.6. Keep raw order and repeats for the model's batching rows. Shapes limit k to 48.
def draws(n: Nat, +k: Nat, stream: Stream) -> Read<List<&2,Nat>>:
  match n:
    case 0n: Read{[],stream}
    case 1n+p:
      +w = next_word(stream)
      +tail = draws(p,k,after(Bits.Bits64,w))
      Read{low_bits(value(Bits.Bits64,w),k) <> value(List<&2,Nat>,tail),after(List<&2,Nat>,tail)}

# R6.7. A negative entry is represented as the U32 value 0xffffffff.
def trit_limb(n: Nat, +w: U32) -> H.Bytes:
  match n:
    case 0n: []
    case 1n+p:
      trit = Bool.pick(U32,U32.is_zero(U32.and(w,1)),0,Bool.pick(U32,U32.is_zero(U32.and(w,2)),1,4294967295))
      trit <> trit_limb(p,U32.shrn(w,2n))

def trit_chunk(w: Bits.Bits64, +entries: Nat) -> H.Bytes:
  Bits.Bits64{h,l} = w
  H.cat([trit_limb(Nat.min(entries,16n),l),trit_limb(Nat.min(Nat.sub(entries,16n),16n),h)])

def trit_words(count: Nat, +entries: Nat, stream: Stream) -> Read<H.Bytes>:
  match count:
    case 0n: Read{[],stream}
    case 1n+p:
      +w = next_word(stream)
      +tail = trit_words(p,Nat.sub(entries,32n),after(Bits.Bits64,w))
      Read{H.cat([trit_chunk(value(Bits.Bits64,w),entries),value(H.Bytes,tail)]),after(H.Bytes,tail)}

def trits(+n: Nat, stream: Stream) -> Read<H.Bytes>:
  trit_words(Nat.div(Nat.add(n,31n),32n),n,stream)

def seal(stream: Stream) -> H.Bytes:
  +a = next_word(stream)
  +b = next_word(after(Bits.Bits64,a))
  +c = next_word(after(Bits.Bits64,b))
  d = next_word(after(Bits.Bits64,c))
  H.cat([wire(value(Bits.Bits64,a)),wire(value(Bits.Bits64,b)),wire(value(Bits.Bits64,c)),wire(value(Bits.Bits64,d))])
