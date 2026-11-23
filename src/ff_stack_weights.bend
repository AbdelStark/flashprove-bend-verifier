import Base
import ./ff_stack.bend as S
import ./ff_stack_panels.bend as D
import ./ff_stack_rotary.bend as Rot
import ./ff_shape.bend as G
import ./weight_types.bend as W
import ./weight_rows.bend as WR
import ./weight_catalog.bend as Catalog
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./policy_tables.bend as Tables
import ./policy_statement.bend as Statement
import ./oracle_sample.bend as Sample
import ./key_stage_openings.bend as K
import ./row_tensor.bend as T
import ./extension.bend as X
import ./fold.bend as F
import ./base_check.bend as B
import ./header.bend as H

type State is Data:
  State{shape:G.Shape,key:B.Elements,point:B.Elements,stack:A.Values,units:List<&2,W.WeightUnit>,group:Nat,
    kl:List<&2,U32>,rot:Rot.Point}

def layout(+s:G.Shape) -> W.Layout:
  Bool.pick(Unit -> W.Layout,Nat.is_eq(G.field(s,"lt"),6n),_ => Catalog.small(),_ => Catalog.full())(Unit{})
def units(+g:W.Layout) -> List<&2,W.WeightUnit>:
  W.Layout{_,_,us} = g
  us
def groups(+u:W.WeightUnit) -> List<&2,W.Group>:
  W.WeightUnit{_,_,_,_,_,_,gs} = u
  gs

def equality(+z:B.Elements,+bits:Nat,+high:Nat) -> W.Factor:
  +xs = z
  W.Equality{F.take(X.E3,xs,bits),F.take(X.E3,S.fold_eq(List.drop(&2,X.E3,xs,bits)),high)}

def places(+n:Nat,+first:Nat,+step:Nat,+z:B.Elements,+seg:G.Segment,+acc:B.Elements) -> B.Elements:
  match n:
    case 0n: acc
    case 1n+k:
      +j = k
      c = Nat.div(G.pos(seg,Nat.add(first,Nat.mul(j,step))),step)
      places(j,first,step,z,seg,A.eq(z,c) <> acc)

def public_factor(+s:G.Shape,+key:B.Elements,+k:Nat,+bits:Nat,+high:Nat) -> W.Factor:
  +name = D.name(k)
  +z = A.rev(G.zj(s,key,name))
  start = Bool.pick(Nat,Nat.is_eq(k,6n) || Nat.is_eq(k,7n),G.field(s,"fe"),0n)
  W.Equality{F.take(X.E3,z,bits),places(high,start,A.size(bits),A.rev(List.drop(&2,X.E3,z,bits)),G.segment(s,name),[])}

def qk_factor(+r:Rot.Point,+active:Bool,+hd:Bool) -> W.Factor:
  Rot.Point{heads,on,off} = r
  W.ArrayFactor{Bool.pick(B.Elements,hd,heads,Bool.pick(B.Elements,active,on,off))}

def other(+s:G.Shape,+key:B.Elements,+rs:B.Elements,+k:Nat,+wy:Nat,+layer:Nat,+name:String,+bits:Nat,+high:Nat,+kl:List<&2,U32>,+rot:Rot.Point) -> W.Factor:
  enabled = Nat.is_eq(D.word(kl,Nat.add(Nat.mul(13n,layer),12n)),1n)
  get = Bool.pick(Unit -> W.Factor,Nat.is_eq(k,11n),_ => qk_factor(rot,enabled,String.eq(name,"hd")),
    _ => Bool.pick(Unit -> W.Factor,String.eq(name,"e"),
      _ => equality(A.slice(rs,wy,Sample.row_bits(G.field(s,"NE"))),bits,high),
      _ => public_factor(s,key,k,bits,high))(Unit{}))
  get(Unit{})

def factor(+d:State,+k:Nat,+wy:Nat,+layer:Nat,+g:W.Group) -> W.Factor:
  State{+s,key,+rs,_,_,_,kl,rot} = d
  W.Group{+name,_,_,_,high,bits,_,_,_} = g
  get = Bool.pick(Unit -> W.Factor,String.eq(name,"kk"),
    _ => equality(F.take(X.E3,rs,wy),bits,high),
    _ => other(s,key,rs,k,wy,layer,name,bits,high,kl,rot))
  get(Unit{})

def fs(+gs:List<&2,W.Group>,+d:State,+k:Nat,+wy:Nat,+l:Nat) -> List<&2,W.Factor>:
  match gs:
    case []: []
    case g <> tail: factor(d,k,wy,l,g) <> fs(tail,d,k,wy,l)

def kind(+k:Nat,+moe:Bool) -> Nat:
  match k:
    case 0n: Bool.pick(Nat,moe,5n,3n)
    case 1n: Bool.pick(Nat,moe,6n,4n)
    case 2n: 2n
    case 3n: 9n
    case 4n: 1n
    case 5n: 11n
    case 6n: 7n
    case 7n: 8n
    case 10n: 10n
    case _: 0n

