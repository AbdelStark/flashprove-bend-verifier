import Base
import ./segment_workers.bend as Workers
import ./segment_local.bend as Local
import ./segment_transport.bend as Transport
import ./segment_projection.bend as Project
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

# Each local equation depends only on its authenticated segment slice. Batches
# of two put one feed-forward and one attention segment on separate workers.
# A final unmatched descriptor reports the original length error in order.
type Task is Data:
  Task{input: M.Inputs, link: Q.Link, index: Nat, last: Bool}
  Mismatch{}
type Batch is Data:
  Single{a: Task}
  Pair{a: Task,b: Task}
  Joined{left: Batch,right: Batch}

def batches(models: Inputs.Batches,links: List<&2,Q.Link>,i: Nat) -> List<&2,Batch>:
  match models links:
    case Nil{} Nil{}: []
    case a <> b <> +tail l <> k <> rest:
      +idx = i
      Pair{Task{a,l,idx,False{}},Task{b,k,1n+idx,List.is_empty(&2,M.Inputs,tail)}} <> batches(tail,rest,2n+idx)
    case a <> +tail l <> rest:
      +idx = i
      Single{Task{a,l,idx,List.is_empty(&2,M.Inputs,tail)}} <> batches(tail,rest,1n+idx)
    case _ _: [Single{Mismatch{}}]

# The authenticated order also fixes error priority within joined pairs.
# Cap a window at eight rows, irrespective of the proof or scheduler size.
def join_pairs(xs: List<&2,Batch>) -> List<&2,Batch>:
  match xs:
    case a <> b <> rest: Joined{a,b} <> join_pairs(rest)
    case tail: tail

def window(+workers: U32,+xs: List<&2,Batch>) -> List<&2,Batch>:
  run = Bool.pick(Unit -> List<&2,Batch>,U32.is_ge(workers,8),
    _ => join_pairs(join_pairs(xs)),
    _ => Bool.pick(Unit -> List<&2,Batch>,U32.is_ge(workers,4),_ => join_pairs(xs),_ => xs)(Unit{}))
  run(Unit{})

type Row is Data:
  Row{link: Q.Link,physical: Local.Local,first: Bool}

def prepare(task: Task,+ctx: Local.Context) -> IO(Row):
  match task:
    case Mismatch{}: IO.die(Row,1,"NO: segment-link-count")
    case Task{+model,link,+i,last}:
      do IO<Row>:
        ok : Unit <- Header.require(Nat.is_eq(i,Local.number(model)),"NO: segment-link-order")
        logical : Local.Logical <- family(model,ctx,last)
        physical : Local.Local <- Local.physical(i,ctx,logical)
        return Row{link,physical,Nat.is_eq(i,0n)}

def ready(task: Task,ctx: Local.Context) -> IO.OP<Row>:
  Workers.observe(Row,prepare(task,ctx))

def prepared(batch: Batch,+ctx: Local.Context) -> List<IO.OP<Row>>:
  match batch:
    case Single{a}: [ready(a,ctx)]
    case Pair{a,b}:
      x y = ready(a,ctx) ready(b,ctx)
      [x,y]
    case Joined{a,b}:
      left right = prepared(a,ctx) prepared(b,ctx)
      List.append(&1,IO.OP<Row>,left,right)

def row_step(row: Row,c: B.Code,m: B.Code,st: State) -> IO(State):
  Row{link,local,first} = row
  step(link,local,c,m,st,first)

def apply(xs: List<IO.OP<Row>>,+c: B.Code,+m: B.Code,st: State) -> IO(State):
  match xs:
    case []: IO.pure(State,st)
    case outcome <> tail:
      do IO<State>:
        row : Row <- Workers.result(Row,outcome)
        next : State <- row_step(row,c,m,st)
        apply(tail,c,m,next)

def advanced(xs: List<IO.OP<Row>>,c: B.Code,m: B.Code,st: State) -> IO.OP<State>:
  Workers.observe(State,apply(xs,c,m,st))

