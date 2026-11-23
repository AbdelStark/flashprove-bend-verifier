import Base
import ./fold.bend as F
import ./fold_frame.bend as R
import ./fold_carry.bend as C
import ./fold_verify.bend as V
import ./fold_request_shape.bend as Q
import ./oracle_sample.bend as Sample
import ./leaf_shape.bend as L
import ./lin_run.bend as Lin
import ./base_check.bend as B
import ./key_stage_trace.bend as Tr
import ./plan.bend as P
import ./transcript.bend as T
import ./extension.bend as E
import ./header.bend as H
import ./key_stage_openings.bend as K

type Send is Data:
  Send{seed: Sample.Seed, result: Tr.Observed}
type Bat is Data:
  Bat{sends: List<&2,Send>, theta: E.E3, rows: Nat, after_bat: Tr.Events}
type Samples is Data:
  Samples{rows: List<&2,R.Equation>, kept: C.Keeps}

def marker(e: Tr.Observed) -> U32:
  +n = Lin.name(e)
  Bool.pick(U32,String.eq(n,"SEND seed"),1,Bool.pick(U32,String.eq(n,"BAT"),2,0))

type Phase is Data:
  Reading{sends: List<&2,Send>, pending: Maybe<&2,Sample.Seed>}
  Found{sends: List<&2,Send>, theta: E.E3, rows: Nat}
  Bad{}

def seed_state(+n: U32, z: U32, s: T.Stream, acc: List<&2,Send>) -> Phase:
  good = U32.is_lt(0,n) && U32.is_eq(z,1)
  Bool.pick(Phase,good,Reading{acc,Some{Sample.point(Nat.sub(U32.to_nat(n),1n),s,[])}},Bad{})

def ordinary(kind: U32, e: Tr.Observed, acc: List<&2,Send>) -> Phase:
  match kind e:
    case 0 _: Reading{acc,None{}}
    case 1 Tr.Observed{P.Round{_,_,_,_,_,_,n,z,_,_,_,_},_,s,_,_}: seed_state(n,z,s,acc)
    case _ Tr.Observed{P.Round{_,_,_,_,_,_,_,_,_,_,_,rows},_,s,_,_}: Found{List.reverse(&2,Send,acc),V.first(s),U32.to_nat(rows)}

def step(pending: Maybe<&2,Sample.Seed>, +e: Tr.Observed, acc: List<&2,Send>) -> Phase:
  match pending:
    case None{}: ordinary(marker(e),e,acc)
    case Some{seed}:
      +name = Lin.name(e)
      ok = String.eq(name,"SEND answer") || String.eq(name,"LOC")
      Bool.pick(Phase,ok,Reading{Send{seed,e} <> acc,None{}},Bad{})

def scan(xs: Tr.Events, phase: Phase) -> IO(Bat):
  match xs phase:
    case rest Found{ss,t,n}: IO.pure(Bat,Bat{ss,t,n,rest})
    case Con{e,tail} Reading{acc,pending}: scan(tail,step(pending,e,acc))
    case _ _: IO.die(Bat,1,"NO: request-group-bat")

def sample_part(+rows: Nat, len: Nat) -> Sample.Part: Sample.Part{rows,len,Sample.row_bits(rows),0n}

def put(value: Maybe<&2,Sample.Sample>, +id: Nat, +main: Nat, mask: Nat, degree: Nat, +keep: Bool, state: Samples) -> IO(Samples):
  match value state:
    case Some{Sample.Sample{+fs,ws,+y}} Samples{acc,+ks}:
      +parts: R.Forms = Bool.pick(R.Forms,Nat.is_eq(mask,0n),[],[R.On{id,True{},ws}])
      on = Bool.pick(R.Forms,Nat.is_eq(main,0n),parts,R.On{id,False{},fs} <> parts)
      remint: C.Kept = C.Kept{id,id,main,degree,fs,y}
      IO.pure(Samples,Samples{R.Equation{on,y} <> acc,Bool.pick(C.Keeps,keep,remint <> ks,ks)})
    case _ _: IO.die(Samples,1,"NO: request-ood-shape")

