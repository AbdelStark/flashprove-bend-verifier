import Base
import ../src/segment_transport.bend as Transport
import ../src/segment_projection.bend as P
import ../src/fold_frame.bend as R
import ../src/fold_carry.bend as C
import ../src/fold.bend as F
import ../src/fold_cs.bend as CS
import ../src/base_check.bend as B
import ../src/extension.bend as X
import ../src/key_stage_lookup.bend as K
import ../src/row_tensor.bend as T

# R12.16 main-row transfer followed by the actual terminal column folds.
# Compare every terminal BASE coefficient to generic placement, BAT and FOLD.
# The carrier moves between aligned offsets 4 and 6, with retained and
# nonretained members. The projection includes gamma=0, gamma=1, cancellations
# and non-base-field weights.
def group(reverse: Bool) -> R.Members:
  +g: R.Member = R.Member{0n,2n,3n,0n,False{}}
  +other: R.Member = R.Member{1n,2n,3n,0n,False{}}
  +big: R.Member = R.Member{2n,4n,3n,0n,False{}}
  +kept: R.Member = R.Member{3n,8n,1n,0n,True{}}
  Bool.pick(R.Members,reverse,[other,g,big,kept],[g,other,big,kept])

def factor(a: Nat,b: Nat) -> F.Factor: F.Factor{K.small(a),K.small(b)}

def source() -> F.Form:
  ext: X.E3 = X.E3{0,4,0,3,0,2}
  [F.Term{ext,[factor(1n,2n),factor(5n,0n),factor(3n,7n),factor(11n,13n)]},
    F.Term{K.small(31n),T.choice(4n,5n)}]

def main_of(value: Maybe<&2,R.Group>,gs: B.Elements,epsilon: X.E3) -> F.Form:
  match value:
    case Some{R.Group{m,_,_,_}}: F.fixed(m,gs,epsilon)
    case _: []

def conventional(old: F.Form,members: R.Members,gs: B.Elements,epsilon: X.E3) -> F.Form:
  carry: R.Equation = R.Equation{[R.On{0n,False{},C.on_row(old,0n)}],F.zero()}
  local: R.Equation = R.Equation{[R.On{2n,False{},R.insert(source(),0n,2n,3n,[])}],F.zero()}
  lay: R.Layout = R.Layout{members,3n,0n,4n,0n}
  assembled = R.grouped(lay,R.batch([carry,local],K.small(17n),R.Batched{[],F.zero(),F.one()}))
  main_of(assembled,gs,epsilon)

def same(a: B.Elements,b: B.Elements) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{v,xs} Con{w,ys}: B.equal(v,w) && same(xs,ys)
    case _ _: False{}

def check(+coords: B.Elements) -> Bool:
  +p: P.Basis = P.Basis{coords,2n,2n}
  +u: B.Elements = [K.small(3n),K.small(5n),K.small(7n)]
  +v: B.Elements = [K.small(2n),F.zero(),F.one()]
  +a = group(False{})
  +b = group(True{})
  old = conventional(source(),a,u,K.small(11n))
  all = conventional(old,b,v,K.small(13n))
  expected = F.expand(F.fixed(all,coords,F.one()),CS.zeros(4n))
  start = P.merge(p,source(),P.zeros(p),F.zero())
  first = P.merge(p,conventional([],a,u,K.small(11n)),start,Transport.multiplier(a,u,K.small(11n)))
  +saved = P.merge(p,conventional([],b,v,K.small(13n)),first,Transport.multiplier(b,v,K.small(13n)))
  actual = F.expand(F.fixed(P.lift(p,saved),coords,F.one()),CS.zeros(4n))
  same(actual,saved) && same(saved,expected)

# The ordinary and terminal challenge lists fix adjacent axes. Compare the
# single scatter to the two explicit folds with a nonempty previous carry.
def fused(+eps: X.E3) -> Bool:
  +basis: P.Basis = P.Basis{[F.one(),F.zero()],2n,2n}
  +coords: B.Elements = [F.zero(),X.E3{0,4,0,2,0,3},F.one()]
  +local = R.insert(source(),0n,3n,5n,[])
  +old: B.Elements = [F.one(),F.zero(),K.small(3n),K.small(5n)]
  +carry = K.small(17n)
  same(Transport.contract(basis,coords,local,old,carry,eps),P.merge(basis,F.fixed(local,coords,eps),old,carry))

# Deferred updates apply the older scalar first. Include a zero carry and
# non-base-field carries so reversing, dropping or repeating an update
# changes the resulting table. Five updates split unevenly in the fork tree.
def queued() -> Bool:
  +basis: P.Basis = P.Basis{[F.one(),F.zero()],2n,2n}
  +old: B.Elements = [F.one(),K.small(7n),F.zero(),K.small(13n)]
  +a: Transport.Update = Transport.Update{[],source(),F.zero(),K.small(11n)}
  +b: Transport.Update = Transport.Update{[],source(),X.E3{0,7,0,5,0,3},K.small(17n)}
  +c: Transport.Update = Transport.Update{[],source(),K.small(19n),X.E3{0,2,0,9,0,4}}
  +d: Transport.Update = Transport.Update{[],source(),X.E3{0,1,0,0,0,6},K.small(23n)}
  +e: Transport.Update = Transport.Update{[],source(),K.small(3n),F.one()}
  +ab = Transport.commit_one(basis,Transport.commit_one(basis,old,a),b)
  eager = Transport.commit_one(basis,Transport.commit_one(basis,Transport.commit_one(basis,ab,c),d),e)
  same(ab,Transport.finish_columns(basis,Transport.Deferred{old,[b,a]})) &&
    same(eager,Transport.finish_columns(basis,Transport.Deferred{old,[e,d,c,b,a]})) &&
    same(old,Transport.finish_columns(basis,Transport.Deferred{old,[]}))

def main() -> IO(Unit):
  IO.print(Bool.show(check([K.small(23n),K.small(29n)]) && check([F.one(),F.zero()]) && fused(F.zero()) && fused(K.small(7n)) && queued()))

#|True
