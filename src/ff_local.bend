import Base
import ./ff_shape.bend as G
import ./ff_rounds.bend as R
import ./ff_catalog.bend as Catalog
import ./ff_norm.bend as Norm
import ./ff_gates.bend as Gate
import ./ff_tables.bend as Tables
import ./segment_model.bend as M
import ./segment_attention.bend as Attention
import ./segment_attention_psc.bend as P
import ./segment_attention_rounds.bend as Round
import ./segment_attention_aff.bend as A
import ./segment_attention_scores.bend as C
import ./segment_planes.bend as Pl
import ./segment_forest.bend as Forest
import ./segment_tables.bend as S
import ./key_stage_trace.bend as Trace
import ./plan_types.bend as Profile
import ./policy_statement.bend as St
import ./base_check.bend as B
import ./header.bend as H
import ./fold.bend as F

type Context is Data:
  Context{shape:G.Shape,key:B.Elements,heard:R.Heard}
type Prefix is Data:
  Prefix{rows:M.Equations,functions:M.Functionals}
def lt(p:Profile.Profile) -> Nat:
  match p:
    case Profile.SmallExact{}: 6n
    case Profile.SmallClipped{}: 6n
    case _: 10n
def hear(model:M.Inputs,p:Profile.Profile) -> IO(Context):
  M.Inputs{+link,main,_,events,_,_,_} = model
  +key = Attention.point(main)
  +first = Nat.is_eq(link,0n)
  do IO<Context>:
    +s : G.Shape <- Catalog.shape(lt(p),first)
    +n : Nat = G.field(s,"forest_slots")
    tail : Trace.Events <- Attention.rest(events,n)
    cur : P.Cursor <- Round.scan(tail,n,[])
    h : R.Heard <- R.receive(cur,s,key,first)
    return Context{s,key,h}
def scales(st:St.Statement) -> List<&2,U32>:
  St.Statement{_,_,_,_,ws,_,_,_} = st
  ws
def before(+s:G.Shape,h:R.Heard,group:Nat,st:St.Statement) -> A.Equations:
  R.Heard{R.Levels{sq,ga,gr},R.Tokens{tv,+tt,stack},R.Coins{+w,p,g,o,_},R.Points{_,rho,ex,_,_},_} = h
  a = Norm.squares(s,sq,w,g,rho)
  b = Norm.rows(s,group,scales(st),tv,p,o,w)
  C.cat(a,C.cat(b,C.cat(Gate.reads(s,tt),Gate.groups(s,ga,gr,stack,ex))))
def suffix(s:G.Shape,h:R.Heard) -> A.Equations:
  R.Heard{_,_,_,R.Points{_,_,_,_,tkh},c} = h
  Gate.embedding(s,tkh,Round.declared(c))
def offsets(+s:G.Shape) -> List<&2,Nat>:
  [G.head_cols(s,"b","bit0"),G.head_cols(s,"b","bit1"),G.head_cols(s,"b","pin")]
def bundle(+s:G.Shape,key:B.Elements,+h:R.Heard,+link:Nat,st:St.Statement,main:Forest.Claims,planes:Pl.Parts) -> Prefix:
  Pl.Parts{rows,fs} = planes
  +u = G.field(s,"u3")
  pre = A.equations(before(s,h,Nat.div(link,2n),st),link,u,[])
  extra = A.equations(suffix(s,h),link,u,[])
  Prefix{F.cat(M.Aff,M.mask_rows(main),F.cat(M.Aff,pre,F.cat(M.Aff,rows,extra))),
    F.cat(M.Functional,Tables.all(s,key,h),fs)}
def prefix(c:Context,model:M.Inputs) -> IO(Prefix):
  Context{+s,key,h} = c
  M.Inputs{+link,+main,_,_,st,shape,_} = model
  do IO<Prefix>:
    ps : Pl.Parts <- Pl.on_u3(main,shape,link,G.field(s,"ltBits"),offsets(s),G.field(s,"u3"),G.field(s,"tree_b"))
    return bundle(s,key,h,link,st,main,ps)
