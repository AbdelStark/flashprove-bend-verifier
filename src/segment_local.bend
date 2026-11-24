import Base
import ./segment_coverage.bend as Cover
import ./smallness_geometry.bend as G
import ./smallness.bend as Small
import ./segment_attention.bend as Attention
import ./segment_head.bend as Head
import ./segment_ff.bend as Feed
import ./segment_layout.bend as Layout
import ./segment_model.bend as M
import ./segment_batch.bend as Batch
import ./fold_frame.bend as Frame
import ./fold_request_shape.bend as Shape
import ./plan.bend as P
import ./plan_types.bend as PT
import ./lin_own.bend as Own
import ./key_stage_openings.bend as K
import ./key_stage_codes.bend as Codes
import ./header.bend as Header
import ./hash_bytes.bend as H

type Family is Data:
  Family{prefix: M.Equations, suffix: M.Equations, functions: M.Functionals, free: Maybe<&2,Nat>, pending: Maybe<&2,Own.Pending>}

def attention(p: Attention.Prepared) -> Family:
  Attention.Prepared{rows,fns,_} = p
  Family{rows,[],fns,None{},None{}}

def head(p: Head.Prepared) -> Family:
  Head.Prepared{before,after,fns,_,free,pending} = p
  Family{before,after,fns,Some{free},Some{pending}}

def number(input: M.Inputs) -> Nat:
  M.Inputs{n,_,_,_,_,_,_} = input
  n

type Context is Data:
  Context{layout: Layout.Book, shape: Shape.Shape, geometry: List<&2,G.Segment>, profile: PT.Profile}

def context(+items: List<&2,P.Item>,+profile: PT.Profile) -> IO(Context):
  do IO<Context>:
    raw : H.Bytes <- Codes.item(items,"layout")
    layout : Layout.Book <- Layout.parse(raw)
    shape : Shape.Shape <- Shape.load(items)
    return Context{layout,shape,G.select(profile),profile}

def width(table: Layout.Matrix) -> IO(Nat):
  Layout.Matrix{_,rows,n,_,_} = table
  do IO<Nat>:
    ok : Unit <- Header.require(Nat.is_eq(rows,1n),"NO: segment-U3-rows")
    return n

def slots(g: G.Segment) -> Nat:
  G.Segment{_,_,n,_} = g
  n

type Logical is Data:
  Logical{row: Batch.Row,pending: Maybe<&2,Own.Pending>}

def u3_live(row: Batch.Row,n: Nat) -> Bool:
  Batch.Row{reads,_,_} = row
  Cover.form(Cover.u3(reads,[]),n)

def compute(+input: M.Inputs,ctx: Context,family: Family) -> IO(Logical):
  Context{book,_,geo,_} = ctx
  Family{+before,+after,fns,free,pending} = family
  +link = number(input)
  do IO<Logical>:
    +g : G.Segment <- K.need(G.Segment,List.get(&2,G.Segment,geo,link),"NO: segment-geometry")
    table : Layout.Matrix <- Layout.lookup(Map.get(Maybe<&2,Layout.Matrix>,None{},book,Layout.key(link,"U3")))
    +n : Nat <- width(table)
    p : Small.Contribution <- Small.compute(input,g,fns,n,List.length(&2,M.Aff,before),List.length(&2,M.Aff,after))
    +row : Batch.Row <- Batch.combine(before,after,p,slots(g),free)
    ok : Unit <- Header.require(u3_live(row,n),"NO: segment-zero-U3-column")
    return Logical{row,pending}

type Local is Data:
  Local{equation: Frame.Equation,pending: Maybe<&2,Own.Pending>}

def physical(link: Nat,ctx: Context,p: Logical) -> IO(Local):
  Context{book,shape,_,_} = ctx
  Logical{row,pending} = p
  do IO<Local>:
    eq : Frame.Equation <- Batch.physical(shape,book,link,row)
    return Local{eq,pending}

def at_attention(+input: M.Inputs,ctx: Context) -> IO(Logical):
  do IO<Logical>:
    p : Attention.Prepared <- Attention.compute(input)
    compute(input,ctx,attention(p))

def at_head(+input: M.Inputs,+ctx: Context) -> IO(Logical):
  Context{_,_,_,profile} = ctx
  do IO<Logical>:
    h : Head.Prepared <- Head.compute(input,profile)
    compute(input,ctx,head(h))

def feed(p: Feed.Prepared) -> Family:
  Feed.Prepared{before,after,fns,_,free,pending} = p
  Family{before,after,fns,Some{free},Some{pending}}

def at_feed(+input: M.Inputs,+ctx: Context) -> IO(Logical):
  Context{_,_,_,p} = ctx
  do IO<Logical>:
    f : Feed.Prepared <- Feed.compute(input,p)
    compute(input,ctx,feed(f))
