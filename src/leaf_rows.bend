import Base
import ./fold.bend as F
import ./row_tensor.bend as X
import ./sumcheck.bend as E
import ./extension.bend as Ext
import ./goldilocks.bend as Field
import ./base_check.bend as B
import ./hash_bytes.bend as H
import ./record_seeds.bend as Seeds
import ./commitment.bend as Commitment
import ./transcript.bend as T
import ./code_eval.bend as Eval
import ./leaf_shape.bend as S
import ./leaf_stage.bend as L
import ./opening_bytes.bend as O
import ./key_stage_openings.bend as K
import ./pow2.bend as P2

type Layout is Data:
  Layout{table_depth: Nat, ell: Nat, tail: Nat, row_bits: Nat, place_bits: Nat, side_bits: Nat, rows: Nat}

def layout(shape: S.Shape) -> IO(Layout):
  match shape:
    case S.Shape{d,n,r,v,1,_,_,_,+rows,Con{S.Stage{B.Code{_,ell,_},_,_,_},_}}:
      IO.pure(Layout,Layout{U32.to_nat(d),U32.to_nat(n),U32.to_nat(r),U32.to_nat(v),Commitment.variables(U32.from_nat(ell)),Commitment.variables(rows),U32.to_nat(rows)})
    case _: IO.die(Layout,1,"NO: link-layout")

def take_point(n: Nat, stream: T.Stream, acc: B.Elements) -> T.Read<B.Elements>:
  match n:
    case 0n: T.Read{List.reverse(&2,Ext.E3,acc),stream}
    case 1n+k:
      +got = T.element(stream)
      take_point(k,T.after(Ext.E3,got),T.value(Ext.E3,got) <> acc)

def theta(t: Nat) -> Ext.E3:
  match t:
    case 0n: F.one()
    case 1n: Ext.E3{0,0,0,1,0,0}
    case _: Ext.E3{0,0,0,0,0,1}

def place(terms: F.Form, +layout: Layout, side: X.Member) -> F.Form:
  Layout{_,_,_,_,+p,b,_} = layout
  X.rows_high(X.extend(terms,Nat.add(b,p),0n),p,side)

def packed(raw: H.Bytes) -> B.Elements:
  B.elements(H.u32s(raw),[])

def basis_pads(n: Nat, +end: Nat, +bits: Nat, +beta: Ext.E3) -> F.Form:
  match n:
    case 0n: []
    case 1n+k:
      +i = k
      F.Term{E.mul(beta,theta(i)),X.choice(bits,Nat.add(end,i))} <> basis_pads(i,end,bits,beta)

def combine(gs: B.Elements, xs: B.Elements) -> IO(Ext.E3):
  match gs:
    case []:
      match xs:
        case [v]: IO.pure(Ext.E3,v)
        case _: IO.die(Ext.E3,1,"NO: link-column-width")
    case g <> tail: combine(tail,F.pairs(xs,g,[]))

def record_form(+layout: Layout, side: X.Member, +seeds: B.Elements) -> IO(F.Form):
  Layout{_,+ell,_,_,_,_,_} = layout
  +width = Commitment.variables(U32.from_nat(ell))
  +cut = Nat.sub(ell,3n)
  fs = X.eq(List.take(&2,Ext.E3,seeds,width))
  do IO<F.Form>:
    beta : Ext.E3 <- K.need(Ext.E3,List.get(&2,Ext.E3,seeds,width),"NO: record-seed")
    return place(List.append(&2,F.Term,X.below(fs,cut,F.one()),basis_pads(3n,cut,width,beta)),layout,side)

def record_seeds(shape: S.Shape, config: H.Bytes, root: H.Bytes) -> B.Elements:
  S.Shape{d,+n,r,v,count,salt,_,_,_,_} = shape
  name = H.cat([root,config,H.word(d),H.word(n),H.word(r),H.word(v),H.word(count),H.word(salt)])
  packed(Seeds.sample(name,Commitment.variables(n)))

type Row is Data:
  Row{form: F.Form, target: Ext.E3}

