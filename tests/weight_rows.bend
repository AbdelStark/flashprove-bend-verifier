import Base
import ../src/weight_types.bend as G
import ../src/weight_rows.bend as Rows
import ../src/row_tensor.bend as T
import ../src/base_check.bend as B
import ../src/fold.bend as F
import ../src/sumcheck.bend as E
import ../src/extension.bend as X

def elem(n: U32) -> X.E3: X.E3{0,n,0,0,0,0}

def at(xs: F.Form, +n: Nat, acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case F.Term{w,fs} <> tail: at(tail,n,E.add(acc,T.entry(fs,n,w)))

def agrees(ws: B.Elements, +terms: F.Form, i: Nat) -> Bool:
  match ws:
    case []: True{}
    case w <> tail:
      +n = i
      B.equal(w,at(terms,n,F.zero())) && agrees(tail,terms,1n+n)

def main() -> IO(Unit):
  # The expected table sums each of 16 explicit Boolean columns per row.
  gs: List<&2,G.Group> = [G.Group{"v",G.A{},False{},3n,0n,0n,2n,0n,1n},G.Group{"x",G.E{},True{},12n,3n,2n,1n,2n,6n},
    G.Group{"h",G.A{},False{},3n,0n,0n,0n,3n,3n}]
  us: List<&2,G.WeightUnit> = [G.WeightUnit{0n,0n,2n,3n,3n,36n,gs}]
  c: G.Claim = G.Claim{0n,0n,[G.ArrayFactor{[elem(3),elem(5),elem(7)]},G.Equality{[elem(19),elem(23)],[elem(11),elem(13),elem(17)]},
    G.ArrayFactor{[elem(29),elem(31),elem(37)]}],0n,F.zero(),F.zero()}
  do IO<Unit>:
    terms : F.Form <- Rows.claim(G.Layout{4n,64n,us},c,[elem(2),elem(3),elem(5),elem(7)],F.one(),[])
    IO.print(Bool.show(agrees([
      F.zero(),F.zero(),F.zero(),X.E3{4294967294,4050185837,0,0,0,0},
      X.E3{0,258380430,0,0,0,0},X.E3{4294967294,4005680117,0,0,0,0},X.E3{0,305358690,0,0,0,0},X.E3{4294967294,3916668677,0,0,0,0},
      X.E3{0,399315210,0,0,0,0},X.E3{4294967294,4033304357,0,0,0,0},X.E3{0,276199770,0,0,0,0},X.E3{4294967294,3985729277,0,0,0,0},
      X.E3{0,326417910,0,0,0,0},X.E3{4294967294,3890579117,0,0,0,0},X.E3{0,426854190,0,0,0,0},X.E3{4294967294,3982659917,0,0,0,0},
      X.E3{0,329657790,0,0,0,0},X.E3{4294967294,3925876757,0,0,0,0},X.E3{0,389595570,0,0,0,0},X.E3{4294967294,3812310437,0,0,0,0},
      X.E3{0,509471130,0,0,0,0},X.E3{4294967280,1760455681,0,0,0,0},X.E3{15,1720880640,0,0,0,0},X.E3{4294967277,3251893249,0,0,0,0},
      X.E3{18,862413312,0,0,0,0},X.E3{4294967272,1939801089,0,0,0,0},X.E3{23,3440445952,0,0,0,0},X.E3{4294967279,1733764097,0,0,0,0},
      X.E3{16,1987664384,0,0,0,0},X.E3{4294967276,2439445505,0,0,0,0},X.E3{19,1958606336,0,0,0,0},X.E3{4294967270,3850808321,0,0,0,0},
      X.E3{25,1900490240,0,0,0,0},X.E3{4294967276,1653689345,0,0,0,0},X.E3{19,2788015616,0,0,0,0},X.E3{4294967273,2102273,0,0,0,0},
      X.E3{23,952218112,0,0,0,0},X.E3{4294967266,993895425,0,0,0,0},X.E3{30,1575590400,0,0,0,0},F.zero(),
      F.zero(),F.zero(),F.zero(),F.zero(),
      F.zero(),F.zero(),F.zero(),F.zero(),
      F.zero(),F.zero(),F.zero(),F.zero(),
      F.zero(),F.zero(),F.zero(),F.zero(),
      F.zero(),F.zero(),F.zero(),F.zero(),
      F.zero(),F.zero(),F.zero(),F.zero()],terms,0n)))
#|True
