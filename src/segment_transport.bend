import Base
import ./segment_workers.bend as Workers
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

# Two checked local forms can wait for projection. The next link requires the
# preceding mask, target and kept rows in the cursor, but not its main columns.
type Columns is Data:
  Sequential{values: B.Elements}
  Empty{values: B.Elements}
  One{values: B.Elements, first: Update}
  Two{values: B.Elements, first: Update, second: Update}
type State is Data:
  State{cursor: Fold.Cursor, basis: Project.Basis, columns: Columns}

def begin(+events: Tr.Events,main: B.Code,later: List<&2,S.Stage>) -> IO(State):
  B.Code{_,ell,_} = main
  do IO<State>:
    +basis : Project.Basis <- Project.load(events,ell,later)
    n : U32 <- IO.thread_count()
    +zero : B.Elements = Project.zeros(basis)
    return State{Fold.Cursor{events,Fold.Start{},[]},basis,Bool.pick(Columns,U32.is_le(n,1),Sequential{zero},Empty{zero})}

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

# C_i = contribution_i + carry_i * C_(i-1). Compute the expensive local
# vectors independently, then apply both affine updates in transcript order.
def commit_two(+basis: Project.Basis,old: B.Elements,a: Update,b: Update) -> B.Elements:
  Update{ga,fa,ca,ea} = a
  Update{gb,fb,cb,eb} = b
  first second = contract(basis,ga,fa,old,ca,ea) contribution(basis,gb,fb,eb)
  F.plus(second,F.scaled(first,cb))

def finish_columns(basis: Project.Basis,q: Columns) -> B.Elements:
  match q:
    case Sequential{xs}: xs
    case Empty{xs}: xs
    case One{xs,a}: commit_one(basis,xs,a)
    case Two{xs,a,b}: commit_two(basis,xs,a,b)

def assembled(basis: Project.Basis,t: Transition,append: Update -> Columns) -> State:
  Transition{cur,update} = t
  State{cur,basis,append(update)}

def collect(basis: Project.Basis,t: IO(Transition),append: Update -> Columns) -> IO(State):
  do IO<State>:
    done : Transition <- t
    return assembled(basis,done,append)

# A full queue projects alongside the next checked transition. IO.OP retains
# that transition's refusal until the preceding checked work has completed.
def advance_queue(q: Columns,+basis: Project.Basis,t: IO(Transition)) -> IO(State):
  match q:
    case Sequential{xs}: collect(basis,t,d => Sequential{commit_one(basis,xs,d)})
    case Empty{xs}: collect(basis,t,d => One{xs,d})
    case One{xs,a}: collect(basis,t,d => Two{xs,a,d})
    case Two{xs,a,b}:
      projected next = commit_two(basis,xs,a,b) Workers.observe(Transition,t)
      collect(basis,Workers.result(Transition,next),d => One{projected,d})

def advance(link: Q.Link,row: R.Equation,c: B.Code,m: B.Code,st: State,first: Bool) -> IO(State):
  State{cur,basis,queue} = st
  advance_queue(queue,basis,transition(link,row,c,m,cur,first))

def restore(st: State) -> Fold.Cursor:
  match st:
    case State{Fold.Cursor{evs,Fold.Past{ms,stage,R.Closed{F.Single{fs,d,f,t},held},g,ks},alive},+basis,columns}:
      main = F.cat(F.Term,Project.lift(basis,finish_columns(basis,columns)),fs)
      Fold.Cursor{evs,Fold.Past{ms,stage,R.Closed{F.Single{main,d,f,t},held},g,ks},alive}
    case State{cur,_,_}: cur
