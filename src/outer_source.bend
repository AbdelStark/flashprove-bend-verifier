import Base
import ./base_check.bend as B
import ./row_tensor.bend as V
import ./sumcheck.bend as E
import ./fold.bend as F
import ./extension.bend as X

# A matrix coefficient v(i,c) = scale * row(i) * columns[c].
type Source is Data:
  Outer{row: F.Factors, columns: B.Elements, bits: Nat, scale: X.E3}

def scaled(source: Source,w: X.E3) -> Source:
  Outer{row,cs,bits,v} = source
  Outer{row,cs,bits,E.mul(v,w)}

def pairs(cs: B.Elements,+row: F.Factors,+bits: Nat,i: Nat,+w: X.E3,out: F.Form) -> F.Form:
  match cs:
    case []: out
    case [a]: F.Term{E.mul(a,w),List.append(&2,F.Factor,row,V.choice(bits,i))} <> out
    case a <> b <> tail:
      +j = i
      fs: F.Factors = F.Factor{a,b} <> V.choice(Nat.sub(bits,1n),Nat.div(j,2n))
      pairs(tail,row,bits,Nat.add(j,2n),w,F.Term{w,List.append(&2,F.Factor,row,fs)} <> out)

def expand(source: Source) -> F.Form:
  Outer{row,cs,bits,w} = source
  pairs(cs,row,bits,0n,w,[])
