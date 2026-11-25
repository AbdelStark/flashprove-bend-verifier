import Base
import ./leaf_shape.bend as S
import ./lin_shape.bend as Lin
import ./lin_shared.bend as Shared
import ./lin_run.bend as Run
import ./lin_projection.bend as Project
import ./key_stage_openings.bend as K
import ./key_stage_trace.bend as Tr
import ./fold_open.bend as Open
import ./fold_cs.bend as CS
import ./sumcheck.bend as A
import ./header.bend as Header
import ./row_tensor.bend as X
import ./extension.bend as E
import ./fold.bend as F
import ./base_check.bend as B
import ./oracle_sample.bend as Sample

type Slot is Data:
  Slot{index: Nat, coefficient: E.E3}

type Pending is Data:
  Pending{weights: F.Form, psi: B.Elements, masks: List<&2,Slot>, target: E.E3}

type Opened is Data:
  Opened{index_seed: Sample.Seed, index_y: E.E3, w_seed: Sample.Seed, w_y: E.E3}

type First is Data:
  First{pending: Pending, opened: Opened}

type Geometry is Data:
  Geometry{stages: List<&2,S.Stage>, w: Nat, masks: Nat, omega: Nat, ell: Nat, ell_mask: Nat, k: Nat, h: Nat}

def return_geometry(ss: List<&2,S.Stage>, w: Nat, m: Nat, n: Nat, a: Nat, b: Nat, k: Nat, h: Nat) -> IO(Geometry):
  IO.pure(Geometry,Geometry{ss,w,m,n,a,b,k,h})

def geometry(ss: List<&2,S.Stage>, w: U32, masks: U32, omega: U32) -> IO(Geometry):
  match ss:
    case +s <> tail:
      S.Stage{B.Code{_,ell,_},B.Code{_,ell_mask,_},k,h} = s
      return_geometry(s <> tail,U32.to_nat(w),U32.to_nat(masks),U32.to_nat(omega),ell,ell_mask,U32.to_nat(k),U32.to_nat(h))
    case _: IO.die(Geometry,1,"NO: lin-own-stages")

# Source coordinates are [place, member row]. A shorter term fixes its missing
# high bits to zero. Group coordinates are [member row, group prefix, place].
def place_factors(n: Nat, fs: F.Factors, +zero: F.Factor) -> F.Factors:
  match n fs:
    case 0n _: []
    case 1n+k Con{f,rest}: f <> place_factors(k,rest,zero)
    case 1n+k Nil{}: zero <> place_factors(k,[],zero)

def row_factors(n: Nat, fs: F.Factors, prefix: F.Factors, places: F.Factors, +zero: F.Factor) -> F.Factors:
  match n fs:
    case 0n rest: List.append(&2,F.Factor,prefix,List.append(&2,F.Factor,rest,places))
    case 1n+k Con{f,rest}: f <> row_factors(k,rest,prefix,places,zero)
    case 1n+k Nil{}: zero <> row_factors(k,[],prefix,places,zero)

def layout(terms: F.Form, +cols: Nat, +rows: Nat, +prefix: F.Factors, +zero: F.Factor) -> F.Form:
  match terms:
    case []: []
    case F.Term{w,+fs} <> tail:
      places = place_factors(cols,fs,zero)
      row = List.drop(&2,F.Factor,fs,cols)
      ordered = row_factors(rows,row,prefix,places,zero)
      F.Term{w,ordered} <> layout(tail,cols,rows,prefix,zero)

def table(terms: F.Form, rows: Nat, ell: Nat, k: Nat, offset: Nat) -> F.Form:
  +r = Sample.row_bits(rows)
  prefix = X.choice(Nat.sub(k,r),Nat.div(offset,Nat.pow(2n,r)))
  layout(terms,CS.bits(ell),r,prefix,X.select(0n))

def eq(psi: B.Elements, scale: E.E3) -> F.Form:
  [F.Term{scale,X.eq(psi)}]

def slots(xs: List<&2,Slot>, +bits: Nat, +h: Nat, +offset: Nat) -> F.Form:
  match xs:
    case []: []
    case Slot{i,w} <> tail:
      j = Nat.add(offset,Nat.mul(i,CS.size(h)))
      F.Term{w,X.choice(bits,j)} <> slots(tail,bits,h,offset)

