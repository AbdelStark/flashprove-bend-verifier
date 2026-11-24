import Base
import ./fold.bend as F
import ./extension.bend as X
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./key_stage_lookup.bend as K
import ./key_stage_matrix.bend as Shift
import ./oracle_sample.bend as Sample

# Smallness functional columns in §13.9. At offset+c*count+s the contribution
# is scale*columns[c]*step^s. The validated public shape fixes the bit width.
type Series is Data:
  Series{columns: B.Elements, count: Nat, offset: Nat, bits: Nat, step: X.E3, scale: X.E3}

def scaled(s: Series,w: X.E3) -> Series:
  Series{cs,n,at,bits,z,scale} = s
  Series{cs,n,at,bits,z,E.mul(w,scale)}

def fits(s: Series,b: Nat,length: Nat) -> Bool:
  Series{cs,n,at,bits,_,_} = s
  Nat.is_eq(b,bits) && Nat.is_le(Nat.add(at,Nat.mul(n,F.count(X.E3,cs,0n))),length)

# The complete, separable form remains available to general layout placement
# and to the independent model-row probe at arbitrary evaluation points.
def terms(cs: B.Elements,+n: Nat,+at: Nat,+bits: Nat,+point: F.Factors,+scale: X.E3,acc: F.Form) -> F.Form:
  match cs:
    case []: acc
    case u <> rest:
      xs = Shift.stretch(1n+Nat.mul(2n,bits),bits,0n,at,n,point,E.mul(u,scale),[])
      terms(rest,n,Nat.add(at,n),bits,point,scale,List.reverse.go(&2,F.Term,xs,acc))

def expand(s: Series) -> F.Form:
  Series{cs,+n,at,bits,z,scale} = s
  terms(cs,n,at,bits,K.powers(Sample.row_bits(n),z),scale,[])

def run(n: Nat,+at: U32,+step: X.E3,+value: X.E3,buf: Array<X.E3>) -> Array<X.E3>:
  match n:
    case 0n: buf
    case 1n: F.summed(Array.get(X.E3,buf,at),at,value)
    case 2n+k:
      next = F.summed(Array.get(X.E3,buf,at),at,value)
      run(1n+k,U32.add(at,1),step,E.mul(value,step),next)

def write_columns(cs: B.Elements,+n: Nat,+at: U32,+z: X.E3,+scale: X.E3,buf: Array<X.E3>) -> Array<X.E3>:
  match cs:
    case []: buf
    case u <> rest:
      next = run(n,at,z,E.mul(u,scale),buf)
      write_columns(rest,n,U32.add(at,U32.from_nat(n)),z,scale,next)

def write(s: Series,buf: Array<X.E3>) -> Array<X.E3>:
  Series{cs,n,at,_,z,scale} = s
  write_columns(cs,n,U32.from_nat(at),z,scale,buf)
