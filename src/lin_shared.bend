import Base
import ./plan.bend as P
import ./fold_verify.bend as FV
import ./lin_run.bend as Run
import ./lin_shape.bend as Lin
import ./leaf_shape.bend as S
import ./leaf_stage.bend as L
import ./leaf_rows.bend as Rows
import ./fold_open.bend as Open
import ./fold_cs.bend as CS
import ./fold.bend as F
import ./row_tensor.bend as X
import ./oracle_sample.bend as Sample
import ./key_stage_trace.bend as Tr
import ./key_stage_openings.bend as K
import ./base_check.bend as B
import ./hash_bytes.bend as H
import ./transcript.bend as T
import ./opening_bytes.bend as O
import ./sumcheck.bend as E
import ./extension.bend as Ext
import ./header.bend as Header

type Group is Data:
  Group{stages: List<&2,S.Stage>, rows: Nat, ell: Nat, masks: Nat, k: Nat, h: Nat}

def group(+stages: List<&2,S.Stage>, n: U32) -> IO(Group):
  match stages:
    case S.Stage{B.Code{_,ell,_},B.Code{_,m,_},k,h} <> _:
      IO.pure(Group,Group{stages,U32.to_nat(n),ell,m,U32.to_nat(k),U32.to_nat(h)})
    case _: IO.die(Group,1,"NO: lin-codes")

def absent() -> Sample.Part:
  Sample.Part{0n,0n,0n,0n}

def main_sample(group: Group, seed: Sample.Seed, y: Ext.E3) -> IO(Sample.Sample):
  Group{_,n,ell,_,k,_} = group
  K.need(Sample.Sample,Sample.single(Sample.Member{Sample.Part{n,ell,k,0n},absent(),False{}},seed,y),"NO: lin-send-main")

def mask_sample(group: Group, seed: Sample.Seed, y: Ext.E3) -> IO(Sample.Sample):
  Group{_,_,_,m,_,h} = group
  K.need(Sample.Sample,Sample.single(Sample.Member{absent(),Sample.Part{1n,m,h,0n},False{}},seed,y),"NO: lin-send-mask")

type Inputs is Data:
  Inputs{psi: B.Elements, u_seed: Sample.Seed, u_y: Ext.E3, places: O.Places, opened: O.Columns,
    omega_seed: Sample.Seed, omega_y: Ext.E3, split_y: Ext.E3, zeta: B.Elements, share: Ext.E3}

def one(e: Tr.Observed) -> IO(Ext.E3):
  K.need(Ext.E3,FV.value(Run.message(e)),"NO: lin-element")

def seed(+e: Tr.Observed) -> IO(Sample.Seed):
  Tr.Observed{P.Round{_,_,_,_,_,_,n,nz,_,_,_,_},_,_,_,_} = e
  do IO<Sample.Seed>:
    ok : Unit <- Header.require(U32.is_eq(nz,1) && U32.is_ge(n,1) && U32.is_le(n,64),"NO: lin-seed-width")
    return Sample.point(U32.to_nat(U32.sub(n,1)),Run.stream(e),[])

def point(+e: Tr.Observed) -> B.Elements:
  Tr.Observed{P.Round{_,_,_,_,_,_,n,_,_,_,_,_},_,_,_,_} = e
  T.value(B.Elements,Rows.take_point(U32.to_nat(n),Run.stream(e),[]))

type Both is Data:
  Both{a: Ext.E3,b: Ext.E3}

def left(ys: Both) -> Ext.E3:
  Both{x,_} = ys
  x

def right(ys: Both) -> Ext.E3:
  Both{_,y} = ys
  y

def both(a: B.Elements) -> IO(Both):
  match a:
    case [x,y]: IO.pure(Both,Both{x,y})
    case _: IO.die(Both,1,"NO: lin-shared-samples")

type UInput is Data:
  UInput{psi: B.Elements, seed: Sample.Seed, y: Ext.E3, places: O.Places, opening: O.Columns}

def assemble(first: UInput, omega: Sample.Seed, +ys: Both, zeta: B.Elements, share: Ext.E3) -> Inputs:
  UInput{psi,s,y,xs,cols} = first
  Inputs{psi,s,y,xs,cols,omega,left(ys),right(ys),zeta,share}

def remaining(xs: Tr.Events, u: UInput) -> IO(Inputs & Tr.Events):
  match xs:
    case +e <> +f <> +g <> +h <> tail:
      ok = String.eq(Run.name(e),"SEND seed") && String.eq(Run.name(f),"SEND answer") &&
        String.eq(Run.name(g),"LIN zeta") && String.eq(Run.name(h),"SPLIT")
      do IO<Inputs & Tr.Events>:
        valid : Unit <- Header.require(ok,"NO: lin-omega-rounds")
        om : Sample.Seed <- seed(e)
        ys : Both <- both(Rows.packed(Run.message(f)))
        share : Ext.E3 <- one(h)
        return (assemble(u,om,ys,point(g),share),tail)
    case _: IO.die(Inputs & Tr.Events,1,"NO: lin-omega-rounds")

def prefix(xs: Tr.Events) -> IO(Inputs & Tr.Events):
  match xs:
    case +a <> +b <> +c <> +d <> tail:
      ok = String.eq(Run.name(a),"LIN point") && String.eq(Run.name(b),"SEND seed") &&
        String.eq(Run.name(c),"SEND answer") && String.eq(Run.name(d),"LOC")
      do IO<Inputs & Tr.Events>:
        valid : Unit <- Header.require(ok,"NO: lin-table-rounds")
        us : Sample.Seed <- seed(b)
        uy : Ext.E3 <- one(c)
        remaining(tail,UInput{point(a),us,uy,Run.draws(d),Run.head(Run.columns(d))})
    case _: IO.die(Inputs & Tr.Events,1,"NO: lin-table-rounds")

