import Base
import ./fold.bend as F
import ./fold_frame.bend as R
import ./fold_carry.bend as C
import ./fold_verify.bend as V
import ./fold_cs.bend as CS
import ./fold_request_rounds.bend as W
import ./fold_request_symbols.bend as Z
import ./fold_request_shape.bend as Q
import ./leaf_shape.bend as L
import ./lin_run.bend as Lin
import ./base_check.bend as B
import ./key_stage_trace.bend as Tr
import ./opening_bytes.bend as O
import ./plan.bend as P
import ./extension.bend as E
import ./header.bend as H
import ./key_stage_openings.bend as K

def Local() -> Data: List<&2,R.Equation>
def Segments() -> Data: List<&2,Local>

type Past is Data:
  Start{}
  Past{members: Q.Notices, stage: L.Stage, form: R.Closed, gamma: B.Elements, kept: C.Keeps}
type Cursor is Data:
  Cursor{events: Tr.Events, previous: Past, alive: Q.Notices}
type Group is Data:
  Group{row: R.Group, stage: L.Stage, kept: C.Keeps, events: Tr.Events}

def switched(previous: Past, sends: List<&2,W.Send>) -> IO(C.Equations):
  match previous sends:
    case Start{} Con{W.Send{_,result},_}:
      do IO<C.Equations>:
        ok : Unit <- H.require(String.eq(Lin.name(result),"SEND answer"),"NO: initial-request-send")
        return C.Equations{[],[]}
    case Past{old,L.Stage{+c,+m,+k,+h},f,gs,ks} Con{W.Send{_,+result},_}:
      do IO<C.Equations>:
        ok : Unit <- H.require(String.eq(Lin.name(result),"LOC"),"NO: request-switch-list")
        shape : C.Switch <- K.need(C.Switch,C.frame(0n,c,m,ks),"NO: request-switch-shape")
        vals : List<&2,C.Opening> <- K.need(List<&2,C.Opening>,Z.read(old,L.Stage{c,m,k,h},gs,Lin.draws(result),Lin.columns(result),3n),"NO: request-switch-columns")
        K.need(C.Equations,C.switch(shape,f,vals),"NO: request-switch-equations")
    case _ _: IO.die(C.Equations,1,"NO: request-switch-send")

def stage_of(lay: R.Layout, m: B.Code, w: B.Code) -> L.Stage:
  R.Layout{_,k,h,_,_} = lay
  L.Stage{m,w,U32.from_nat(k),U32.from_nat(h)}

def run_batch(+ns: Q.Notices, +c: B.Code, +m: B.Code, rows: Local, transfer: C.Equations,
    sends: W.Samples, +theta: E.E3, count: Nat, next: Tr.Events) -> IO(Group):
  C.Equations{plain,generator} = transfer
  W.Samples{back,keep} = sends
  +all = List.concat(&2,R.Equation,[plain,rows,List.reverse(&2,R.Equation,back),generator])
  +layout = Q.layout(ns,c,m)
  do IO<Group>:
    ok : Unit <- H.require(Nat.is_eq(F.count(R.Equation,all,0n),count),"NO: request-group-row-count")
    assembled : R.Group <- K.need(R.Group,R.grouped(layout,R.batch(all,theta,R.Batched{[],F.zero(),F.one()})),"NO: request-group-placement")
    return Group{assembled,stage_of(layout,c,m),List.reverse(&2,C.Kept,keep),next}

def prepare(+ns: Q.Notices, +c: B.Code, +m: B.Code, rows: Local, prev: Past, +first: Bool, bat: W.Bat, expected: Nat) -> IO(Group):
  B.Code{_,ell,_} = c
  B.Code{_,mask,_} = m
  W.Bat{+ss,t,n,after} = bat
  do IO<Group>:
    ok : Unit <- H.require(Nat.is_eq(List.length(&2,W.Send,ss),expected),"NO: request-send-moments")
    transfer : C.Equations <- switched(prev,ss)
    sample : W.Samples <- W.sampled(ss,ns,0n,ell,mask,first,W.Samples{[],[]})
    run_batch(ns,c,m,rows,transfer,sample,t,n,after)

