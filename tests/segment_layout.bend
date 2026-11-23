import Base
import ../src/base_check.bend as B
import ../src/sumcheck.bend as E
import ../src/fold.bend as F
import ../src/row_tensor.bend as V
import ../src/segment_layout.bend as L
import ../src/key_stage_lookup.bend as K
import ../src/extension.bend as X

# One 2x2 rectangle from a 4x4 logical array, laid over two rows and
# two places in a physical 4x4 oracle. Exercise both enumeration orders.
def source() -> F.Term:
  F.Term{K.small(23n),[F.Factor{K.small(2n),K.small(3n)},F.Factor{K.small(5n),K.small(7n)},
    F.Factor{K.small(11n),K.small(13n)},F.Factor{K.small(17n),K.small(19n)}]}

def entry(t: F.Term,i: Nat) -> X.E3:
  F.Term{w,fs} = t
  V.entry(fs,i,w)

def expected(+row: Nat,+column: Nat,low_i: Bool) -> X.E3:
  +axis = Nat.mod(row,2n)
  +i = Bool.pick(Nat,low_i,column,axis)
  +j = Nat.sub(Nat.add(column,axis),i)
  v = entry(source(),Nat.add(Nat.add(2n,i),Nat.mul(4n,j)))
  Bool.pick(X.E3,Nat.is_ge(row,2n) && Nat.is_lt(column,2n),v,F.zero())

def points(n: Nat,+t: F.Term,+low_i: Bool) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +p = k
      B.equal(entry(t,p),expected(Nat.mod(p,4n),Nat.div(p,4n),low_i)) && points(p,t,low_i)

def check(+dir: Bool) -> Bool:
  block: L.Block = L.Block{2n,0n,2n,0n,1n,1n,1n,1n,dir}
  points(16n,L.tile(block,source(),2n,2n,2n),dir)

# R12.17. One of two disjoint layout tiles contains logical (row=2,col=1).
# Its weight and destination must survive; the other tile gives the zero form.
def kept() -> Bool:
  +hit: L.Block = L.Block{2n,0n,2n,0n,1n,1n,1n,1n,True{}}
  miss: L.Block = L.Block{0n,2n,2n,2n,1n,1n,1n,1n,False{}}
  +rs: F.Form = L.translate([F.Term{K.small(23n),V.choice(4n,6n)}],[miss,hit],2n,2n,2n,[])
  right = Maybe.default(&2,F.Term,List.head(&2,F.Term,rs),F.Term{F.zero(),[]})
  Nat.is_eq(F.count(F.Term,rs,0n),1n) && B.equal(entry(right,3n),K.small(23n))

def main() -> IO(Unit):
  IO.print(Bool.show(check(True{}) && check(False{}) && kept()))

#|True