def row(sample: Sample.Sample) -> Rows.Row:
  Sample.Sample{main,_,t} = sample
  Rows.Row{main,t}

def mask(sample: Sample.Sample) -> F.Form:
  Sample.Sample{_,terms,_} = sample
  terms

def split_mask(group: Group, weight: Ext.E3, answer: Sample.Sample, sample_scale: Ext.E3) -> B.Elements:
  Group{_,_,_,ell,_,h} = group
  +bits = Nat.add(CS.bits(ell),h)
  terms = X.scale(mask(answer),sample_scale,[F.Term{weight,X.choice(bits,0n)}])
  F.expand(terms,CS.zeros(CS.size(bits)))

def claim(batch: Rows.Batch, weights: B.Elements) -> F.Claim:
  Rows.Batch{_,_,main,target} = batch
  F.Claim{main,weights,target}

def product(low: F.Factors, terms: F.Form) -> F.Form:
  match terms:
    case []: []
    case F.Term{w,f} <> rest:
      +ls = low
      F.Term{w,List.append(&2,F.Factor,ls,f)} <> product(ls,rest)

def folded(+shape: Lin.Shape, +u: Group, +x: Inputs, table: L.Table, cfg: H.Bytes, +t: Ext.E3) -> IO(F.Claim):
  Lin.Shape{+stored,+low,+matrix,_,_,_,_} = shape
  Inputs{+psi,us,uy,draws,cols,oms,_,sy,zeta,share} = x
  +gamma = List.drop(&2,Ext.E3,psi,low)
  neg = E.negate(F.one())
  coefs = product(X.eq(List.take(&2,Ext.E3,psi,low)),X.below(X.eq(zeta),matrix,neg))
  do IO<F.Claim>:
    +layout : Rows.Layout <- Rows.layout(stored)
    record : Rows.Row <- Rows.record(table,X.Only{},stored,layout,cfg,gamma)
    mine : Sample.Sample <- main_sample(u,us,uy)
    +split : Sample.Sample <- mask_sample(u,oms,sy)
    plain : Rows.Batch = Rows.add(Rows.Row{Rows.place(coefs,layout,X.Only{}),E.negate(share)},Rows.add(record,Rows.Batch{t,F.one(),[],F.zero()}))
    before : Rows.Batch = Rows.add(row(split),Rows.add(row(mine),plain))
    result : Rows.Batch <- Rows.columns(draws,cols,layout,X.Only{},gamma,before)
    return claim(result,split_mask(u,E.negate(t),split,E.mul(t,E.mul(t,t))))

def omega(+group: Group, matrix: Nat, +x: Inputs, +t: Ext.E3) -> IO(F.Claim):
  Group{_,+n,ell,_,_,_} = group
  Inputs{_,_,_,_,_,+s,y,sy,zeta,share} = x
  +places = CS.bits(ell)
  width = Nat.add(places,Sample.row_bits(n))
  on_table = X.rows_high(X.extend(X.below(X.eq(zeta),matrix,F.one()),width,0n),places,X.Only{})
  do IO<F.Claim>:
    mine : Sample.Sample <- main_sample(group,s,y)
    +split : Sample.Sample <- mask_sample(group,s,sy)
    first : Rows.Batch = Rows.add(Rows.Row{on_table,share},Rows.Batch{t,F.one(),[],F.zero()})
    return claim(Rows.add(row(split),Rows.add(row(mine),first)),split_mask(group,F.one(),split,E.mul(t,t)))

type Adopted is Data:
  Adopted{psi: B.Elements, omega_seed: Sample.Seed, omega_y: Ext.E3, shape: Lin.Shape}

def end(events: Tr.Events) -> Bool:
  match events:
    case [e]: String.eq(Run.name(e),"SEAL")
    case _: False{}

def groups(begin: Inputs & Tr.Events, +shape: Lin.Shape, table: L.Table, cfg: H.Bytes) -> IO(Adopted):
  (+x,events) = begin
  Inputs{psi,_,_,_,_,seed,y,_,_,_} = x
  Lin.Shape{S.Shape{_,_,_,_,_,_,_,_,+n,+us},_,matrix,Lin.Side{_,_,+m,_},_,+oms,_} = shape
  do IO<Adopted>:
    +fold : Group <- group(us,n)
    +om : Group <- group(oms,m)
    +a : Run.Group <- Run.group(events)
    ca : F.Claim <- folded(shape,fold,x,table,cfg,Run.theta(a))
    rest : Tr.Events <- Run.verify(a,Open.Folded{U32.to_nat(n)},us,ca)
    +b : Run.Group <- Run.group(rest)
    cb : F.Claim <- omega(om,matrix,x,Run.theta(b))
    closed : Tr.Events <- Run.verify(b,Open.Omega{U32.to_nat(m)},oms,cb)
    ok : Unit <- Header.require(end(closed),"NO: lin-seal")
    return Adopted{psi,seed,y,shape}

def check(events: Tr.Events, items: List<&2,P.Item>, table: L.Table, config: H.Bytes) -> IO(Adopted):
  do IO<Adopted>:
    shape : Lin.Shape <- Lin.load(items)
    inps : Inputs & Tr.Events <- prefix(events)
    groups(inps,shape,table,config)
