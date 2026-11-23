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

def main() -> IO(Unit):
  IO.print(Bool.show(used() && powers() && cancellation()))

#|True