def record(table: L.Table, side: X.Member, shape: S.Shape, layout: Layout, config: H.Bytes, gamma: B.Elements) -> IO(Row):
  L.Table{root,raw} = table
  do IO<Row>:
    form : F.Form <- record_form(layout,side,record_seeds(shape,config,O.digest_bytes(root)))
    value : Ext.E3 <- combine(gamma,packed(raw))
    return Row{form,value}

def equality(+layout: Layout, phi: B.Elements) -> Row:
  Layout{_,+ell,_,_,_,_,_} = layout
  +form = X.below(X.eq(phi),Nat.sub(ell,3n),F.one())
  Row{X.scale(place(form,layout,X.Right{}),E.negate(F.one()),place(form,layout,X.Left{})),F.zero()}

def sample(+layout: Layout, side: X.Member, +fs: F.Factors, beta: Ext.E3, answer: Ext.E3) -> Row:
  Layout{_,_,_,_,+p,+b,rows} = layout
  pad = Nat.add(Nat.mul(Nat.sub(P2.pow2(p),1n),P2.pow2(b)),Nat.sub(rows,1n))
  +i = pad
  delta = F.sub(beta,X.entry(fs,i,F.one()))
  Row{X.side_bit([F.Term{F.one(),fs},F.Term{delta,X.choice(Nat.add(b,p),i)}],b,side),answer}

def pow_bits(k: Nat, +n: Nat, +z: Field.Gl, +acc: Field.Gl) -> Field.Gl:
  match k:
    case 0n: acc
    case 1n+p:
      next = Bool.pick(Field.Gl,Nat.is_eq(Nat.mod(n,2n),0n),acc,Ext.product(acc,z))
      pow_bits(p,Nat.div(n,2n),Ext.product(z,z),next)

def generator(+layout: Layout, side: X.Member, +z: Field.Gl) -> F.Form:
  Layout{_,+ell,+r,_,p,b,_} = layout
  +width = Commitment.variables(U32.from_nat(ell))
  +rt = Commitment.variables(U32.from_nat(r))
  +stride = P2.pow2(rt)
  prefix = Nat.div(Nat.add(ell,Nat.sub(stride,1n)),stride)
  tail = X.extend(X.below(X.powers(rt,z),r,F.one()),Nat.add(p,b),prefix)
  msg = X.below(X.powers(width,z),ell,X.scalar(pow_bits(32n,r,z,Field.Gl{0,1})))
  place(List.append(&2,F.Term,msg,tail),layout,side)

def column(places: O.Columns, +pos: Nat) -> Maybe<&2,H.Bytes>:
  match places:
    case []: None{}
    case O.Column{i,bytes} <> rest:
      Bool.pick(Maybe<&2,H.Bytes>,Nat.is_eq(i,pos),Some{bytes},column(rest,pos))

def lift(words: H.Bytes) -> B.Elements:
  match words:
    case l <> h <> tail: Ext.E3{h,l,0,0,0,0} <> lift(tail)
    case _: []

type Batch is Data:
  Batch{theta: Ext.E3, power: Ext.E3, form: F.Form, target: Ext.E3}

def add(row: Row, state: Batch) -> Batch:
  Row{form,value} = row
  Batch{+t,+w,acc,target} = state
  Batch{t,E.mul(t,w),X.scale(form,w,acc),E.add(target,E.mul(w,value))}

def columns(draws: O.Places, +available: O.Columns, +layout: Layout, +side: X.Member, +gamma: B.Elements, state: Batch) -> IO(Batch):
  match draws:
    case []: IO.pure(Batch,state)
    case +pos <> rest:
      Layout{depth,_,_,_,_,_,_} = layout
      do IO<Batch>:
        z : Field.Gl <- K.need(Field.Gl,Eval.point(depth,pos),"NO: link-column-code")
        raw : H.Bytes <- K.need(H.Bytes,column(available,pos),"NO: link-column")
        y : Ext.E3 <- combine(gamma,lift(raw))
        columns(rest,available,layout,side,gamma,add(Row{generator(layout,side,z),y},state))
