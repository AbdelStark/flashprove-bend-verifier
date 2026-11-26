import Base
import ../src/extension.bend as X
import ../src/fold.bend as F
import ../src/base_check.bend as B
import ../src/sumcheck.bend as E
import ../src/chain.bend as Word
import ../src/smallness_columns.bend as C

# Reference: trit u of a word is bits 2u..2u+1 of its low limb, then of its
# high limb. 1 adds the power, 3 subtracts it, 0 and 2 contribute nothing.
def trit(w: Word.Bits64, +u: Nat) -> U32:
  Word.Bits64{hi,lo} = w
  +low = Nat.is_lt(u,16n)
  limb = Bool.pick(U32,low,lo,hi)
  U32.and(U32.shrn(limb,Nat.mul(2n,Bool.pick(Nat,low,u,Nat.sub(u,16n)))),3)

def at(ps: B.Elements, i: Nat) -> X.E3: Maybe.default(&2,X.E3,List.get(&2,X.E3,ps,i),F.zero())

def naive(+w: Word.Bits64, +ps: B.Elements, +base: Nat, u: Nat, acc: X.E3) -> X.E3:
  match u:
    case 0n: acc
    case 1n+(+k): naive(w,ps,base,k,C.signed(trit(w,k),acc,at(ps,Nat.add(base,k))))

def words() -> List<&2,Word.Bits64>:
  [Word.Bits64{0,0}, Word.Bits64{4294967295,4294967295}, Word.Bits64{1431655765,3435973836},
   Word.Bits64{2147483649,1}, Word.Bits64{305419896,2596069104}, Word.Bits64{3,3221225472}]

# Four words fold 128 trits. With 80 powers the rest read as zero.
def check(ws: List<&2,Word.Bits64>, +ps: B.Elements, +base: Nat, r: C.Acc, want: X.E3) -> Bool:
  match ws:
    case []:
      C.Acc{_,got} = r
      B.equal(got,want)
    case +w <> tail: check(tail,ps,Nat.add(base,32n),C.word(w,U32.from_nat(base),r),naive(w,ps,base,32n,want))

def run(+n: Nat) -> Bool:
  +chi: X.E3 = X.E3{0,7,1,3,2,9}
  +ps = C.powers(n,chi,F.one())
  +start: X.E3 = X.E3{0,5,0,0,0,1}
  check(List.take(&2,Word.Bits64,words(),4n),ps,0n,C.Acc{C.powers_table(ps),start},start) &&
    check(List.drop(&2,Word.Bits64,words(),2n),ps,0n,C.Acc{C.powers_table(ps),start},start)

def main() -> IO(Unit):
  IO.print(Bool.show(run(80n) && run(128n)))

#|True
