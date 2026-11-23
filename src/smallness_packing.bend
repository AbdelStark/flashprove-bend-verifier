import Base
import ./base_check.bend as B
import ./fold.bend as F
import ./fold_cs.bend as CS
import ./goldilocks.bend as Gl
import ./extension.bend as X
import ./sumcheck.bend as E
import ./key_stage_lookup.bend as KL
import ./header.bend as Header

# The weight of packed digit row i is u^floor(i/3) * radix^(i mod 3)
# with u=chi^128. For bit j, write 2^j=3 q[j]+r[j]. Then a separable
# term contributes the u^q part; the remaining weight depends only on
# t=sum r[j]bit[j]. Every released matrix has <= 16 row bits, so t<=24.
# Interpolate that function on the additive index t by a 32-point DFT.
# Each Fourier mode has endpoints 1 and u^q[j]*omega^(mode*r[j]).
def radix() -> X.E3: KL.small(1048576n)

def three(i: Nat, +u: X.E3) -> X.E3:
  +j = i
  E.mul(KL.power(32n,Nat.div(j,3n),u,F.one()),KL.power(2n,Nat.mod(j,3n),radix(),F.one()))

def samples(n: Nat, +u: X.E3) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k:
      +j = k
      three(j,u) <> samples(j,u)

def horner(xs: B.Elements, +mode: Gl.Gl, acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case y <> rest: horner(rest,mode,E.add(CS.scale(mode,acc),y))

def endpoint(bits: Nat, place: Nat, +mode: Gl.Gl, +u: X.E3) -> F.Factors:
  match bits:
    case 0n: []
    case 1n+k:
      +p = place
      high = CS.scale(CS.pow(mode,Nat.mod(p,3n)),KL.power(32n,Nat.div(p,3n),u,F.one()))
      F.Factor{F.one(),high} <> endpoint(k,Nat.mul(p,2n),mode,u)

def series(left: Nat, +bits: Nat, +u: X.E3, +values: B.Elements, mode: Gl.Gl,
  inverse: Gl.Gl, acc: F.Form) -> F.Form:
  match left:
    case 0n: acc
    case 1n+k:
      +m = mode
      +i = inverse
      # Goldilocks order-32 root, inverse root and 1/32.
      w = CS.scale(Gl.Gl{4160749567,134217729},horner(values,i,F.zero()))
      term: F.Term = F.Term{w,endpoint(bits,1n,m,u)}
      series(k,bits,u,values,X.product(m,Gl.Gl{16383,4294950912}),
        X.product(i,Gl.Gl{4294967294,4294705153}),term <> acc)

def left(+bits: Nat, +step: X.E3) -> IO(F.Form):
  do IO<F.Form>:
    ok : Unit <- Header.require(Nat.is_le(bits,20n),"NO: segment-packing-width")
    return series(32n,bits,step,samples(32n,step),Gl.Gl{0,1},Gl.Gl{0,1},[])

type Sum is Data:
  Sum{next: X.E3, sum: X.E3}

def double(v: Sum, bit: Nat, u: X.E3) -> Sum:
  Sum{+p,s} = v
  +next = E.mul(p,p)
  +total = E.mul(E.add(F.one(),p),s)
  Bool.pick(Sum,Nat.is_eq(bit,0n),Sum{next,total},Sum{E.mul(next,u),E.add(total,next)})

def geometric(fuel: Nat, n: Nat, +u: X.E3) -> Sum:
  match fuel n:
    case _ 0n: Sum{F.one(),F.zero()}
    case 1n+k +m: double(geometric(k,Nat.div(m,2n),u),Nat.mod(m,2n),u)
    case _ _: Sum{F.one(),F.zero()}

def at_end(progression: Sum, +tail: Nat) -> X.E3:
  Sum{p,s} = progression
  +b = radix()
  base = E.mul(s,E.add(F.one(),E.add(b,E.mul(b,b))))
  rest = Bool.pick(X.E3,Nat.is_eq(tail,1n),F.one(),Bool.pick(X.E3,Nat.is_eq(tail,2n),E.add(F.one(),b),F.zero()))
  E.add(base,E.mul(p,rest))

def total(+rows: Nat, step: X.E3) -> X.E3:
  at_end(geometric(32n,Nat.div(rows,3n),step),Nat.mod(rows,3n))
