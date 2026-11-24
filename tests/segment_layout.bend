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

# Two logical column intervals of eight cells, with their row and column
# bits split differently in the destination. Compare all destination entries,
# including outside the intervals, against direct R12.17 tile evaluation.
def total(ts: F.Form,+i: Nat,acc: X.E3) -> X.E3:
  match ts:
    case []: acc
    case t <> rest: total(rest,i,E.add(acc,entry(t,i)))

def same_entries(+a: F.Form,+b: F.Form,n: Nat) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +i = k
      B.equal(total(a,i,F.zero()),total(b,i,F.zero())) && same_entries(a,b,i)

def indexed() -> Bool:
  +bs : List<&2,L.Block> = [L.Block{0n,8n,4n,0n,0n,3n,1n,2n,False{}},
    L.Block{0n,0n,0n,2n,0n,3n,2n,1n,True{}}]
  +terms : F.Form = [source(),F.Term{K.small(13n),V.choice(4n,12n)},F.Term{F.one(),[]}]
  +res = L.translate_matrix(L.index(1n,16n,bs),terms,bs,1n,16n,3n,2n)
  same_entries(res,L.translate(terms,bs,0n,3n,2n,[]),32n)

# A spanning rectangle in the top two rows rules out a column cut at the root.
# In the bottom two rows both rectangles span that row interval and require
# a column cut. The fourth term exercises the short-factor fallback.
def row_then_cols(t: L.Index) -> Bool:
  match t:
    case L.Rows{L.Leaf{_},L.Cols{_,_}}: True{}
    case _: False{}

def rectangles() -> Bool:
  +bs : List<&2,L.Block> = [
    L.Block{0n,0n,0n,0n,1n,2n,2n,1n,True{}},
    L.Block{2n,0n,0n,2n,1n,1n,1n,1n,False{}},
    L.Block{2n,2n,2n,2n,1n,1n,1n,1n,True{}}]
  +ts : F.Form = [source(),F.Term{K.small(41n),V.choice(4n,10n)},
    F.Term{F.zero(),V.choice(4n,3n)},F.Term{F.one(),[]}]
  +t = L.index(4n,4n,bs)
  correct = same_entries(L.translate_matrix(t,ts,bs,4n,4n,2n,2n),L.translate(ts,bs,2n,2n,2n,[]),16n)
  correct && row_then_cols(t)

def is_general(t: L.Index) -> Bool:
  match t:
    case L.General{}: True{}
    case _: False{}

def fallback() -> Bool:
  +b: L.Block = L.Block{0n,0n,0n,0n,2n,2n,2n,2n,True{}}
  is_general(L.index(4n,4n,[b,b]))

def main() -> IO(Unit):
  IO.print(Bool.show(check(True{}) && check(False{}) && kept() && indexed() && rectangles() && fallback()))

#|True