def locked(xs: List<&2,Slot>, +ell: Nat) -> Bool:
  match xs:
    case []: True{}
    case Slot{i,_} <> tail: Nat.is_lt(i,Nat.sub(ell,1n)) && locked(tail,ell)

def sample(part: Sample.Member, s: Sample.Seed, y: E.E3) -> IO(Sample.Sample):
  K.need(Sample.Sample,Sample.single(part,s,y),"NO: lin-own-sample")

type Batch is Data:
  Batch{theta: E.E3, power: E.E3, main: F.Form, mask: F.Form, target: E.E3}

def add(claim: Sample.Sample, batch: Batch) -> Batch:
  Sample.Sample{xs,ys,v} = claim
  Batch{+t,+w,a,b,c} = batch
  Batch{t,A.mul(w,t),X.scale(xs,w,a),X.scale(ys,w,b),A.add(c,A.mul(w,v))}

def result(batch: Batch, size: Nat) -> F.Claim:
  Batch{_,_,a,b,c} = batch
  F.Claim{a,F.expand(b,CS.zeros(size)),c}

# Short and over-width forms keep the original placement and validation path.
def weight_table(+terms: F.Form, +rows: Nat, +ell: Nat, +k: Nat, +off: Nat,
                +gs: B.Elements, +base_bits: Nat) -> F.Form:
  +r = Sample.row_bits(rows)
  good = Project.fits(terms,r,CS.bits(ell),k,base_bits,F.count(E.E3,gs,0n))
  choose = Bool.pick(Unit -> F.Form,good,
    _ => Project.project(terms,gs,r,k,base_bits,off), _ => table(terms,rows,ell,k,off))
  choose(Unit{})

def bat(+geo: Geometry, first: First, psi: B.Elements, os: Sample.Seed, oy: E.E3, t: E.E3, gs: B.Elements, n_base: Nat) -> IO(F.Claim):
  Geometry{_,+w,+m,+n,+ell,+ell_mask,+k,+h} = geo
  First{Pending{weights,mine,+mask,target},Opened{iseed,iy,ws,wy}} = first
  +wa = Open.before_at(w,n)
  +oa = Open.after_at(w,n)
  +ia = Open.before_at(1n,m)
  ma = Open.after_at(1n,m)
  bits = Nat.add(h,CS.bits(ell_mask))
  eval : Sample.Sample = Sample.Sample{table(eq(mine,F.one()),w,ell,k,wa),slots(mask,bits,h,ia),target}
  dot : Sample.Sample = Sample.Sample{List.append(&2,F.Term,weight_table(weights,n,ell,k,oa,gs,n_base),table(eq(psi,A.negate(F.one())),w,ell,k,wa)),[],F.zero()}
  do IO<F.Claim>:
    ok : Unit <- Header.require(locked(mask,ell_mask),"NO: lin-index-mask-pad")
    i : Sample.Sample <- sample(Sample.Member{Shared.absent(),Sample.Part{1n,ell_mask,h,ia},False{}},iseed,iy)
    own : Sample.Sample <- sample(Sample.Member{Sample.Part{w,ell,k,wa},Sample.Part{m,ell_mask,h,ma},False{}},ws,wy)
    om : Sample.Sample <- sample(Sample.Member{Sample.Part{n,ell,k,oa},Shared.absent(),False{}},os,oy)
    return result(add(om,add(own,add(i,add(dot,add(eval,Batch{t,F.one(),[],[],F.zero()}))))),Nat.mul(CS.size(h),ell_mask))

def coordinates(group: Run.Group) -> B.Elements:
  Run.Group{_,rounds,_,_} = group
  Project.gammas(rounds,[])

def check(events: Tr.Events, adopted: Shared.Adopted, first: First) -> IO(Unit):
  Shared.Adopted{psi,s,y,Lin.Shape{_,_,_,Lin.Side{_,_,+omega,_},Lin.Side{_,_,+w,+m},_,+ss}} = adopted
  do IO<Unit>:
    +group : Run.Group <- Run.group(events)
    geo : Geometry <- geometry(ss,w,m,omega)
    claim : F.Claim <- bat(geo,first,psi,s,y,Run.theta(group),coordinates(group),Project.base_width(ss))
    rest : Tr.Events <- Run.verify(group,Open.Second{U32.to_nat(w),U32.to_nat(m),U32.to_nat(omega)},ss,claim)
    Header.require(List.is_empty(&2,Tr.Observed,rest),"NO: lin-own-rounds")