def sample_rows(ns: Q.Notices, ys: B.Elements, +seed: Sample.Seed, +ell: Nat, +mask_len: Nat, state: Samples, rider: Bool) -> IO(Samples):
  match ns ys rider:
    case Nil{} Nil{} False{}: IO.pure(Samples,state)
    case Nil{} Con{_,Nil{}} True{}: IO.pure(Samples,state)
    case Con{Q.Notice{R.Member{+id,+m,+d,+n,keep},_,_},more} Con{y,tail} flag:
      member: Sample.Member = Sample.Member{sample_part(m,ell),sample_part(n,mask_len),Nat.is_eq(d,1n)}
      do IO<Samples>:
        next : Samples <- put(Sample.single(member,seed,y),id,m,n,d,keep,state)
        sample_rows(more,tail,seed,ell,mask_len,next,flag)
    case _ _ _: IO.die(Samples,1,"NO: request-ood-count")

def sampled(ss: List<&2,Send>, +ns: Q.Notices, +moment: Nat, +ell: Nat, +mask_len: Nat, +first: Bool, state: Samples) -> IO(Samples):
  match ss:
    case []: IO.pure(Samples,state)
    case Send{seed,Tr.Observed{P.Round{_,_,_,_,_,a,_,_,_,_,_,_},raw,_,_,_}} <> tail:
      do IO<Samples>:
        answers : B.Elements <- K.need(B.Elements,B.read_elements(U32.to_nat(a),raw,[],True{}),"NO: request-ood-value")
        st : Samples <- sample_rows(Q.moment(ns,moment,[]),answers,seed,ell,mask_len,state,first && Nat.is_eq(moment,0n))
        sampled(tail,ns,1n+moment,ell,mask_len,first,st)

type Fold is Data:
  Fold{closed: R.Closed, gamma: B.Elements, after: Tr.Events, epsilon: E.E3}

def rounds(n: Nat, events: Tr.Events, +row: R.Group, +eps: E.E3, target: E.E3, gs: B.Elements, +h: Nat, +len: Nat) -> IO(Fold):
  match n events:
    case 0n rest:
      +gamma = List.reverse(&2,E.E3,gs)
      IO.pure(Fold,Fold{R.close(row,gamma,h,len,eps,target),gamma,rest,eps})
    case 1n+k Con{Tr.Observed{P.Round{name,_,_,_,_,_,_,_,_,_,_,_},raw,stream,_,_},tail}:
      +g = V.first(stream)
      do IO<Fold>:
        ok : Unit <- H.require(String.eq(name,"FOLD round"),"NO: request-fold-round")
        +cs : B.Elements <- K.need(B.Elements,B.read_elements(2n,raw,[],True{}),"NO: request-fold-values")
        rounds(k,tail,row,eps,F.round(target,V.pick(cs),V.pick(List.drop(&2,E.E3,cs,1n)),g),g <> gs,h,len)
    case _ _: IO.die(Fold,1,"NO: request-fold-round")

def fold(row: R.Group, stage: L.Stage, events: Tr.Events) -> IO(Fold):
  R.Group{+m,+w,+kept,+t} = row
  L.Stage{_,B.Code{_,len,_},k,h} = stage
  match events:
    case Tr.Observed{P.Round{name,_,_,_,_,_,_,_,_,_,_,_},raw,stream,_,_} <> tail:
      +eps = V.first(stream)
      do IO<Fold>:
        ok : Unit <- H.require(String.eq(name,"FOLD epsilon"),"NO: request-fold-first")
        star : E.E3 <- K.need(E.E3,V.value(raw),"NO: request-fold-star")
        rounds(U32.to_nat(k),tail,R.Group{m,w,kept,t},eps,B.masked(star,eps,t),[],U32.to_nat(h),len)
    case _: IO.die(Fold,1,"NO: request-fold-first")
