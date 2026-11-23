import Base
import ./segment_local.bend as Local
import ./segment_transport.bend as Transport
import ./segment_model.bend as M
import ./segment_inputs.bend as Inputs
import ./fold.bend as F
import ./fold_frame.bend as R
import ./fold_request.bend as Fold
import ./fold_request_shape.bend as Q
import ./fold_batt.bend as Batt
import ./lin_own.bend as Own
import ./key_stage_trace.bend as Trace
import ./plan.bend as Plan
import ./plan_types.bend as PT
import ./base_check.bend as B
import ./leaf_shape.bend as S
import ./header.bend as Header

# Consume one physical group at a time. Only folded obligations, surviving
# member samples and the separate G/H matrix claims cross a segment boundary.
type State is Data:
  State{carry: Transport.State, pending_rev: Batt.Pending}

def family(+model: M.Inputs,+ctx: Local.Context,last: Bool) -> IO(Local.Logical):
  choose = Bool.pick(Unit -> IO(Local.Logical),last,
    _ => Local.at_head(model,ctx),
    _ => Bool.pick(Unit -> IO(Local.Logical),Nat.is_eq(Nat.mod(Local.number(model),2n),0n),
      _ => Local.at_feed(model,ctx), _ => Local.at_attention(model,ctx))(Unit{}))
  choose(Unit{})

def pending(p: Maybe<&2,Own.Pending>,xs: Batt.Pending) -> Batt.Pending:
  match p:
    case None{}: xs
    case Some{x}: x <> xs

def step(link: Q.Link,placed: Local.Local,c: B.Code,m: B.Code,state: State,first: Bool) -> IO(State):
  Local.Local{row,maybe} = placed
  State{cur,ps} = state
  do IO<State>:
    next : Transport.State <- Transport.advance(link,row,c,m,cur,first)
    return State{next,pending(maybe,ps)}

def walk(models: Inputs.Batches,links: List<&2,Q.Link>,+ctx: Local.Context,+c: B.Code,+m: B.Code,state: State,i: Nat) -> IO(State):
  match models links:
    case Nil{} Nil{}: IO.pure(State,state)
    case Con{+model,+tail} Con{link,rest}:
      +idx = i
      do IO<State>:
        ok : Unit <- Header.require(Nat.is_eq(idx,Local.number(model)),"NO: segment-link-order")
        logical : Local.Logical <- family(model,ctx,List.is_empty(&2,M.Inputs,tail))
        physical : Local.Local <- Local.physical(idx,ctx,logical)
        after : State <- step(link,physical,c,m,state,Nat.is_eq(idx,0n))
        walk(tail,rest,ctx,c,m,after,1n+idx)
    case _ _: IO.die(State,1,"NO: segment-link-count")

def finish(st: State,c: B.Code,m: B.Code,later: List<&2,S.Stage>,events: Trace.Events,items: List<&2,Plan.Item>) -> IO(Own.First):
  State{cur,rows} = st
  do IO<Own.First>:
    after : Trace.Events <- Fold.finish(Transport.restore(cur),c,m,later)
    Batt.checked(events,after,List.reverse(&2,Own.Pending,rows),items)

def closed(ctx: Local.Context,models: Inputs.Batches,+events: Trace.Events,items: List<&2,Plan.Item>) -> IO(Own.First):
  match ctx:
    case Local.Context{book,Q.Shape{+c,+m,+links,+later},geometry,profile}:
      context: Local.Context = Local.Context{book,Q.Shape{c,m,links,later},geometry,profile}
      do IO<Own.First>:
        initial : Transport.State <- Transport.begin(events,c,later)
        done : State <- walk(models,links,context,c,m,State{initial,[]},0n)
        finish(done,c,m,later,events,items)

def verify(models: Inputs.Batches,events: Trace.Events,+items: List<&2,Plan.Item>,profile: PT.Profile) -> IO(Own.First):
  do IO<Own.First>:
    ctx : Local.Context <- Local.context(items,profile)
    closed(ctx,models,events,items)
