import Base
import ../src/segment_outer.bend as O
import ../src/outer_source.bend as D
import ../src/segment_layout.bend as L
import ../src/fold.bend as F
import ../src/fold_frame.bend as Frame
import ../src/row_tensor.bend as V
import ../src/sumcheck.bend as E
import ../src/base_check.bend as B
import ../src/key_stage_lookup.bend as K
import ../src/segment_projection.bend as P
import ../src/extension.bend as X

# Logical matrix 4x8; enclosing physical member 8x8. The rectangles vary
# the inner enumeration order and the bit at which rows become columns.
def tiles() -> L.Tiles:
  [L.Block{0n,0n,0n,0n,2n,2n,1n,3n,True{}},
   L.Block{0n,4n,4n,0n,1n,2n,2n,1n,False{}},
   L.Block{2n,4n,4n,4n,1n,2n,1n,2n,True{}}]

def source() -> D.Source:
  # Logical column 7 is implicitly zero. Upper row restrictions include
  # non-Boolean extension factors, including a zero low endpoint.
  rs: F.Factors = [F.Factor{K.small(2n),X.E3{0,3,0,4,0,1}},F.Factor{F.zero(),K.small(7n)}]
  D.Outer{rs,[F.one(),K.small(5n),F.zero(),K.small(42n),K.small(31n),K.small(11n),K.small(19n)],3n,K.small(3n)}

def eval(t: F.Term,n: Nat) -> X.E3:
  F.Term{w,fs} = t
  V.entry(fs,n,w)

def at(ts: F.Form,+gs: B.Elements,+n: Nat,w: X.E3) -> X.E3:
  match ts:
    case []: w
    case F.Term{a,fs} <> tail:
      at(tail,gs,n,E.add(w,eval(F.fix(gs,fs,a),n)))

def same(+a: F.Form,+b: F.Form,+gs: B.Elements,left: Nat) -> Bool:
  match left:
    case 0n: True{}
    case 1n+k:
      +i = k
      B.equal(at(a,gs,i,F.zero()),at(b,gs,i,F.zero())) && same(a,b,gs,i)

def form(on: Frame.On) -> F.Form:
  Frame.On{_,_,ts} = on
  ts

def test(+gs: B.Elements) -> Bool:
  +k = F.count(X.E3,gs,0n)
  +bs = tiles()
  +s = source()
  mat: L.Matrix = L.Matrix{1n,4n,8n,bs,L.index(4n,8n,bs)}
  +coords: B.Elements = F.cat(X.E3,[X.E3{0,5,0,2,0,3},F.one(),K.small(17n)],gs)
  got = form(O.on_matrix(s,mat,Frame.Member{2n,8n,3n,0n,False{}},0n,3n,Some{P.Basis{gs,k,Nat.sub(3n,k)}}))
  expected = L.translate(D.expand(s),bs,2n,3n,3n,[])
  same(got,expected,coords,Nat.pow(2n,Nat.sub(3n,k)))

# A kept oracle is evaluated at fresh coordinates in the next segment.
# Changing the column point here must still match the complete form.
def kept() -> Bool:
  +bs = tiles()
  +s = source()
  mat: L.Matrix = L.Matrix{1n,4n,8n,bs,L.index(4n,8n,bs)}
  got = form(O.on_matrix(s,mat,Frame.Member{2n,8n,3n,0n,True{}},0n,3n,Some{P.Basis{[F.zero(),F.one()],2n,1n}}))
  coords: B.Elements = [F.one(),K.small(13n),K.small(41n),K.small(11n),K.small(29n)]
  same(got,L.translate(D.expand(s),bs,2n,3n,3n,[]),coords,2n)

def main() -> IO(Unit):
  IO.print(Bool.show(kept() && test([]) && test([K.small(11n)]) && test([F.zero(),F.one()]) &&
    test([K.small(5n),X.E3{0,7,0,1,0,11},K.small(3n)])))

#|True
