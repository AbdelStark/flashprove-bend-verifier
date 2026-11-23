import Base
import ../src/row_tensor.bend as X
import ../src/fold.bend as F
import ../src/base_check.bend as B
import ../src/extension.bend as Ext
import ../src/sumcheck.bend as E

def scalar(i: Nat) -> Ext.E3:
  Ext.E3{0,U32.from_nat(i),0,0,0,0}

def total(form: F.Form, +at: Nat, acc: Ext.E3) -> Ext.E3:
  match form:
    case []: acc
    case F.Term{w,fs} <> tail: total(tail,at,E.add(acc,X.entry(fs,at,w)))

def compare(n: Nat, +length: Nat, +fs: F.Factors, +cut: F.Form) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +i = k
      expected = Bool.pick(Ext.E3,Nat.is_lt(i,length),X.entry(fs,i,scalar(13n)),F.zero())
      B.equal(total(cut,i,F.zero()),expected) && compare(i,length,fs,cut)

def prefixes(n: Nat, +fs: F.Factors) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +length = k
      compare(16n,length,fs,X.below(fs,length,scalar(13n))) && prefixes(length,fs)

# Four vector bits become two row bits, one member bit, then two position bits.
def moves(n: Nat) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +i = k
      fs = X.choice(4n,i)
      +form = X.rows_high([F.Term{scalar(7n),fs}],2n,X.Right{})
      +p = Nat.add(Nat.div(i,4n),Nat.mul(8n,Nat.mod(i,4n)))
      B.equal(total(form,Nat.add(p,4n),F.zero()),scalar(7n)) && B.equal(total(form,p,F.zero()),F.zero()) && moves(i)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Bool.show(prefixes(17n,X.eq([scalar(2n),scalar(3n),scalar(5n),scalar(7n)])) && moves(16n)))

#|True