def cursor(done: W.Fold, ns: Q.Notices, stage: L.Stage, keep: C.Keeps, alive: Q.Notices) -> Cursor:
  W.Fold{form,gs,tail,_} = done
  Cursor{tail,Past{ns,stage,form,gs,keep},alive}

def close(group: Group, +ns: Q.Notices) -> IO(Cursor):
  Group{row,+stage,ks,rest} = group
  do IO<Cursor>:
    folded : W.Fold <- W.fold(row,stage,rest)
    return cursor(folded,ns,stage,ks,Q.survivors(ns,[]))

def prefix(alive: Q.Notices, ns: Q.Notices, first: Bool) -> Q.Notices:
  match first:
    case True{}: ns
    case False{}: Q.carry() <> List.append(&2,Q.Notice,alive,ns)

def visit(ls: List<&2,Q.Link>, rows: Segments, +c: B.Code, +m: B.Code, cur: Cursor, first: Bool) -> IO(Cursor):
  match ls rows cur:
    case Nil{} Nil{} state: IO.pure(Cursor,state)
    case Con{Q.Link{_,ns},tail} Con{local,more} Cursor{evs,prev,alive}:
      +begin = first
      +all = prefix(alive,ns,begin)
      do IO<Cursor>:
        bat : W.Bat <- W.scan(evs,W.Reading{[],None{}})
        group : Group <- prepare(all,c,m,local,prev,begin,bat,3n)
        next : Cursor <- close(group,all)
        visit(tail,more,c,m,next,False{})
    case _ _ _: IO.die(Cursor,1,"NO: request-segment-count")

def final_claim(row: R.Group, stage: L.Stage) -> IO(F.Claim):
  R.Group{fs,mask,kept,t} = row
  L.Stage{_,B.Code{_,n,_},k,h} = stage
  do IO<F.Claim>:
    ok : Unit <- H.require(List.is_empty(&2,R.On,kept) && U32.is_eq(k,1) && U32.is_eq(h,0),"NO: request-last-group")
    return F.Claim{fs,F.expand(mask,CS.zeros(n)),t}

def final(later: List<&2,L.Stage>, stage: L.Stage, claim: F.Claim, raw: Lin.Group) -> IO(Tr.Events):
  Lin.Group{_,trace,_,tail} = raw
  do IO<Tr.Events>:
    ok : Unit <- H.require(V.custom(claim,stage <> later,trace,V.leaf_open(1n)),"NO: request-carry-proximity")
    return tail

def end(group: Group, later: List<&2,L.Stage>) -> IO(Tr.Events):
  Group{row,+stage,_,rest} = group
  do IO<Tr.Events>:
    claim : F.Claim <- final_claim(row,stage)
    raw : Lin.Group <- Lin.scan(rest,F.zero(),[],None{})
    final(later,stage,claim,raw)

def finish(cur: Cursor,c: B.Code,m: B.Code,later: List<&2,L.Stage>) -> IO(Tr.Events):
  match cur:
    case Cursor{events,prev,Nil{}}:
      do IO<Tr.Events>:
        bat : W.Bat <- W.scan(events,W.Reading{[],None{}})
        group : Group <- prepare([Q.carry()],c,m,[],prev,False{},bat,1n)
        end(group,later)
    case _: IO.die(Tr.Events,1,"NO: request-kept-at-end")

# The returned suffix starts after BASE. Its LIN/SEAL messages belong to the other request checks.
def verify(shape: Q.Shape, local: Segments, events: Tr.Events) -> IO(Tr.Events):
  Q.Shape{+c,+m,links,later} = shape
  do IO<Tr.Events>:
    cur : Cursor <- visit(links,local,c,m,Cursor{events,Start{},[]},True{})
    finish(cur,c,m,later)
