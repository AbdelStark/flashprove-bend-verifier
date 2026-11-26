import Base
import ../src/extension.bend as X
import ../src/key_stage_lookup.bend as K
import ../src/fold.bend as F
import ../src/sumcheck.bend as E
import ../src/segment_coverage.bend as C

# R13.9. The prefix [0,2) always takes endpoint zero of its second bit.
# A zero in unused padding is admitted; extending the prefix exposes it.
def used() -> Bool:
  +fs: F.Factors = [F.Factor{F.one(),F.one()},F.Factor{F.one(),F.zero()}]
  C.prefix(fs,2n,1n) && Bool.not(C.prefix(fs,3n,1n))

def powers() -> Bool:
  +m = E.negate(F.one())
  C.order(m,2n) && Bool.not(C.order(m,3n)) && Bool.not(C.order(F.zero(),1n)) && C.order(K.small(3n),1024n)

# Cancellation between two distinct reads can leave one entry of U3
# unconstrained even when neither read is the all-zero vector.
def cancellation() -> Bool:
  +all: F.Term = F.Term{F.one(),[F.Factor{F.one(),F.one()}]}
  cancel: F.Term = F.Term{E.negate(F.one()),[F.Factor{F.zero(),F.one()}]}
  C.form([all],2n) && Bool.not(C.form([all,cancel],2n))

# One tensor term: the endpoint shortcut agrees with the full table, whose
# entries are products of one endpoint per bit (cubic coefficients included).
def g(+x: U32) -> X.E3: X.E3{0,x,0,0,0,0}

def agree(+t: F.Term,+length: Nat,+bits: Nat) -> String:
  +got = C.form([t],length)
  +want = F.fits([t],bits) && C.dense([t],length,bits,None{})
  Bool.show(Bool.not(Bool.xor(got,want))) ++ "/" ++ Bool.show(got)

def single() -> String:
  +a: F.Factor = F.Factor{X.E3{0,3,0,5,0,7},g(2)}
  +b: F.Factor = F.Factor{g(9),X.E3{0,0,0,1,0,0}}
  +w: X.E3 = X.E3{0,6,0,0,0,13}
  String.join([
    agree(F.Term{w,[a,b,a]},8n,3n), agree(F.Term{w,[a,F.Low{},b]},8n,3n),
    agree(F.Term{w,[F.High{},a]},4n,2n), agree(F.Term{w,[a,F.Factor{g(1),F.zero()}]},4n,2n),
    agree(F.Term{F.zero(),[a,b]},4n,2n), agree(F.Term{w,[a,b]},8n,3n),
    agree(F.Term{w,[a,F.Low{}]},2n,1n), agree(F.Term{w,[a,b]},3n,2n)]," ")

def main() -> IO(Unit):
  IO.print(Bool.show(used() && powers() && cancellation()) ++ " " ++ single())

#|True True/True True/False True/False True/False True/False True/False True/False True/True
