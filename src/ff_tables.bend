import Base
import ./ff_shape.bend as G
import ./ff_rounds.bend as R
import ./segment_attention_psc.bend as P
import ./segment_attention_points.bend as Z
import ./base_check.bend as B
import ./extension.bend as X
import ./fold.bend as F
import ./segment_model.bend as M

type Coordinates is Data:
  Points{z:B.Elements,zt:B.Elements,zv:B.Elements,y:B.Elements,za:B.Elements,zb:B.Elements,ze:B.Elements,pv:B.Elements,rv:B.Elements,rt:B.Elements}
def point(p:Coordinates,k:String) -> B.Elements:
  Points{z,zt,zv,y,za,zb,ze,pv,rv,rt} = p
  match k:
    case "Z": z
    case "zt": zt
    case "Z_V": zv
    case "Y": y
    case "Z_a": za
    case "Z_b": zb
    case "Z_E": ze
    case "P_V": pv
    case "r_tV": rv
    case _: rt

def portions(ns:List<&2,Nat>,+phi:F.Form,+n:Nat,m:Nat,off:Nat,acc:M.Functionals) -> M.Functionals:
  match ns:
    case []: acc
    case count <> tail:
      +j = m
      +i = off
      portions(tail,phi,n,1n+j,Nat.add(i,count),M.Functional{j,n,phi,i} <> acc)
def functions(xs:List<&2,G.NamedTable>,+points:Coordinates,+acc:M.Functionals) -> M.Functionals:
  match xs:
    case []: List.reverse(&2,M.Functional,acc)
    case G.NamedTable{name,p,G.Table{mu,n,off,ns}} <> +tail:
      pick = Bool.pick(Unit -> M.Functionals,String.eq(name,"b"),
        _ => functions(tail,points,acc), _ => functions(tail,points,portions(ns,Z.equality(point(points,p)),n,mu,off,acc)))
      pick(Unit{})
def named(s:G.Shape) -> List<&2,G.NamedTable>:
  G.Shape{_,_,_,ts,_} = s
  ts
def all(+s:G.Shape,+key:B.Elements,h:R.Heard) -> M.Functionals:
  R.Heard{R.Levels{sq,g,gr},R.Tokens{pv,tt,_},_,R.Points{zpv,_,_,ze,_},_} = h
  +z = R.suffix(s,key,"la")
  +la = G.field(s,"la")
  +rt = P.point(tt)
  pts : Coordinates = Points{z,R.suffix(s,key,"lt"),R.last(R.at(sq),la),Z.cat(Z.take(z,G.field(s,"ls")),rt),
    R.last(R.at(g),la),R.last(R.at(gr),la),ze,zpv,P.point(pv),rt}
  functions(named(s),pts,[])
