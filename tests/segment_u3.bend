import Base
import ../src/fold.bend as F
import ../src/base_check.bend as B
import ../src/extension.bend as X
import ../src/segment_layout.bend as L
import ../src/segment_u3.bend as U
import ../src/row_tensor.bend as V
import ../src/key_stage_lookup.bend as K
import ../src/sumcheck.bend as E

# The first logical interval crosses a physical row boundary. The second
# occupies a different physical column prefix in the same two-row member.
def blocks() -> L.Tiles:
  [L.Block{0n,0n,0n,4n,0n,2n,1n,1n,False{}},
   L.Block{0n,4n,1n,0n,0n,2n,0n,2n,True{}}]

def term(n: Nat) -> X.E3: K.small(Nat.add(41n,n))

def dense(n: Nat,out: List<X.E3>) -> List<X.E3>:
  match n:
    case 0n: out
    case 1n+k:
      +i = k
      dense(i,term(i) <> out)

def reference(n: Nat,acc: F.Form) -> F.Form:
  match n:
    case 0n: L.translate(acc,blocks(),0n,1n,3n,[])
    case 1n+k:
      +i = k
      reference(i,F.Term{term(i),V.choice(3n,i)} <> acc)

def eval(t: F.Term,x: Nat) -> X.E3:
  F.Term{w,fs} = t
  V.entry(fs,x,w)

def value(ts: F.Form,+gs: B.Elements,+x: Nat,acc: X.E3) -> X.E3:
  match ts:
    case []: acc
    case F.Term{w,fs} <> tail:
      more = F.fix(gs,fs,w)
      value(tail,gs,x,E.add(acc,eval(more,x)))

def eq(a: F.Form,b: F.Form,+gs: B.Elements,x: Nat) -> Bool:
  +j = x
  B.equal(value(a,gs,j,F.zero()),value(b,gs,j,F.zero()))

def check(p: U.Packing,+gs: B.Elements) -> Bool:
  U.Packed{+ts,ok} = p
  +expected = reference(8n,[])
  ok && F.fits(ts,4n) && eq(ts,expected,gs,0n) && eq(ts,expected,gs,1n)

def projected(+row: X.E3,+g: X.E3,+h: X.E3) -> Bool:
  +coords : B.Elements = [g,h]
  check(U.scan(blocks(),coords,2n,1n,3n,dense(8n,[])),row <> coords)

def live(p: U.Packing) -> Bool:
  U.Packed{_,b} = p
  b

def main() -> IO(Unit):
  +b = blocks()
  # At both endpoint challenges and non-Boolean field points the contracted
  # physical vector must equal direct, tile-by-tile R12.17 evaluation.
  good = projected(F.one(),F.zero(),F.one()) &&
    projected(K.small(7n),X.E3{0,2,0,3,0,5},K.small(11n))
  invalid = Bool.not(live(U.scan(b,[],0n,1n,3n,dense(7n,[F.zero()])))) &&
    Bool.not(live(U.scan(b,[F.one()],1n,1n,3n,dense(7n,[]))))
  IO.print(Bool.show(good && invalid && U.spans(b,0n,8n,2n,8n) && Bool.not(U.spans(b,0n,8n,1n,8n))))

#|True
