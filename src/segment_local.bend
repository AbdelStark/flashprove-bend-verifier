import Base
import ./segment_u3.bend as Dense
import ./segment_projection.bend as Project
import ./base_check.bend as B
import ./fold.bend as F
import ./extension.bend as X
import ./oracle_sample.bend as Sample
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
  Context{layout: Layout.Book, shape: Shape.Shape, geometry: List<&2,G.Segment>, profile: PT.Profile, basis: Maybe<&2,Project.Basis>}

def context(+items: List<&2,P.Item>,+profile: PT.Profile) -> IO(Context):
  do IO<Context>:
    raw : H.Bytes <- Codes.item(items,"layout")
    layout : Layout.Book <- Layout.parse(raw)
    shape : Shape.Shape <- Shape.load(items)
    return Context{layout,shape,G.select(profile),profile,None{}}

def width(table: Layout.Matrix) -> IO(Nat):
  Layout.Matrix{_,rows,n,_,_} = table
  do IO<Nat>:
    ok : Unit <- Header.require(Nat.is_eq(rows,1n),"NO: segment-U3-rows")
    return n

def slots(g: G.Segment) -> Nat:
  G.Segment{_,_,n,_} = g
  n

type Logical is Data:
  Logical{row: Batch.Row,packed: Frame.Forms,pending: Maybe<&2,Own.Pending>}

def u3_live(row: Batch.Row,n: Nat) -> Bool:
  Batch.Row{reads,_,_} = row
  Cover.form(Cover.u3(reads,[]),n)

def combined(packed: Dense.Packing,id: Nat,rs: List<&2,M.Read>,v: B.Elements,y: X.E3,pending: Maybe<&2,Own.Pending>) -> IO(Logical):
  Dense.Packed{form,ok} = packed
  do IO<Logical>:
    check : Unit <- Header.require(ok,"NO: segment-zero-U3-column")
    return Logical{Batch.Row{Dense.others(rs),v,y},[Frame.On{id,False{},form}],pending}

def regular(+row: Batch.Row,n: Nat,pending: Maybe<&2,Own.Pending>) -> IO(Logical):
  do IO<Logical>:
    ok : Unit <- Header.require(u3_live(row,n),"NO: segment-zero-U3-column")
    return Logical{row,[],pending}

def dense(valid: Bool,+rs: List<&2,M.Read>,v: B.Elements,y: X.E3,pending: Maybe<&2,Own.Pending>,
    bs: Layout.Tiles,+n: Nat,id: Nat,row_bits: Nat,col_bits: Nat,basis: Project.Basis) -> IO(Logical):
  match valid basis:
    case True{} Project.Basis{gs,gr,_}:
      +bits = Sample.row_bits(n)
      do IO<Logical>:
        check : Unit <- Header.require(Dense.fits(rs,bits),"NO: segment-zero-U3-column")
        vals : List<X.E3> = Array.to_list(X.E3,Dense.populate(rs,Array.new(X.E3,bits,F.zero())))
        combined(Dense.scan(bs,gs,gr,row_bits,col_bits,vals),id,rs,v,y,pending)
    case False{} _: regular(Batch.Row{rs,v,y},n,pending)

def preparing(row: Batch.Row,pending: Maybe<&2,Own.Pending>,+link: Nat,table: Layout.Matrix,
    member: Frame.Member,code: B.Code,basis: Project.Basis) -> IO(Logical):
  Batch.Row{+rs,v,y} = row
  Layout.Matrix{_,_,+n,+bs,_} = table
  Frame.Member{id,+rows,_,_,keep} = member
  B.Code{_,+cols,_} = code
  good = Bool.not(keep) && Dense.local(rs,link,Sample.row_bits(n),n) && Dense.spans(bs,0n,n,rows,cols)
  dense(good,rs,v,y,pending,bs,n,id,Sample.row_bits(rows),Sample.row_bits(cols),basis)

def prepare(row: Batch.Row,pending: Maybe<&2,Own.Pending>,+link: Nat,+table: Layout.Matrix,shape: Shape.Shape,basis: Project.Basis) -> IO(Logical):
  Layout.Matrix{index,_,_,_,_} = table
  Shape.Shape{c,_,links,_} = shape
  do IO<Logical>:
    l : Shape.Link <- K.need(Shape.Link,List.get(&2,Shape.Link,links,link),"NO: segment-layout-link")
    m : Frame.Member <- Layout.member(l,index)
    preparing(row,pending,link,table,m,c,basis)

def covered(basis: Maybe<&2,Project.Basis>,row: Batch.Row,pending: Maybe<&2,Own.Pending>,
    link: Nat,table: Layout.Matrix,shape: Shape.Shape,n: Nat) -> IO(Logical):
  match basis:
    case None{}: regular(row,n,pending)
    case Some{b}: prepare(row,pending,link,table,shape,b)

def compute(+input: M.Inputs,ctx: Context,family: Family) -> IO(Logical):
  Context{book,shape,geo,_,basis} = ctx
  Family{+before,+after,fns,free,pending} = family
  +link = number(input)
  do IO<Logical>:
    +g : G.Segment <- K.need(G.Segment,List.get(&2,G.Segment,geo,link),"NO: segment-geometry")
    +table : Layout.Matrix <- Layout.lookup(Map.get(Maybe<&2,Layout.Matrix>,None{},book,Layout.key(link,"U3")))
    +n : Nat <- width(table)
    p : Small.Contribution <- Small.compute(input,g,fns,n,List.length(&2,M.Aff,before),List.length(&2,M.Aff,after))
    +row : Batch.Row <- Batch.combine(before,after,p,slots(g),free)
    covered(basis,row,pending,link,table,shape,n)

type Local is Data:
  Local{equation: Frame.Equation,pending: Maybe<&2,Own.Pending>}

def additional(eq: Frame.Equation,packed: Frame.Forms) -> Frame.Equation:
  Frame.Equation{forms,y} = eq
  Frame.Equation{List.append(&2,Frame.On,packed,forms),y}

def physical(link: Nat,ctx: Context,p: Logical) -> IO(Local):
  Context{book,shape,_,_,basis} = ctx
  Logical{row,packed,pending} = p
  do IO<Local>:
    eq : Frame.Equation <- Batch.physical(shape,book,link,row,basis)
    return Local{additional(eq,packed),pending}

def at_attention(+input: M.Inputs,ctx: Context) -> IO(Logical):
  do IO<Logical>:
    p : Attention.Prepared <- Attention.compute(input)
    compute(input,ctx,attention(p))

def at_head(+input: M.Inputs,+ctx: Context) -> IO(Logical):
  Context{_,_,_,profile,_} = ctx
  do IO<Logical>:
    h : Head.Prepared <- Head.compute(input,profile)
    compute(input,ctx,head(h))

def feed(p: Feed.Prepared) -> Family:
  Feed.Prepared{before,after,fns,_,free,pending} = p
  Family{before,after,fns,Some{free},Some{pending}}

def at_feed(+input: M.Inputs,+ctx: Context) -> IO(Logical):
  Context{_,_,_,p,_} = ctx
  do IO<Logical>:
    f : Feed.Prepared <- Feed.compute(input,p)
    compute(input,ctx,feed(f))