def claim(+id:Nat,+l:Nat,+f:List<&2,W.Factor>,+v:A.Value) -> W.Claim:
  A.Value{x,slot,b} = v
  W.Claim{id,l,f,slot,x,b}

def batch(+n:Nat,+i:Nat,+d:State,+k:Nat,+lm:Nat,+first:Nat,+wy:Nat,+acc:List<&2,W.Claim>) -> IO(List<&2,W.Claim>):
  match n:
    case 0n: IO.pure(List<&2,W.Claim>,acc)
    case 1n+rest:
      State{+s,_,_,vs,us,g,_,_} = d
      +l = Nat.add(Nat.mul(g,G.field(s,"Lam")),D.layer(k,i,lm))
      +id = kind(k,Nat.is_eq(Nat.mod(l,2n),1n))
      v = A.at(vs,Nat.add(S.v0(s),Nat.add(first,i)))
      do IO<List<&2,W.Claim>>:
        unit : W.WeightUnit <- WR.unit(us,id,l)
        batch(rest,1n+i,d,k,lm,first,wy,claim(id,l,fs(groups(unit),d,k,wy,l),v) <> acc)

def loop(+xs:D.Panels,+d:State,+acc:List<&2,W.Claim>) -> IO(List<&2,W.Claim>):
  match xs:
    case []: IO.pure(List<&2,W.Claim>,List.reverse(&2,W.Claim,acc))
    case D.Panel{D.Spec{+k,lm},first,ni,_,_,wy,_} <> tail:
      n = Bool.pick(Nat,D.weighted(k),Bool.pick(Nat,D.route(k),1n,ni),0n)
      do IO<List<&2,W.Claim>>:
        next : List<&2,W.Claim> <- batch(n,0n,d,k,lm,first,wy,acc)
        loop(tail,d,next)

def histogram(+vs:List<&2,U32>,+et:B.Elements,buf:Array<X.E3>) -> Array<X.E3>:
  match vs et:
    case Con{+i,tail} Con{x,more}: histogram(tail,more,Rot.add(Array.get(X.E3,buf,i),i,x))
    case _ _: buf

def embed_groups(+gs:List<&2,W.Group>,+tokens:List<&2,U32>,+time:B.Elements,+features:B.Elements) -> List<&2,W.Factor>:
  match gs:
    case []: []
    case W.Group{name,_,_,+n,high,bits,_,_,_} <> tail:
      select = Bool.pick(Unit -> W.Factor,String.eq(name,"v"),
        _ => W.ArrayFactor{F.take(X.E3,Rot.list(Array.to_list(X.E3,histogram(tokens,time,Array.new(X.E3,Sample.row_bits(n),F.zero()))),[]),n)},
        _ => equality(features,bits,high))
      select(Unit{}) <> embed_groups(tail,tokens,time,features)

def embedding(+v:A.Values,+s:G.Shape,+units:List<&2,W.WeightUnit>,+layers:Nat,+words:List<&2,U32>,+ze:B.Elements,+tkh:B.Elements,+cs:List<&2,W.Claim>) -> IO(List<&2,W.Claim>):
  match v:
    case []: IO.pure(List<&2,W.Claim>,cs)
    case [x]:
      +l = layers
      +ls = G.field(s,"ls")
      feats = A.rev(F.cat(X.E3,tkh,F.take(X.E3,ze,ls)))
      eta = S.fold_eq(A.rev(List.drop(&2,X.E3,ze,ls)))
      do IO<List<&2,W.Claim>>:
        unit : W.WeightUnit <- WR.unit(units,12n,l)
        return F.cat(W.Claim,cs,[claim(12n,l,embed_groups(groups(unit),words,eta,feats),x)])
    case _: IO.die(List<&2,W.Claim>,1,"NO: G-embedding-arity")

def claims(+s:G.Shape,+link:Nat,+key:B.Elements,+st:Statement.Statement,+terms:P.Check,+stack:P.Check,
    +ze:B.Elements,+tkh:B.Elements,+vs:A.Values) -> IO(List<&2,W.Claim>):
  Statement.Statement{_,words,_,Tables.Tables{_,_,rot,_},+kl,_,_,_} = st
  +us = units(layout(s))
  +d : State = State{s,key,A.rev(P.point(stack)),P.ends(stack),us,Nat.div(link,2n),kl,Rot.point(s,key,P.point(terms),rot)}
  do IO<List<&2,W.Claim>>:
    cs : List<&2,W.Claim> <- loop(D.panels(s),d,[])
    embedding(vs,s,us,Nat.div(Nat.mul(F.count(U32,kl,0n),2n),29n),words,ze,tkh,cs)
