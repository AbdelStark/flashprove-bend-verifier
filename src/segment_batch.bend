import Base
import ./outer_source.bend as O
import ./segment_outer.bend as Outer
import ./segment_projection.bend as Project
import ./u3_series.bend as U
import ./smallness.bend as Small
import ./smallness_form.bend as SF
import ./smallness_geometry.bend as Geo
import ./segment_model.bend as M
import ./segment_layout.bend as Layout
import ./key_stage_lookup_rows.bend as L
import ./key_stage_lookup.bend as KL
import ./key_stage_openings.bend as K
import ./base_check.bend as B
import ./fold.bend as F
import ./fold_frame.bend as Frame
import ./fold_request_shape.bend as Q
import ./sumcheck.bend as E
import ./row_tensor.bend as V
import ./extension.bend as X
import ./header.bend as H
import ./oracle_sample.bend as S

# R13.4, R11.1. Retain one batched row per local segment. Array names and
# owners may refer to unreleased messages of previous segments under R12.17.
type State is Type:
  State{reads: List<&2,M.Read>, mask: Array<X.E3>, rhs: X.E3, power: X.E3}
type Row is Data:
  Row{reads: List<&2,M.Read>, mask: B.Elements, target: X.E3}

def scaled(ts: List<&2,M.Read>,+power: X.E3,acc: List<&2,M.Read>) -> List<&2,M.Read>:
  match ts:
    case []: acc
    case M.OuterRead{id,n,s} <> rest: scaled(rest,power,M.OuterRead{id,n,O.scaled(s,power)} <> acc)
    case M.U3Run{id,s} <> rest: scaled(rest,power,M.U3Run{id,U.scaled(s,power)} <> acc)
    case M.Read{link,name,terms} <> rest:
      scaled(rest,power,M.Read{link,name,V.scale(terms,power,[])} <> acc)

def updated(pair: Array<X.E3> & X.E3,i: U32,k: X.E3) -> Array<X.E3>:
  (buf,old) = pair
  Array.set(X.E3,buf,i,E.add(old,k))

def masked(ms: L.Masks,+power: X.E3,+slots: Nat,buf: Array<X.E3>) -> IO(Array<X.E3>):
  match ms:
    case []: IO.pure(Array<X.E3>,buf)
    case L.Mask{L.Multiplicities{},+slot,v} <> tail:
      +j = U32.from_nat(slot)
      do IO<Array<X.E3>>:
        ok : Unit <- H.require(Nat.is_lt(slot,slots),"NO: segment-mask-slot")
        masked(tail,power,slots,updated(Array.get(X.E3,buf,j),j,E.mul(power,v)))
    case _: IO.die(Array<X.E3>,1,"NO: segment-mask-oracle")

def add(row: M.Aff,st: State,chi: X.E3,slots: Nat) -> IO(State):
  M.Aff{r,m,v} = row
  State{terms,buf,target,+p} = st
  do IO<State>:
    next : Array<X.E3> <- masked(m,p,slots,buf)
    return State{scaled(r,p,terms),next,E.add(target,E.mul(v,p)),E.mul(p,chi)}

def batch(rows: M.Equations,st: State,+chi: X.E3,+slots: Nat) -> IO(State):
  match rows:
    case []: IO.pure(State,st)
    case row <> tail:
      do IO<State>:
        next : State <- add(row,st,chi,slots)
        batch(tail,next,chi,slots)

def weighted(row: M.Aff,st: State) -> IO(State):
  match row st:
    case M.Aff{rs,[],v} State{old,buf,y,p}: IO.pure(State,State{F.cat(M.Read,rs,old),buf,E.add(y,v),p})
    case _ _: IO.die(State,1,"NO: structured-smallness-masks")

def structured(rows: M.Equations,st: State) -> IO(State):
  match rows:
    case []: IO.pure(State,st)
    case row <> tail:
      do IO<State>:
        next : State <- weighted(row,st)
        structured(tail,next)

def powers(st: State,p: X.E3) -> State:
  State{reads,mask,t,_} = st
  State{reads,mask,t,p}

def is_free(free: Maybe<&2,Nat>,pos: Nat) -> Bool:
  match free:
    case None{}: False{}
    case Some{j}: Nat.is_eq(j,pos)

