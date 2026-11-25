import Base
import ../src/segment_attention_aff.bend as A
import ../src/segment_attention_points.bend as Z
import ../src/segment_attention_shape.bend as S
import ../src/ff_shape.bend as G
import ../src/ff_reads.bend as R
import ../src/ff_lookup.bend as Lookup
import ../src/row_tensor.bend as T
import ../src/fold.bend as F
import ../src/sumcheck.bend as E
import ../src/base_check.bend as B
import ../src/extension.bend as X

# Scalar oracle at one address, using the low-first factors of the generic row tensor.
def scalar(z:B.Elements,i:Nat) -> X.E3: T.entry(T.eq(A.rev(z)),i,F.one())
def same(xs:B.Elements,ys:B.Elements) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case Con{x,t} Con{y,r}: B.equal(x,y) && same(t,r)
    case _ _: False{}
def expected(n:Nat,+at:Nat,+z:B.Elements) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k: scalar(z,at) <> expected(k,1n+at,z)
def interval(+z:B.Elements,+at:Nat,+n:Nat) -> Bool:
  same(A.eq_range(A.rev(z),at,n),expected(n,at,z)) && B.equal(A.eq(z,at),scalar(z,at))
def logical(n:Nat,+i:Nat,+seg:G.Segment,+z:B.Elements,+unit:Nat) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k: scalar(z,Nat.div(G.pos(seg,Nat.mul(i,unit)),unit)) <> logical(k,1n+i,seg,z,unit)

# Independent enumeration of the two halves of the FlashProve tile cover.
def scan(n:Nat,+nt:Nat,+p:B.Elements,+sg:B.Elements,+col:Bool,+idx:Nat,+acc:X.E3) -> X.E3:
  match n:
    case 0n: acc
    case 1n++j:
      +r = Nat.div(j,Nat.sub(nt,1n))
      +t = Nat.mod(j,Nat.sub(nt,1n))
      +below = Nat.is_lt(t,r)
      row = Bool.pick(Nat,below,r,Nat.sub(Nat.sub(nt,1n),r))
      column = Bool.pick(Nat,below,t,Nat.sub(t,r))
      w = E.mul(scalar(p,r),scalar(sg,t))
      scan(j,nt,p,sg,col,idx,Bool.pick(X.E3,Nat.is_eq(idx,Bool.pick(Nat,col,column,row)),E.add(acc,w),acc))
def margins(n:Nat,+nt:Nat,+p:B.Elements,+sg:B.Elements,+col:Bool,+idx:Nat) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k: scan(Nat.mul(Nat.div(nt,2n),Nat.sub(nt,1n)),nt,p,sg,col,idx,F.zero()) <> margins(k,nt,p,sg,col,1n+idx)
def tiles(+z:B.Elements,+h:Nat,+col:Bool) -> Bool:
  +nt = A.size(h)
  s : S.Shape = S.Shape{h,0n,1n,0n,0n,0n,0n,0n,0n,0n,0n,0n}
  +m = Nat.sub(h,1n)
  same(Z.marginals(s,z,col),margins(nt,nt,A.slice(z,1n,m),A.slice(z,1n+m,h),col,0n))

def main() -> IO(Unit):
  +a : X.E3 = X.E3{0,5,0,7,0,2}
  +b : X.E3 = X.E3{6,4,3,2,1,7}
  +z : B.Elements = [a,b,F.zero(),F.one(),a,b]
  +runs : List<&2,G.Run> = [G.Run{10n,2n},G.Run{7n,0n},G.Run{19n,5n},G.Run{1n,6n}]
  +seg : G.Segment = G.Segment{0n,6n,13n,False{},runs}
  do IO<Unit>:
    IO.print(Bool.show(interval([],9n,4n) && interval(z,0n,0n) && interval(z,1n,2n) && interval(z,28n,43n)))
    IO.print(Bool.show(same(R.weights(6n,z,seg,3n,[]),logical(6n,0n,seg,z,3n))))
    IO.print(Bool.show(same(Lookup.cuts(runs,A.rev(z),8n,2n),Z.cat(expected(1n,5n,z),expected(3n,0n,z)))))
    IO.print(Bool.show(tiles(z,0n,False{}) && tiles(z,1n,True{}) && tiles(z,3n,False{}) && tiles(z,3n,True{})))
    IO.print(Bool.show(tiles([a,b],3n,False{}) && tiles([b,a],3n,True{})))

#|True
#|True
#|True
#|True
#|True
