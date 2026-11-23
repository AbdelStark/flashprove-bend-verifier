import Base
import ../src/extension.bend as X
import ../src/sumcheck.bend as E
import ../src/base_check.bend as B

# R11.4's ledger includes known public targets in the base field and two zero limbs.
# These are compared as canonical field encodings, both before and after multiplication.
def main() -> IO(Unit):
  +z : X.E3 = X.E3{0,0,0,0,0,0}
  +a : X.E3 = X.E3{0,1,0,0,0,0}
  +minus : X.E3 = X.E3{4294967295,0,0,0,0,0}
  do IO<Unit>:
    IO.print(Bool.show(B.equal(E.negate(z),z)))
    IO.print(Bool.show(B.equal(E.negate(a),minus)))
    IO.print(Bool.show(B.equal(E.negate(minus),a)))
#|True
#|True
#|True
