import Base
import ../src/fold.bend as F
import ../src/row_tensor.bend as T
import ../src/extension.bend as E
import ../src/base_check.bend as B

# Compare the chunked path to coordinate-by-coordinate interpolation. Test
# every Boolean address, and interrupt the selector run at each position.
def equal(xs: F.Factors, ys: F.Factors) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case Con{+x,xt} Con{+y,yt}: B.equal(F.at_bit(x,False{}),F.at_bit(y,False{})) &&
      B.equal(F.at_bit(x,True{}),F.at_bit(y,True{})) && equal(xt,yt)
    case _ _: False{}

def same(x: F.Term, y: F.Term) -> Bool:
  F.Term{a,as_} = x
  F.Term{b,bs} = y
  B.equal(a,b) && equal(as_,bs)

def interrupt(fs: F.Factors, pos: Nat) -> F.Factors:
  match fs pos:
    case Con{_,rest} 0n: F.Factor{E.E3{0,3,0,4,0,0},E.E3{0,17,0,0,0,9}} <> rest
    case Con{f,rest} 1n+n: f <> interrupt(rest,n)
    case _ _: []

def agree(+gs: B.Elements, +fs: F.Factors) -> Bool:
  +w: E.E3 = E.E3{0,4,0,2,0,3}
  same(F.project(F.prepare(gs),F.Term{w,fs}),F.fix(gs,fs,w))

def positions(n: Nat,+gs: B.Elements,+fs: F.Factors) -> Bool:
  match n:
    case 0n: agree(gs,fs)
    case 1n+k:
      +i = k
      agree(gs,interrupt(fs,i)) && positions(i,gs,fs)

def addresses(n: Nat,+gs: B.Elements) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +i = k
      positions(6n,gs,T.choice(6n,i)) && addresses(i,gs)

def main() -> IO(Unit):
  +coords: B.Elements = [F.one(),E.E3{0,8,0,3,0,0},F.zero(),E.E3{0,0,0,4,0,5},F.one()]
  do IO<Unit>:
    IO.print(Bool.show(addresses(64n,coords)))
    IO.print(Bool.show(agree(coords,T.choice(2n,1n))))
    IO.print(Bool.show(agree([],T.choice(3n,5n))))
#|True
#|True
#|True
