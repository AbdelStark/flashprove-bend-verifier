import Base
import ./lin_own.bend as Lin
import ./key_stage_wf.bend as WF
import ./key_stage_trace.bend as Trace
import ./key_stage_lookup_plan.bend as M
import ./key_stage_lookup_rows.bend as L
import ./key_stage_psc.bend as PSC
import ./key_stage_matrix.bend as Mat
import ./key_stage_openings.bend as K
import ./oracle_sample.bend as OOD
import ./plan.bend as P
import ./fold.bend as F
import ./fold_verify.bend as FV
import ./sumcheck.bend as E
import ./base_check.bend as B
import ./extension.bend as X
import ./transcript.bend as T
import ./header.bend as Header
import ./hash_bytes.bend as H

type Combined is Data:
  Combined{masks: L.Masks, target: X.E3}

def merge(parts: List<&2,Mat.Part>, +theta: X.E3, +pow: X.E3, acc: Combined) -> Combined:
  match parts acc:
    case Nil{} out: out
    case Con{Mat.Part{_,_,_,_,m,t},tail} Combined{ms,total}:
      merge(tail,theta,E.mul(pow,theta),Combined{L.sum(L.scale(m,pow),ms),E.add(total,E.mul(pow,t))})

def eq(z: B.Elements, gamma: B.Elements, acc: X.E3) -> X.E3:
  match z gamma:
    case Con{+x,tail} Con{y,more}: eq(tail,more,E.mul(acc,F.mix(F.sub(F.one(),x),x,y)))
    case _ _: acc

def weights(parts: List<&2,Mat.Part>, +z: B.Elements, +theta: X.E3, +scale: X.E3, +bits: Nat, acc: F.Form) -> F.Form:
  match parts:
    case []: acc
    case Mat.Part{runs,digits,point,psi,_,_} <> tail:
      next = Mat.runs(runs,digits,bits,point,eq(psi,z,scale),acc)
      weights(tail,z,theta,E.mul(theta,scale),bits,next)

type Matrix is Data:
  Matrix{weights: F.Form, psi: B.Elements, masks: L.Masks, target: X.E3}

def finish(remaining: L.Tape, form: PSC.Obligation, parts: List<&2,Mat.Part>, inherited: L.Masks, +z: B.Elements,
  bits: Nat, eps: X.E3, theta: X.E3, next: Nat) -> IO(Matrix):
  L.Tape{events,_,_,_} = remaining
  PSC.Obligation{target,fresh,carry,_} = form
  do IO<Matrix>:
    ok : Unit <- Header.require(List.is_empty(&2,L.AlgebraRound,events),"NO: key-batt-extra-rounds")
    return Matrix{weights(parts,z,theta,eps,bits,[]),z,
      L.sum(L.next(fresh,L.IndexMask{},next),L.scale(inherited,carry)),target}

def folded_form(claim: PSC.Claim, eps: X.E3, rev: B.Elements, t: L.Tape, parts: List<&2,Mat.Part>,
  inherited: L.Masks, bits: Nat, theta: X.E3, next: Nat) -> IO(Matrix):
  finish(t,PSC.obligation(claim,F.zero(),[]),parts,inherited,List.reverse(&2,X.E3,rev),bits,eps,theta,next)

def folded(st: L.State, parts: List<&2,Mat.Part>, inherited: L.Masks, bits: Nat, theta: X.E3, next: Nat) -> IO(Matrix):
  L.State{+claim,rev,t} = st
  PSC.Claim{_,eps,_} = claim
  folded_form(claim,eps,rev,t,parts,inherited,bits,theta,next)

def sumcheck(start: Combined, stream: L.Events, parts: List<&2,Mat.Part>, theta: X.E3, k: Nat, bits: Nat, idx: Nat) -> IO(Matrix):
  Combined{ms,target} = start
  do IO<Matrix>:
    start : L.State <- L.begin(L.Tape{stream,0n,0n,[]},target)
    end : L.State <- L.rounds(List.replicate(PSC.Variable,k,PSC.Variable{PSC.Plain{},2n}),start)
    folded(end,parts,ms,bits,theta,idx)

type Later is Data:
  Later{tape: L.Events, seed: OOD.Seed, answer: X.E3}

def named(round: P.Round) -> String:
  P.Round{name,_,_,_,_,_,_,_,_,_,_,_} = round
  name

def samples(round: P.Round) -> Nat:
  P.Round{_,_,_,_,_,_,n,_,_,_,_,_} = round
  U32.to_nat(n)