def coverage(mask: B.Elements,+free: Maybe<&2,Nat>,pos: Nat) -> Bool:
  match mask:
    case []: True{}
    case +z <> tail:
      +i = pos
      Bool.pick(Bool,is_free(free,i),B.equal(z,F.zero()),Bool.not(B.equal(z,F.zero()))) && coverage(tail,free,1n+i)

def read_buf(n: Nat,xs: List<X.E3>,acc: B.Elements) -> B.Elements:
  match n xs:
    case 1n+k x <> more: read_buf(k,more,x <> acc)
    case _ _: List.reverse(&2,X.E3,acc)

def finish(st: State,slots: Nat,free: Maybe<&2,Nat>) -> IO(Row):
  State{r,buf,y,_} = st
  +v = read_buf(slots,Array.to_list(X.E3,buf),[])
  do IO<Row>:
    ok : Unit <- H.require(coverage(v,free,0n),"NO: segment-free-slot")
    return Row{r,v,y}

def combine(+prefix: M.Equations,suffix: M.Equations,part: Small.Contribution,+slots: Nat,free: Maybe<&2,Nat>) -> IO(Row):
  Small.Contribution{ds,ts,r,n,+chi} = part
  shift = KL.power(32n,Nat.add(List.length(&2,M.Aff,prefix),n),chi,F.one())
  do IO<Row>:
    a : State <- batch(prefix,State{[],Array.new(X.E3,S.row_bits(slots),F.zero()),F.zero(),F.one()},chi,slots)
    b : State <- batch(ds,a,chi,slots)
    c : State <- structured(ts,b)
    e : State <- weighted(r,c)
    last : State <- batch(suffix,powers(e,shift),chi,slots)
    finish(last,slots,free)

def place(rs: List<&2,M.Read>,+layout: Layout.Book,+shape: Q.Shape,+basis: Maybe<&2,Project.Basis>,acc: Frame.Forms) -> IO(Frame.Forms):
  match rs:
    case []: IO.pure(Frame.Forms,acc)
    case M.OuterRead{+owner,name,source} <> tail:
      do IO<Frame.Forms>:
        table : Layout.Matrix <- Layout.lookup(Map.get(Maybe<&2,Layout.Matrix>,None{},layout,Layout.key(owner,name)))
        on : Frame.On <- Outer.located(shape,table,source,owner,basis)
        place(tail,layout,shape,basis,on <> acc)
    case M.U3Run{owner,s} <> tail:
      do IO<Frame.Forms>:
        on : Frame.On <- Layout.on_main(layout,shape,owner,"U3",U.expand(s))
        place(tail,layout,shape,basis,on <> acc)
    case M.Read{owner,name,terms} <> tail:
      do IO<Frame.Forms>:
        on : Frame.On <- Layout.on_main(layout,shape,owner,name,terms)
        place(tail,layout,shape,basis,on <> acc)

def mask_member(ns: Q.Notices) -> IO(Nat):
  match ns:
    case Q.Notice{Frame.Member{id,_,_,0n,_},_,_} <> tail: mask_member(tail)
    case Q.Notice{Frame.Member{id,_,_,1n,_},_,_} <> _: IO.pure(Nat,id)
    case _: IO.die(Nat,1,"NO: segment-mask-member")

def mask_label(link: Q.Link) -> IO(Nat):
  Q.Link{_,ns} = link
  mask_member(ns)

def physical(shape: Q.Shape,layout: Layout.Book,link: Nat,row: Row,basis: Maybe<&2,Project.Basis>) -> IO(Frame.Equation):
  Q.Shape{c,+m,+links,stages} = shape
  Row{rs,v,y} = row
  do IO<Frame.Equation>:
    l : Q.Link <- K.need(Q.Link,List.get(&2,Q.Link,links,link),"NO: segment-link")
    id : Nat <- mask_label(l)
    on : Frame.Forms <- place(rs,layout,Q.Shape{c,m,links,stages},basis,[])
    return Frame.Equation{Frame.On{id,True{},SF.dense(v,[],Layout.columns(m),0n,F.one(),[])} <> on,y}
