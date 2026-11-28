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
type Update is Data:
  Update{challenges: B.Elements, terms: F.Form, carry: X.E3, epsilon: X.E3}

# The next link requires the preceding mask, target and kept rows in the
# cursor, but not its main columns. With one worker each update is projected
# at once. Otherwise every update waits, newest first, until the chain ends.
type Columns is Data:
  Sequential{values: B.Elements}
  Deferred{values: B.Elements, updates: List<&2,Update>}
type State is Data:
  State{cursor: Fold.Cursor, basis: Project.Basis, columns: Columns}

def begin(+events: Tr.Events,main: B.Code,later: List<&2,S.Stage>) -> IO(State):
  B.Code{_,ell,_} = main
  do IO<State>:
    +basis : Project.Basis <- Project.load(events,ell,later)
    n : U32 <- IO.thread_count()
    +zero : B.Elements = Project.zeros(basis)
    return State{Fold.Cursor{events,Fold.Start{},[]},basis,Bool.pick(Columns,U32.is_le(n,1),Sequential{zero},Deferred{zero,[]})}

def multiplier(members: R.Members,gamma: B.Elements,epsilon: X.E3) -> X.E3:
  offset = R.rank(members,True{},False{},0n,2n,0n)
  Tensor.entry(Tensor.eq(gamma),offset,epsilon)

# For a correctly sized member the row and terminal-column challenges fix
# consecutive low bits. Their evaluations commute with summation and the
# common hiding scalar epsilon. Deposit the combined result in one pass.
def contribution(basis: Project.Basis, rows: B.Elements, main: F.Form, eps: X.E3) -> B.Elements:
  Project.Basis{cols,_,n} = basis
  table = Project.reduce(main,F.prepare(F.cat(X.E3,rows,cols)),Array.new(X.E3,n,F.zero()))
  F.scaled(F.values(Array.to_list(X.E3,table),[]),eps)

def contract(basis: Project.Basis, rows: B.Elements, main: F.Form, old: B.Elements, carry: X.E3, eps: X.E3) -> B.Elements:
  F.plus(contribution(basis,rows,main,eps),F.scaled(old,carry))

type Transition is Data:
  Transition{cursor: Fold.Cursor, update: Update}

# Resolve the original width refusal before advancing to the following link.
# Once an Update exists its computation is total and cannot refuse.
def checked(valid: Bool,+gs: B.Elements,main: F.Form,carry: X.E3,eps: X.E3,width: Nat) -> IO(Update):
  match valid:
    case True{}: IO.pure(Update,Update{gs,main,carry,eps})
    case False{}:
      +folded = F.fixed(main,gs,eps)
      do IO<Update>:
        ok : Unit <- Header.require(F.fits(folded,width),"NO: request-switch-equations")
        return Update{[],folded,carry,F.one()}

def stored(done: W.Fold,main: F.Form,+ns: Q.Notices,+stage: S.Stage,ks: Carry.Keeps) -> IO(Transition):
  W.Fold{R.Closed{single,held},+gamma,rest,+eps} = done
  S.Stage{B.Code{_,ell,_},_,k,_} = stage
  prev: Fold.Past = Fold.Past{ns,stage,R.Closed{single,held},gamma,ks}
  scale = multiplier(Q.members(ns),gamma,eps)
  +width = CS.bits(ell)
  +terms = main
  valid = F.fits(terms,Nat.add(U32.to_nat(k),width))
  do IO<Transition>:
    local : Update <- checked(valid,gamma,terms,scale,eps,width)
    return Transition{Fold.Cursor{rest,prev,Q.survivors(ns,[])},local}

def closed(group: Fold.Group,+ns: Q.Notices) -> IO(Transition):
  Fold.Group{R.Group{main,mask,kept,t},+stage,ks,rest} = group
  do IO<Transition>:
    folded : W.Fold <- W.fold(R.Group{[],mask,kept,t},stage,rest)
    stored(folded,main,ns,stage,ks)

def transition(link: Q.Link,row: R.Equation,c: B.Code,m: B.Code,cur: Fold.Cursor,+first: Bool) -> IO(Transition):
  Q.Link{_,ns} = link
  Fold.Cursor{events,past,alive} = cur
  +all = Fold.prefix(alive,ns,first)
  do IO<Transition>:
    bat : W.Bat <- W.scan(events,W.Reading{[],None{}})
    group : Fold.Group <- Fold.prepare(all,c,m,[row],past,first,bat,3n)
    closed(group,all)

