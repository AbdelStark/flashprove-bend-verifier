import Base
import ./round_io.bend as RoundIO
import ./opening_bytes.bend as O
import ./key_stage_openings.bend as K
import ./wire_reader.bend as R
import ./hash_bytes.bend as H
import ./merkle.bend as M
import ./plan.bend as P
import ./transcript.bend as T
import ./header.bend as Header
import ./leaf_shape.bend as S
import ./base_check.bend as B
import ./extension.bend as Ext
import ./pow2.bend as P2

# The algebra reads draws in transcript order, including repeats. Columns use Merkle order.
type EntryRound is Data:
  EntryRound{name: String, message: H.Bytes, samples: T.Stream, draws: O.Places, first: O.Columns, further: O.Columns}

type Context is Data:
  Context{cfg: M.Digest, anchor: M.Digest, leaf: M.Digest, run: M.Digest, shape: S.Shape, salt: Nat}

type Cursor is Data:
  Cursor{state: T.State, session: O.Session, book: K.Book, next: Nat, stages: List<&2,S.Stage>,
    lambda: Maybe<&2,Ext.E3>, events: List<&2,EntryRound>}

def power(bits: U32) -> Nat:
  P2.pow2(U32.to_nat(bits))

def tail_width(first: Bool, last: Bool, k: U32, h: U32, rows: U32) -> Nat:
  match first last:
    case _ True{}: 12n
    case True{} False{}: Nat.add(Nat.mul(6n,U32.to_nat(rows)),3n)
    case False{} False{}: Nat.add(Nat.mul(3n,power(k)),Nat.mul(6n,power(h)))

def add_tables(pair: R.Reader & O.Opened, event: EntryRound, left: O.Columns,
  state: T.State, book: K.Book, next: Nat, stages: List<&2,S.Stage>, lambda: Maybe<&2,Ext.E3>, events: List<&2,EntryRound>) -> R.Reader & Cursor:
  (r,O.Opened{right,session}) = pair
  EntryRound{name,msg,stream,draws,_,_} = event
  (r,Cursor{state,session,book,next,stages,lambda,EntryRound{name,msg,stream,draws,left,right} <> events})

def read_second(pair: R.Reader & O.Opened, ctx: Context, +event: EntryRound, xs: O.Places, +n: Nat,
  state: T.State, book: K.Book, next: Nat, stages: List<&2,S.Stage>, lambda: Maybe<&2,Ext.E3>, events: List<&2,EntryRound>) -> IO(R.Reader & Cursor):
  (r,O.Opened{left,session}) = pair
  Context{+config,_,leaf,_,S.Shape{d,_,_,v,_,salt,_,_,_,_},_} = ctx
  form : O.Shape = O.Shape{174,0,U32.to_nat(d),power(v),U32.to_nat(salt),config}
  do IO<R.Reader & Cursor>:
    got : R.Reader & O.Opened <- K.open_at(K.Published{form,leaf},config,List.drop(&2,Nat,xs,n),r,session)
    return add_tables(got,event,left,state,book,next,stages,lambda,events)

def tables(+ctx: Context, r: R.Reader, event: EntryRound, +xs: O.Places, cur: Cursor) -> IO(R.Reader & Cursor):
  Context{+config,anchor,_,_,S.Shape{d,_,_,v,_,salt,+n,m,_,_},_} = ctx
  Cursor{state,session,book,next,stages,lambda,events} = cur
  form : O.Shape = O.Shape{174,0,U32.to_nat(d),power(v),U32.to_nat(salt),config}
  do IO<R.Reader & Cursor>:
    ok : Unit <- Header.require(Nat.is_eq(List.length(&2,Nat,xs),U32.to_nat(U32.add(n,m))),"NO: link-draw-count")
    got : R.Reader & O.Opened <- K.open_at(K.Published{form,anchor},config,List.take(&2,Nat,xs,U32.to_nat(n)),r,session)
    read_second(got,ctx,event,xs,U32.to_nat(n),state,book,next,stages,lambda,events)

def base(name: String, lambda: Maybe<&2,Ext.E3>, +stage: S.Stage, msg: H.Bytes, draws: O.Places, columns: O.Columns) -> IO(Unit):
  match name lambda:
    case "BASE" Some{l}:
      S.Stage{+main,mask,_,_} = stage
      B.Code{depth,_,_} = main
      do IO<Unit>:
        rows : B.Rows <- K.need(B.Rows,B.read(main,mask,msg),"NO: leaf-base-rows")
        Header.require(B.symbols(rows,l,O.positions(depth,draws),columns),"NO: leaf-base-symbols")
    case "CS" _: IO.pure(Unit,Unit{})
    case _ _: IO.die(Unit,1,"NO: leaf-base-lambda")

