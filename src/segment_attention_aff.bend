import Base
import ./u3_cells.bend as Cells
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F
import ./oracle_sample.bend as Sample
import ./key_stage_lookup.bend as Int
import ./key_stage_lookup_rows.bend as L
import ./base_check.bend as B
import ./segment_model.bend as Model

# Sparse affine forms on a segment's U3 and its scalar masks. Cells are linear
# indices in U3. The affine expression is required to be zero.
type Aff is Data:
  Aff{cells: List<&2,Cells.Cell>, masks: L.Masks, constant: X.E3}
type Value is Data:
  Value{shown: X.E3, slot: Nat, factor: X.E3}

def Values() -> Data: List<&2,Value>
def Equations() -> Data: List<&2,Aff>
def const(k: X.E3) -> Aff: Aff{[],[],k}
def zero() -> Aff: const(F.zero())
def hidden(x: Value) -> Aff:
  Value{v,i,b} = x
  Aff{[],[L.Mask{L.Multiplicities{},i,E.negate(b)}],v}

def scaled_cells(+mode: U32, xs: List<&2,Cells.Cell>, +s: X.E3, acc: List<&2,Cells.Cell>) -> List<&2,Cells.Cell>:
  match xs:
    case []: acc
    case Cells.Cell{i,w} <> tail: scaled_cells(mode,tail,s,Cells.Cell{i,E.by(mode,s,w)} <> acc)

def cells(xs: List<&2,Cells.Cell>, +s: X.E3, acc: List<&2,Cells.Cell>) -> List<&2,Cells.Cell>:
  scaled_cells(E.unit(s),xs,s,acc)

def add(sum: Aff, x: Aff, +s: X.E3) -> Aff:
  Aff{a,b,c} = sum
  Aff{d,e,f} = x
  Aff{cells(d,s,a),L.sum(L.scale(e,s),b),E.add(c,E.mul(f,s))}

def minus(a: Aff, b: Aff) -> Aff: add(a,b,E.negate(F.one()))
def plus(a: Aff, b: Aff) -> Aff: add(a,b,F.one())
def scale(x: Aff, s: X.E3) -> Aff: add(zero(),x,s)
def at(vs: Values, i: Nat) -> Value:
  Maybe.default(&2,Value,List.get(&2,Value,vs,i),Value{F.zero(),0n,F.zero()})
def slot(vs: Values, i: Nat) -> Aff: hidden(at(vs,i))
def scalar(v: Value) -> X.E3:
  Value{x,_,_} = v
  x
def nat(n: Nat) -> X.E3: Int.small(n)
def get(xs: B.Elements,i: Nat) -> X.E3: Maybe.default(&2,X.E3,List.get(&2,X.E3,xs,i),F.zero())
def slice(xs: B.Elements, i: Nat, n: Nat) -> B.Elements:
  List.take(&2,X.E3,List.drop(&2,X.E3,xs,i),n)
def rev(xs: B.Elements) -> B.Elements: List.reverse(&2,X.E3,xs)
def size(n: Nat) -> Nat: Nat.pow(2n,n)
def eqp(xs: B.Elements, ys: B.Elements, a: X.E3) -> X.E3:
  match xs ys:
    case Con{+x,rest} Con{y,tail}: eqp(rest,tail,E.mul(a,F.mix(F.sub(F.one(),x),x,y)))
    case _ _: a

# The point is high bit first. An address uses its low len(point) bits.
def eq_low(z: B.Elements,+i: Nat, acc: X.E3) -> X.E3:
  match z:
    case []: acc
    case +x <> rest:
      v = Bool.pick(X.E3,Nat.is_eq(Nat.mod(i,2n),1n),x,F.sub(F.one(),x))
      eq_low(rest,Nat.div(i,2n),E.mul(acc,v))

def eq(xs: B.Elements,i: Nat) -> X.E3: eq_low(rev(xs),i,F.one())

# Adjacent addresses share their high-bit value w. Their weights are w - w*x
# and w*x. The requested interval can start or end in the middle of a pair.
def pairs(ws: B.Elements,+x: X.E3,n: Nat,acc: B.Elements) -> B.Elements:
  match ws n:
    case Con{+w,tail} 1n+0n: rev(F.sub(w,E.mul(w,x)) <> acc)
    case Con{+w,tail} 1n+1n+k:
      +hi = E.mul(w,x)
      pairs(tail,x,k,hi <> F.sub(w,hi) <> acc)
    case _ _: rev(acc)

def children(ws: B.Elements,+x: X.E3,n: Nat,odd: Bool) -> B.Elements:
  match ws n odd:
    case Con{w,tail} 1n+k True{}: pairs(tail,x,k,[E.mul(w,x)])
    case all count _: pairs(all,x,count,[])

def eq_range(low: B.Elements,+first: Nat,n: Nat) -> B.Elements:
  match low n:
    case _ 0n: []
    case Nil{} count: F.fill(count,F.one(),[])
    case Con{x,rest} +count:
      +offset = Nat.mod(first,2n)
      parents = Nat.div(Nat.add(1n+count,offset),2n)
      children(eq_range(rest,Nat.div(first,2n),parents),x,count,Nat.is_eq(offset,1n))
def ones(+xs: B.Elements) -> X.E3: eqp(xs,List.replicate(X.E3,List.length(&2,X.E3,xs),F.one()),F.one())
def sum(xs: B.Elements, a: X.E3) -> X.E3:
  match xs:
    case []: a
    case x <> tail: sum(tail,E.add(x,a))

def powers(n: Nat, +x: X.E3, +acc: X.E3) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k: acc <> powers(k,x,E.mul(acc,x))

def weighted(+values: Values, weights: B.Elements, +step: Nat, +i: Nat, acc: Aff) -> Aff:
  match weights:
    case []: acc
    case w <> tail: weighted(values,tail,step,Nat.add(i,step),add(acc,slot(values,i),w))

def coefficients(xs: List<&2,Cells.Cell>, +bits: Nat, acc: F.Form) -> F.Form:
  Cells.terms(xs,bits,F.one(),acc)

def equation(x: Aff, owner: Nat, n: Nat) -> Model.Aff:
  Aff{cells,masks,c} = x
  Model.Aff{[Model.U3Cells{owner,Cells.Points{cells,Sample.row_bits(n),F.one()}}],masks,E.negate(c)}

def equations(xs: Equations, +owner: Nat, +n: Nat, acc: Model.Equations) -> Model.Equations:
  match xs:
    case []: List.reverse(&2,Model.Aff,acc)
    case x <> tail: equations(tail,owner,n,equation(x,owner,n) <> acc)