def commit_one(basis: Project.Basis,old: B.Elements,x: Update) -> B.Elements:
  Update{gs,fs,c,e} = x
  contract(basis,gs,fs,old,c,e)

# Split off the carries so the projection inputs are never shared.
type Part is Data:
  Part{rows: B.Elements, main: F.Form, eps: X.E3}

def unzip(newest_first: List<&2,Update>, parts: List<&2,Part>, carries: B.Elements) -> List<&2,Part> & B.Elements:
  match newest_first:
    case []: (parts,carries)
    case Update{gs,fs,c,e} <> older: unzip(older,Part{gs,fs,e} <> parts,c <> carries)

type Parts is Data:
  Leaf{part: Part}
  Fork{left: Parts, right: Parts}

def leaves(ps: List<&2,Part>) -> List<&2,Parts>:
  match ps:
    case []: []
    case p <> rest: Leaf{p} <> leaves(rest)

def pair_up(ts: List<&2,Parts>) -> List<&2,Parts>:
  match ts:
    case a <> b <> rest: Fork{a,b} <> pair_up(rest)
    case rest: rest

# Pair neighbours level by level; 64 levels exceed any list.
def tree(fuel: Nat, ts: List<&2,Parts>) -> List<&2,Parts>:
  match fuel ts:
    case 1n+f Con{a,Con{b,rest}}: tree(f,pair_up(a <> b <> rest))
    case _ rest: rest

# The contributions in order, each subtree on its own worker.
def contributions(+basis: Project.Basis,t: Parts) -> List<&2,B.Elements>:
  match t:
    case Leaf{Part{gs,fs,e}}: [contribution(basis,gs,fs,e)]
    case Fork{l,r}:
      left right = contributions(basis,l) contributions(basis,r)
      List.append(&2,B.Elements,left,right)

def all_contributions(+basis: Project.Basis,ts: List<&2,Parts>) -> List<&2,B.Elements>:
  match ts:
    case [t]: contributions(basis,t)
    case _: []

def carried(cs: B.Elements,xs: List<&2,B.Elements>,old: B.Elements) -> B.Elements:
  match cs xs:
    case Con{c,more} Con{x,rest}: carried(more,rest,F.plus(x,F.scaled(old,c)))
    case _ _: old

def combined(+basis: Project.Basis,old: B.Elements,split: List<&2,Part> & B.Elements) -> B.Elements:
  (parts,carries) = split
  carried(carries,all_contributions(basis,tree(64n,leaves(parts))),old)

# C_i = contribution_i + carry_i * C_(i-1). Compute every contribution at
# once, then apply the affine updates in transcript order.
def commit_all(basis: Project.Basis,old: B.Elements,newest_first: List<&2,Update>) -> B.Elements:
  combined(basis,old,unzip(newest_first,[],[]))

def finish_columns(basis: Project.Basis,q: Columns) -> B.Elements:
  match q:
    case Sequential{xs}: xs
    case Deferred{xs,us}: commit_all(basis,xs,us)

def assembled(basis: Project.Basis,t: Transition,append: Update -> Columns) -> State:
  Transition{cur,update} = t
  State{cur,basis,append(update)}

def collect(basis: Project.Basis,t: IO(Transition),append: Update -> Columns) -> IO(State):
  do IO<State>:
    done : Transition <- t
    return assembled(basis,done,append)

def advance_queue(q: Columns,+basis: Project.Basis,t: IO(Transition)) -> IO(State):
  match q:
    case Sequential{xs}: collect(basis,t,d => Sequential{commit_one(basis,xs,d)})
    case Deferred{xs,us}: collect(basis,t,d => Deferred{xs,d <> us})

def advance(link: Q.Link,row: R.Equation,c: B.Code,m: B.Code,st: State,first: Bool) -> IO(State):
  State{cur,basis,queue} = st
  advance_queue(queue,basis,transition(link,row,c,m,cur,first))

def restore(st: State) -> Fold.Cursor:
  match st:
    case State{Fold.Cursor{evs,Fold.Past{ms,stage,R.Closed{F.Single{fs,d,f,t},held},g,ks},alive},+basis,columns}:
      main = F.cat(F.Term,Project.lift(basis,finish_columns(basis,columns)),fs)
      Fold.Cursor{evs,Fold.Past{ms,stage,R.Closed{F.Single{main,d,f,t},held},g,ks},alive}
    case State{cur,_,_}: cur

