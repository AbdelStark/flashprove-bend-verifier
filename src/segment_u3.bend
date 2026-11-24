import Base
import ./u3_series.bend as U
import ./fold.bend as F
import ./row_tensor.bend as Tensor
import ./segment_layout.bend as L
import ./segment_model.bend as M
import ./segment_coverage.bend as Cover
import ./base_check.bend as B
import ./extension.bend as X
import ./transcript.bend as T

# A U3 tile consumes a column interval in logical order. Its column bits
# are the low bits of that interval; the physical row occupies the high
# bits. Check every precondition before using this narrower representation.
def spans(bs: L.Tiles,+at: Nat,+len: Nat,+rows: Nat,+cols: Nat) -> Bool:
  match bs:
    case []: Nat.is_eq(at,len)
    case L.Block{0n,c,+r,+p,0n,+bc,+br,+bp,_} <> tail:
      +height = Nat.pow(2n,br)
      +width = Nat.pow(2n,bp)
      +size = Nat.pow(2n,bc)
      Nat.is_eq(c,at) && Nat.is_eq(Nat.mod(at,size),0n) && Nat.is_eq(bc,Nat.add(br,bp)) &&
        Nat.is_eq(Nat.mod(r,height),0n) && Nat.is_le(Nat.add(r,height),rows) &&
        Nat.is_eq(Nat.mod(p,width),0n) && Nat.is_le(Nat.add(p,width),cols) &&
        spans(tail,Nat.add(at,size),len,rows,cols)
    case _: False{}

# Cover.u3 collects coefficients under one name. Leave the general placement
# intact when reads of that name target distinct owners.
def local(rs: List<&2,M.Read>,+link: Nat,+bits: Nat,+len: Nat) -> Bool:
  match rs:
    case []: True{}
    case M.U3Run{owner,s} <> tail: Nat.is_eq(owner,link) && U.fits(s,bits,len) && local(tail,link,bits,len)
    case M.Read{owner,name,_} <> tail:
      (Bool.not(Cover.column(name)) || Nat.is_eq(owner,link)) && local(tail,link,bits,len)

def others(rs: List<&2,M.Read>) -> List<&2,M.Read>:
  match rs:
    case []: []
    case M.U3Run{_,_} <> tail: others(tail)
    case M.Read{i,name,form} <> tail:
      +s = name
      +rest = others(tail)
      Bool.pick(List<&2,M.Read>,Cover.column(s),rest,M.Read{i,s,form} <> rest)

def fits(rs: List<&2,M.Read>,+bits: Nat) -> Bool:
  match rs:
    case []: True{}
    case M.U3Run{_,_} <> tail: fits(tail,bits)
    case M.Read{_,name,ts} <> tail:
      (Bool.not(Cover.column(name)) || F.fits(ts,bits)) && fits(tail,bits)

def populate(rs: List<&2,M.Read>,buf: Array<X.E3>) -> Array<X.E3>:
  match rs:
    case []: buf
    case M.U3Run{_,s} <> tail: populate(tail,U.write(s,buf))
    case M.Read{_,name,ts} <> tail:
      add = Bool.pick(Array<X.E3> -> Array<X.E3>,Cover.column(name),b => F.populate(ts,b),b => b)
      populate(tail,add(buf))

# An affine interpolation over two adjacent halves equals the multilinear
# extension evaluated at the current gamma. Descend highest bit first, so
# leaves consume the dense coefficients in wire order. Check every genuine
# cell for the §13.9 U3 nonzero condition while consuming it.
type Chunk is Type:
  Chunk{value: X.E3, tail: List<X.E3>, live: Bool}

def take(values: List<X.E3>) -> Chunk:
  match values:
    case +x <> rest: Chunk{x,rest,Bool.not(T.is_zero(x))}
    case []: Chunk{F.zero(),[],False{}}

def combine(a: X.E3,ok: Bool,g: X.E3,right: Chunk) -> Chunk:
  Chunk{b,tail,valid} = right
  Chunk{F.mix(a,b,g),tail,ok && valid}

def half(left: Chunk,g: X.E3,f: List<X.E3> -> Chunk) -> Chunk:
  Chunk{a,tail,ok} = left
  combine(a,ok,g,f(tail))

def chunk(gs: B.Elements,values: List<X.E3>) -> Chunk:
  match gs:
    case []: take(values)
    case g <> +tail: half(chunk(tail,values),g,xs => chunk(tail,xs))

type Scanned is Type:
  Scanned{form: F.Form, remaining: List<X.E3>, live: Bool}

type Stripe is Data:
  Stripe{gammas: B.Elements, low: F.Factors, upper: Nat, first: Nat, n: Nat}

def appended(acc: F.Form,fs: F.Factors,ok: Bool,read: Chunk) -> Scanned:
  Chunk{w,tail,good} = read
  Scanned{F.Term{w,fs} <> acc,tail,ok && good}

def chunks(n: Nat,at: Nat,+free: F.Factors,+gs: B.Elements,+bits: Nat,s: Scanned) -> Scanned:
  match n s:
    case 0n x: x
    case 1n+k Scanned{acc,values,ok}:
      +pos = at
      fs = List.append(&2,F.Factor,free,Tensor.choice(bits,pos))
      chunks(k,1n+pos,free,gs,bits,appended(acc,fs,ok,chunk(gs,values)))

def rows(n: Nat,at: Nat,+bits: Nat,+stripe: Stripe,s: Scanned) -> Scanned:
  match n:
    case 0n: s
    case 1n+k:
      Stripe{gs,neutral,upper,first,count} = stripe
      +pos = at
      factors = List.append(&2,F.Factor,Tensor.choice(bits,pos),neutral)
      rows(k,1n+pos,bits,stripe,chunks(count,first,factors,gs,upper,s))

def stripes(bs: L.Tiles,+gamma: B.Elements,+gr: Nat,+rb: Nat,+cb: Nat,s: Scanned) -> Scanned:
  match bs:
    case []: s
    case L.Block{_,_,r,p,_,_,br,+bp,_} <> tail:
      +k = Nat.min(gr,bp)
      +size = Nat.pow(2n,k)
      gs = List.reverse(&2,X.E3,List.take(&2,X.E3,gamma,k))
      neutral = List.replicate(F.Factor,k,F.Factor{F.one(),F.one()})
      stripe: Stripe = Stripe{gs,neutral,Nat.sub(cb,k),Nat.div(p,size),Nat.pow(2n,Nat.sub(bp,k))}
      stripes(tail,gamma,gr,rb,cb,rows(Nat.pow(2n,br),r,rb,stripe,s))

type Packing is Data:
  Packed{form: F.Form, live: Bool}

def result(s: Scanned) -> Packing:
  Scanned{form,_,ok} = s
  Packed{form,ok}

def scan(bs: L.Tiles,gs: B.Elements,gr: Nat,rb: Nat,cb: Nat,values: List<X.E3>) -> Packing:
  result(stripes(bs,gs,gr,rb,cb,Scanned{[],values,True{}}))
