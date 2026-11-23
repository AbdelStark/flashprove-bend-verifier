import Base
import ./fold.bend as F
import ./fold_frame.bend as R
import ./fold_carry.bend as Carry
import ./fold_request.bend as Fold
import ./fold_request_rounds.bend as W
import ./fold_request_shape.bend as Q
import ./fold_cs.bend as CS
import ./row_tensor.bend as Tensor
import ./base_check.bend as B
import ./segment_projection.bend as Project
import ./key_stage_trace.bend as Tr
import ./extension.bend as X
import ./header.bend as Header
import ./leaf_shape.bend as S

# R12.16 places the entire preceding main in row 0 of the two-row carrier.
# That equation enters BAT first, with weight one. Once FOLD fixes the group's
# row bits, every preceding coefficient acquires the same scalar. Preserve
# this exact linear combination without inserting and removing those bits
# on every old tensor at each subsequent layer.
type State is Data:
  State{cursor: Fold.Cursor, basis: Project.Basis, columns: B.Elements}

def begin(+events: Tr.Events,main: B.Code,later: List<&2,S.Stage>) -> IO(State):
  B.Code{_,ell,_} = main
  do IO<State>:
    +basis : Project.Basis <- Project.load(events,ell,later)
    return State{Fold.Cursor{events,Fold.Start{},[]},basis,Project.zeros(basis)}

def multiplier(members: R.Members,gamma: B.Elements,epsilon: X.E3) -> X.E3:
  offset = R.rank(members,True{},False{},0n,2n,0n)
  Tensor.entry(Tensor.eq(gamma),offset,epsilon)

def stored(done: W.Fold,+ns: Q.Notices,+stage: S.Stage,ks: Carry.Keeps,+basis: Project.Basis,columns: B.Elements) -> IO(State):
  W.Fold{R.Closed{F.Single{+fs,d,f,target},held},+gamma,rest,eps} = done
  S.Stage{B.Code{_,ell,_},_,_,_} = stage
  single: F.Single = F.Single{[],d,f,target}
  prev: Fold.Past = Fold.Past{ns,stage,R.Closed{single,held},gamma,ks}
  scale = multiplier(Q.members(ns),gamma,eps)
  do IO<State>:
    ok : Unit <- Header.require(F.fits(fs,CS.bits(ell)),"NO: request-switch-equations")
    return State{Fold.Cursor{rest,prev,Q.survivors(ns,[])},basis,Project.merge(basis,fs,columns,scale)}

def closed(group: Fold.Group,+ns: Q.Notices,basis: Project.Basis,old: B.Elements) -> IO(State):
  Fold.Group{row,+stage,ks,rest} = group
  do IO<State>:
    folded : W.Fold <- W.fold(row,stage,rest)
    stored(folded,ns,stage,ks,basis,old)

def advance(link: Q.Link,row: R.Equation,c: B.Code,m: B.Code,st: State,+first: Bool) -> IO(State):
  Q.Link{_,ns} = link
  State{Fold.Cursor{events,past,alive},basis,old} = st
  +all = Fold.prefix(alive,ns,first)
  do IO<State>:
    bat : W.Bat <- W.scan(events,W.Reading{[],None{}})
    group : Fold.Group <- Fold.prepare(all,c,m,[row],past,first,bat,3n)
    closed(group,all,basis,old)

def restore(st: State) -> Fold.Cursor:
  match st:
    case State{Fold.Cursor{evs,Fold.Past{ms,stage,R.Closed{F.Single{fs,d,f,t},held},g,ks},alive},basis,columns}:
      main = F.cat(F.Term,Project.lift(basis,columns),fs)
      Fold.Cursor{evs,Fold.Past{ms,stage,R.Closed{F.Single{main,d,f,t},held},g,ks},alive}
    case State{cur,_,_}: cur
