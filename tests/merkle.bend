import Base
import ../src/merkle.bend as M

def show(d: M.Digest) -> String:
  M.Digest{a,b,c,d,e,f,g,h} = d
  U32.show(a) ++ " " ++ U32.show(b) ++ " " ++ U32.show(c) ++ " " ++ U32.show(d) ++ " " ++ U32.show(e) ++ " " ++ U32.show(f) ++ " " ++ U32.show(g) ++ " " ++ U32.show(h)

# Independent BLAKE2b-256 vectors. Start words are the salt and personalization.
def main() -> IO(Unit):
  +s: M.Digest = M.Digest{1,2,3,4,5,6,7,8}
  +l: M.Digest = M.Digest{9,10,11,12,13,14,15,16}
  +r: M.Digest = M.Digest{17,18,19,20,21,22,23,24}
  do IO<Unit>:
    IO.print(show(M.parent(0,166,0,0,s,l,r)))
    IO.print(show(M.parent(0,178,0,0,s,r,l)))
    IO.print(show(M.parent(0,172,1,99,M.Digest{0,0,0,0,0,0,0,0},l,r)))
#|4105944263 854500832 2093638908 656873832 2939007294 612872924 2487290770 2002411520
#|2865884384 1136098867 3515290628 28694929 601207712 1357174680 2644116329 1638786570
#|1111657899 3793113971 760544734 3052738882 2653465628 1148866624 3640280732 740949126