def switched(pair: R.Reader & O.Opened, +event: EntryRound, stage: S.Stage, cur: Cursor) -> IO(R.Reader & Cursor):
  (r,O.Opened{+cols,session}) = pair
  EntryRound{+name,+msg,stream,+xs,_,_} = event
  Cursor{state,_,book,next,tail,+lambda,events} = cur
  do IO<R.Reader & Cursor>:
    ok : Unit <- base(name,lambda,stage,msg,xs,cols)
    return (r,Cursor{state,session,book,1n+next,tail,lambda,EntryRound{name,msg,stream,xs,cols,[]} <> events})

def switch(ctx: Context, r: R.Reader, +event: EntryRound, +xs: O.Places, cur: Cursor) -> IO(R.Reader & Cursor):
  Context{config,_,_,_,S.Shape{_,_,_,_,_,_,_,_,rows,_},salt} = ctx
  Cursor{state,session,+book,+next,stages,lambda,events} = cur
  match stages:
    case +stage <> +tail:
      S.Stage{B.Code{depth,_,_},_,k,h} = stage
      width = tail_width(Nat.is_eq(next,0n),List.is_empty(&2,S.Stage,tail),k,h,rows)
      do IO<R.Reader & Cursor>:
        root : K.Root <- K.at(book,next)
        got : R.Reader & O.Opened <- K.open_at(K.ordinary(root,depth,width,salt),config,xs,r,session)
        switched(got,event,stage,Cursor{state,O.empty_session(),book,next,tail,lambda,events})
    case _: IO.die(R.Reader & Cursor,1,"NO: leaf-switch-count")

def action(name: String) -> U32:
  match name:
    case "LINK": 1
    case "CS": 2
    case "BASE": 2
    case "BASE lambda": 3
    case _: 0

def dispatch(action: U32, +name: String, +msg: H.Bytes, +stream: T.Stream, +xs: O.Places, ctx: Context, r: R.Reader, +cur: Cursor) -> IO(R.Reader & Cursor):
  match action:
    case 1: tables(ctx,r,EntryRound{name,msg,stream,xs,[],[]},xs,cur)
    case 2: switch(ctx,r,EntryRound{name,msg,stream,xs,[],[]},xs,cur)
    case 3:
      Cursor{state,session,book,next,stages,_,events} = cur
      IO.pure(R.Reader & Cursor,(r,Cursor{state,session,book,next,stages,Some{T.value(Ext.E3,T.element(stream))},EntryRound{name,msg,stream,xs,[],[]} <> events}))
    case _:
      Cursor{state,session,book,next,stages,lambda,events} = cur
      IO.pure(R.Reader & Cursor,(r,Cursor{state,session,book,next,stages,lambda,EntryRound{name,msg,stream,xs,[],[]} <> events}))

def received(pair: R.Reader & RoundIO.Step, round: P.Round, +ctx: Context, cur: Cursor) -> IO(R.Reader & Cursor):
  (r,RoundIO.Step{+msg,state,+stream}) = pair
  P.Round{+name,_,_,_,roots,_,_,_,positions,depth,_,_} = round
  Context{_,_,_,run,_,_} = ctx
  Cursor{_,session,+book,next,stages,lambda,events} = cur
  xs = T.value(O.Places,T.draws(U32.to_nat(positions),U32.to_nat(depth),stream))
  do IO<R.Reader & Cursor>:
    known : K.Book <- K.add(U32.to_nat(roots),msg,run,book,List.length(&2,K.Root,book))
    dispatch(action(name),name,msg,stream,xs,ctx,r,Cursor{state,session,known,next,stages,lambda,events})

def walk(rounds: List<&2,P.Round>, +ctx: Context, pair: R.Reader & Cursor) -> IO(R.Reader & Cursor):
  match rounds pair:
    case Nil{} last: IO.pure(R.Reader & Cursor,last)
    case Con{+round,rest} Tuple{r,+cur}:
      Cursor{state,_,_,_,_,_,_} = cur
      do IO<R.Reader & Cursor>:
        step : R.Reader & RoundIO.Step <- RoundIO.advance(r,state,round)
        next : R.Reader & Cursor <- received(step,round,ctx,cur)
        walk(rest,ctx,next)
