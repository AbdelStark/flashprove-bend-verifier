import Base
import ./ff_shape.bend as G
import ./ff_reads.bend as Read
import ./ff_lookup_line.bend as Line
import ./fold.bend as F
import ./row_tensor.bend as T
import ./sumcheck.bend as E
import ./extension.bend as X
import ./base_check.bend as B
import ./segment_attention_aff.bend as A
import ./segment_forest.bend as Forest
import ./segment_tables.bend as S
import ./key_stage_lookup_rows.bend as L
import ./key_stage_openings.bend as K
import ./policy_statement.bend as St
import ./header.bend as Header
import ./hash_bytes.bend as H

def code(name: String) -> Nat:
  match name:
    case "G": 0n
    case "U": 1n
    case "GH": 2n
    case "UH": 3n
    case "UT": 4n
    case "QK": 5n
    case "QKH": 6n
    case "N1": 7n
    case "N2": 8n
    case "N1H": 9n
    case "N2H": 10n
    case "O": 11n
    case "D": 12n
    case "V": 13n
    case "OH": 14n
    case "DH": 15n
    case "VH": 16n
    case "ROW": 17n
    case "CN1": 18n
    case "CN2": 19n
    case "CQK": 20n
    case "CV": 21n
    case "F": 22n
    case "G0": 23n
    case "CG": 24n
    case "XR": 25n
    case "LR": 26n
    case "LT": 27n
    case "DD": 28n
    case "LH": 29n
    case "SEL": 30n
    case "MR": 31n
    case "L3": 32n
    case "CLR": 33n
    case _: 34n

type Stage is Data:
  Stage{s:G.Shape,key:B.Elements,scales:H.Bytes,group:Nat}
type Segment is Data:
  Segment{id:Nat,moe:Bool,full:B.Elements,blocks:B.Elements,w:X.E3,ec:X.E3,layer:F.Factors,pad:X.E3}

def cuts(rs:List<&2,G.Run>, +v:B.Elements, +unit:Nat, acc:B.Elements) -> B.Elements:
  match rs:
    case []: List.reverse(&2,X.E3,acc)
    case G.Run{from,n} <> tail:
      got = F.take(X.E3,List.drop(&2,X.E3,v,Nat.div(from,unit)),Nat.div(n,unit))
      cuts(tail,v,unit,List.reverse.go(&2,X.E3,got,acc))

def weights(+p:B.Elements, +seg:G.Segment, +log:Nat) -> B.Elements:
  G.Segment{_,bits,+n,_,+rs} = seg
  +u = A.size(log)
  +count = Nat.div(n,u)
  +zs = F.take(X.E3,p,Nat.sub(bits,log))
  run = Bool.pick(Unit -> B.Elements,Nat.is_lt(count,64n),
    _ => Read.weights(count,zs,seg,u,[]), _ => cuts(rs,F.factor_table(T.eq(A.rev(zs)),F.one()),u,[]))
  run(Unit{})

def pad_value(c:S.Call) -> X.E3:
  S.Call{_,_,_,_,p,_} = c
  A.nat(p)

def one(+s:G.Shape,+key:B.Elements,name:String,+seg:G.Segment,p:X.E3) -> Segment:
  G.Segment{_,_,n,moe,_} = seg
  +call = G.call(s,seg)
  +cols = G.zcol(s,key,call)
  +v = weights(cols,seg,0n)
  +ls = G.field(s,"ls")
  b = Bool.pick(Unit -> B.Elements,Nat.is_eq(Nat.mod(n,A.size(ls)),0n),_ => weights(cols,seg,ls),_ => [])
  Segment{code(name),moe,v,b(Unit{}),A.sum(v,F.zero()),G.e(s,key,call),T.eq(A.rev(F.take(X.E3,G.coordinates(s,key,call),G.field(s,"ll")))),p}

def add(c:Line.Context,id:Nat,scale:X.E3,free:X.E3,acc:A.Aff) -> IO(A.Aff):
  do IO<A.Aff>:
    value : A.Aff <- Line.line(id,c)
    return A.add(acc,A.minus(A.const(free),value),scale)