# The previous batch carries shared FOLD state. Overlap its ordered transport
# with the next pair's local equations. A numerical refusal is replayed only
# when its turn in file order arrives.
def pipeline(xs: List<&2,Batch>,placed: List<IO.OP<Row>>,+ctx: Local.Context,+c: B.Code,+m: B.Code,st: State) -> IO(State):
  match xs:
    case []: apply(placed,c,m,st)
    case task <> tail:
      done next = advanced(placed,c,m,st) prepared(task,ctx)
      do IO<State>:
        state : State <- Workers.result(State,done)
        pipeline(tail,next,ctx,c,m,state)

def start(xs: List<&2,Batch>,+ctx: Local.Context,c: B.Code,m: B.Code,st: State) -> IO(State):
  match xs:
    case []: IO.pure(State,st)
    case first <> tail: pipeline(tail,prepared(first,ctx),ctx,c,m,st)

def serial(models: Inputs.Batches,links: List<&2,Q.Link>,+ctx: Local.Context,+c: B.Code,+m: B.Code,state: State,i: Nat) -> IO(State):
  match models links:
    case Nil{} Nil{}: IO.pure(State,state)
    case Con{+model,+tail} Con{link,rest}:
      +idx = i
      do IO<State>:
        ok : Unit <- Header.require(Nat.is_eq(idx,Local.number(model)),"NO: segment-link-order")
        logical : Local.Logical <- family(model,ctx,List.is_empty(&2,M.Inputs,tail))
        physical : Local.Local <- Local.physical(idx,ctx,logical)
        after : State <- step(link,physical,c,m,state,Nat.is_eq(idx,0n))
        serial(tail,rest,ctx,c,m,after,1n+idx)
    case _ _: IO.die(State,1,"NO: segment-link-count")

def schedule(workers: U32,models: Inputs.Batches,links: List<&2,Q.Link>,ctx: Local.Context,c: B.Code,m: B.Code,st: State,i: Nat) -> IO(State):
  match workers:
    case 1: serial(models,links,ctx,c,m,st,i)
    case +n: start(window(n,batches(models,links,i)),ctx,c,m,st)

def walk(models: Inputs.Batches,links: List<&2,Q.Link>,ctx: Local.Context,c: B.Code,m: B.Code,st: State,i: Nat) -> IO(State):
  do IO<State>:
    n : U32 <- IO.thread_count()
    schedule(n,models,links,ctx,c,m,st,i)

def finish(st: State,c: B.Code,m: B.Code,later: List<&2,S.Stage>,events: Trace.Events,items: List<&2,Plan.Item>) -> IO(Own.First):
  State{cur,rows} = st
  do IO<Own.First>:
    after : Trace.Events <- Fold.finish(Transport.restore(cur),c,m,later)
    Batt.checked(events,after,List.reverse(&2,Own.Pending,rows),items)

def basis(s: Transport.State) -> Project.Basis:
  Transport.State{_,b,_} = s
  b

def closed(ctx: Local.Context,models: Inputs.Batches,+events: Trace.Events,items: List<&2,Plan.Item>) -> IO(Own.First):
  match ctx:
    case Local.Context{book,Q.Shape{+c,+m,+links,+later},geometry,profile,_}:
      do IO<Own.First>:
        +initial : Transport.State <- Transport.begin(events,c,later)
        context : Local.Context = Local.Context{book,Q.Shape{c,m,links,later},geometry,profile,Some{basis(initial)}}
        done : State <- walk(models,links,context,c,m,State{initial,[]},0n)
        finish(done,c,m,later,events,items)

def verify(models: Inputs.Batches,events: Trace.Events,+items: List<&2,Plan.Item>,profile: PT.Profile) -> IO(Own.First):
  do IO<Own.First>:
    ctx : Local.Context <- Local.context(items,profile)
    closed(ctx,models,events,items)
