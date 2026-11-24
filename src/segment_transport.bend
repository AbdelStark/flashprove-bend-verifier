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

# For a correctly sized member the row and terminal-column challenges fix
# consecutive low bits. Their evaluations commute with summation and the
# common hiding scalar epsilon. Deposit the combined result in one pass.
def contract(basis: Project.Basis, rows: B.Elements, main: F.Form, old: B.Elements, carry: X.E3, eps: X.E3) -> B.Elements:
  Project.Basis{cols,_,n} = basis
  table = Project.reduce(main,F.prepare(F.cat(X.E3,rows,cols)),Array.new(X.E3,n,F.zero()))
  F.plus(F.scaled(F.values(Array.to_list(X.E3,table),[]),eps),F.scaled(old,carry))

def checked_projection(valid: Bool,+basis: Project.Basis,+gs: B.Elements,main: F.Form,old: B.Elements,
  carry: X.E3,eps: X.E3,width: Nat) -> IO(B.Elements):
  match valid:
    case True{}: IO.pure(B.Elements,contract(basis,gs,main,old,carry,eps))
    case False{}:
      +folded = F.fixed(main,gs,eps)
      do IO<B.Elements>:
        ok : Unit <- Header.require(F.fits(folded,width),"NO: request-switch-equations")
        return Project.merge(basis,folded,old,carry)

def stored(done: W.Fold,main: F.Form,+ns: Q.Notices,+stage: S.Stage,ks: Carry.Keeps,+basis: Project.Basis,old: B.Elements) -> IO(State):
  W.Fold{R.Closed{single,held},+gamma,rest,+eps} = done
  S.Stage{B.Code{_,ell,_},_,k,_} = stage
  prev: Fold.Past = Fold.Past{ns,stage,R.Closed{single,held},gamma,ks}
  scale = multiplier(Q.members(ns),gamma,eps)
  +width = CS.bits(ell)
  +terms = main
  valid = F.fits(terms,Nat.add(U32.to_nat(k),width))
  do IO<State>:
    cols : B.Elements <- checked_projection(valid,basis,gamma,terms,old,scale,eps,width)
    return State{Fold.Cursor{rest,prev,Q.survivors(ns,[])},basis,cols}

def closed(group: Fold.Group,+ns: Q.Notices,basis: Project.Basis,old: B.Elements) -> IO(State):
  Fold.Group{R.Group{main,mask,kept,t},+stage,ks,rest} = group
  do IO<State>:
    folded : W.Fold <- W.fold(R.Group{[],mask,kept,t},stage,rest)
    stored(folded,main,ns,stage,ks,basis,old)

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