def layers(n:Nat,+stage:Stage,+seg:Segment,+acc:A.Aff) -> IO(A.Aff):
  match n:
    case 0n: IO.pure(A.Aff,acc)
    case 1n+k:
      Stage{+s,_,scales,group} = stage
      Segment{id,moe,vs,blocks,+weight,ec,point,pad} = seg
      +i = k
      offset = Nat.add(Nat.mul(group,G.field(s,"Lam")),i)
      c: Line.Context = Line.Context{s,i,offset,scales,vs,blocks,weight}
      skip = moe && Nat.is_eq(Nat.mod(i,2n),0n)
      next = Bool.pick(Unit -> IO(A.Aff),skip,_ => IO.pure(A.Aff,acc),
        _ => add(c,id,T.entry(point,i,ec),E.mul(weight,pad),acc))
      do IO<A.Aff>:
        a : A.Aff <- next(Unit{})
        layers(i,stage,seg,a)

def call_index(seg:G.Segment) -> Nat:
  G.Segment{i,_,_,_,_} = seg
  i

def segments(xs:List<&2,G.NamedSegment>,+stage:Stage,+calls:List<&2,S.Call>,acc:A.Aff) -> IO(A.Aff):
  match xs:
    case []: IO.pure(A.Aff,acc)
    case G.NamedSegment{name,+seg} <> tail:
      Stage{+s,key,_,_} = stage
      do IO<A.Aff>:
        c : S.Call <- K.need(S.Call,List.get(&2,S.Call,calls,call_index(seg)),"NO: G-lookup-call")
        entry: Segment = one(s,key,name,seg,pad_value(c))
        next : A.Aff <- layers(G.field(s,"Lam"),stage,entry,acc)
        segments(tail,stage,calls,next)

def declared(s:G.Shape) -> List<&2,G.NamedSegment>:
  G.Shape{_,_,xs,_,_} = s
  xs

def base(own:List<&2,G.Call>,pub:List<&2,S.Call>,+s:G.Shape,+key:B.Elements,+theta:X.E3,+pad:X.E3,i:Nat,acc:X.E3) -> IO(X.E3):
  match own pub:
    case Nil{} Nil{}: IO.pure(X.E3,acc)
    case Con{c,rest} Con{p,tail}:
      +j = i
      v = E.add(E.mul(theta,A.nat(j)),F.sub(pad_value(p),pad))
      base(rest,tail,s,key,theta,pad,1n+j,F.sub(acc,E.mul(v,G.e(s,key,c))))
    case _ _: IO.die(X.E3,1,"NO: G-lookup-arities")

def public_calls(s:S.Forest) -> List<&2,S.Call>:
  S.Forest{_,_,_,_,cs} = s
  cs

def own_calls(s:G.Shape) -> List<&2,G.Call>:
  G.Shape{_,_,_,_,cs} = s
  cs

def join(+s:G.Shape,link:Nat, f:Forest.Claims, st:St.Statement,pub:S.Forest) -> IO(A.Aff):
  Forest.Claims{L.Point{+key,ms,t},alpha,theta,_} = f
  St.Statement{_,_,_,_,scales,_,_,_} = st
  +cs = public_calls(pub)
  do IO<A.Aff>:
    ok : Unit <- Header.require(Nat.is_eq(G.field(s,"gate_clamp"),1n) && Nat.is_eq(G.field(s,"router_clamp"),1n) &&
      Nat.is_eq(G.field(s,"limbs"),5n),"NO: unsupported-G-lookup")
    c : S.Call <- K.need(S.Call,List.head(&2,S.Call,cs),"NO: G-lookup-call")
    +pad : X.E3 = pad_value(c)
    init : X.E3 <- base(own_calls(s),cs,s,key,theta,pad,0n,F.sub(F.sub(alpha,t),pad))
    segments(declared(s),Stage{s,key,scales,Nat.div(link,2n)},cs,A.Aff{[],ms,init})