def ordinary(round: P.Round, raw: H.Bytes, stream: T.Stream) -> L.AlgebraRound:
  P.Round{name,_,_,_,_,_,n,nz,_,_,_,_} = round
  L.event(name,raw,stream,n,nz)

type Step is Data:
  Continue{rounds: L.Events}
  Stop{rounds: L.Events, seed: OOD.Seed}

def visit(is_seed: Bool, p: P.Round, msg: H.Bytes, s: T.Stream, acc: L.Events) -> Step:
  match is_seed:
    case True{}: Stop{List.reverse(&2,L.AlgebraRound,acc),OOD.point(Nat.sub(samples(p),1n),s,[])}
    case False{}: Continue{ordinary(p,msg,s) <> acc}

def rounds(events: Trace.Events, state: Step) -> IO(Later):
  match events state:
    case Con{Trace.Observed{+p,msg,_,_,_},_} Stop{acc,seed}:
      do IO<Later>:
        ok : Unit <- Header.require(String.eq(named(p),"SEND answer"),"NO: key-W-answer")
        y : X.E3 <- K.need(X.E3,FV.value(msg),"NO: key-W-sample")
        return Later{acc,seed,y}
    case Con{Trace.Observed{+p,msg,s,_,_},tail} Continue{acc}:
      rounds(tail,visit(String.eq(named(p),"SEND seed"),p,msg,s,acc))
    case _ _: IO.die(Later,1,"NO: key-W-sample")

type Tail is Data:
  Tail{theta: X.E3, count: Nat, later: Later}

def sigma(events: Trace.Events) -> IO(Tail):
  match events:
    case Trace.Observed{P.Round{"BAT-sigma",_,_,_,_,_,_,_,_,_,_,cnt},_,s,_,_} <> tail:
      do IO<Tail>:
        seen : Later <- rounds(tail,Continue{[]})
        return Tail{T.value(X.E3,T.element(s)),U32.to_nat(cnt),seen}
    case _ <> tail: sigma(tail)
    case _: IO.die(Tail,1,"NO: key-batt")

type Sealed is Data:
  Sealed{matrix: Matrix, index_seed: OOD.Seed, index_answer: X.E3, w_seed: OOD.Seed, w_answer: X.E3}

def collect(cut: Tail, +parts: List<&2,Mat.Part>, kcol: Nat, rows: Nat, idx: Nat, z: OOD.Seed, answer: X.E3) -> IO(Sealed):
  Tail{+theta,count,Later{tape,w,y}} = cut
  do IO<Sealed>:
    ok : Unit <- Header.require(Nat.is_eq(count,List.length(&2,Mat.Part,parts)),"NO: key-batt-count")
    matrix : Matrix <- sumcheck(merge(parts,theta,F.one(),Combined{[],F.zero()}),tape,parts,theta,kcol,OOD.row_bits(rows),idx)
    return Sealed{matrix,z,answer,w,y}

def combine(stage: WF.Stage, events: Trace.Events) -> IO(Sealed):
  match stage events:
    case WF.Rows{M.Metadata{lookups,+kcol,rows,_,_,_},_,pending,_,idx} Con{Trace.Observed{P.Round{"SEND seed",_,_,_,_,_,n,1,_,_,_,_},_,s,_,_},Con{Trace.Observed{P.Round{"SEND answer",_,_,_,_,_,_,_,_,_,_,_},m,_,_,_},tail}}:
      do IO<Sealed>:
        parts : List<&2,Mat.Part> <- Mat.parts(pending,lookups,kcol,[])
        cut : Tail <- sigma(tail)
        answer : X.E3 <- K.need(X.E3,FV.value(m),"NO: key-index-sample")
        collect(cut,parts,kcol,rows,idx,OOD.point(Nat.sub(U32.to_nat(n),1n),s,[]),answer)
    case _ _: IO.die(Sealed,1,"NO: key-batt-input")


def slots(xs: L.Masks, acc: List<&2,Lin.Slot>) -> IO(List<&2,Lin.Slot>):
  match xs:
    case []: IO.pure(List<&2,Lin.Slot>,List.reverse(&2,Lin.Slot,acc))
    case L.Mask{L.IndexMask{},i,w} <> tail: slots(tail,Lin.Slot{i,w} <> acc)
    case _: IO.die(List<&2,Lin.Slot>,1,"NO: key-batt-mask-oracle")

def lin(sealed: Sealed) -> IO(Lin.First):
  Sealed{Matrix{weights,z,ms,target},iz,iy,wz,wy} = sealed
  do IO<Lin.First>:
    terms : List<&2,Lin.Slot> <- slots(ms,[])
    return Lin.First{Lin.Pending{weights,z,terms,target},Lin.Opened{iz,iy,wz,wy}}
