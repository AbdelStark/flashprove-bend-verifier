import Base
import ./ff_shape.bend as G
import ./segment_attention_aff.bend as A
import ./segment_attention_points.bend as Z
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F

def name(mat: Nat) -> String:
  match mat:
    case 0n: "af"
    case 1n: "ad"
    case 2n: "ar"
    case 3n: "qa"
    case _: "xbI"

def cell(id:Nat,w:X.E3) -> A.Aff: A.Aff{[A.Cell{id,w}],[],F.zero()}

def bytes(n:Nat,+base:Nat,+stride:Nat,+unit:Nat,+col:Nat,+offset:Nat,+scale:X.E3,acc:List<&2,A.Cell>) -> List<&2,A.Cell>:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      id = Nat.add(Nat.add(offset,Nat.div(Nat.add(base,Nat.mul(i,stride)),unit)),col)
      w = E.mul(scale,A.nat(A.size(Nat.mul(8n,i))))
      bytes(i,base,stride,unit,col,offset,scale,A.Cell{id,w} <> acc)
def from(t:G.Tensor,table:Nat,unit:Nat,lam:Nat,col:Nat,w:X.E3,acc:List<&2,A.Cell>) -> List<&2,A.Cell>:
  G.Tensor{_,off,n,count,+width} = t
  bytes(n,Nat.add(off,Nat.mul(lam,width)),Nat.mul(count,width),unit,col,table,w,acc)
def table(s:G.Shape,t:G.Tensor,point:String) -> Nat:
  G.Tensor{m,_,_,_,_} = t
  G.head_cols(s,name(m),point)
def direct(+s:G.Shape,n:String,p:String,lam:Nat,col:Nat,unit:Nat) -> A.Aff:
  +t = G.tensor(s,n)
  A.Aff{from(t,table(s,t,p),unit,lam,col,F.one(),[]),[],F.zero()}
def sh(s:G.Shape,n:String,p:String,lam:Nat,col:Nat) -> A.Aff: direct(s,n,p,lam,col,1n)
def long(+s:G.Shape,n:String,p:String,lam:Nat,col:Nat) -> A.Aff: direct(s,n,p,lam,col,G.field(s,"S2"))

def walk(w:B.Elements,n:Nat,+tensor:G.Tensor,+tab:Nat,+s2:Nat,+lam:Nat,col:Nat,acc:List<&2,A.Cell>) -> A.Aff:
  match w n:
    case _ 0n: A.Aff{acc,[],F.zero()}
    case Con{weight,tail} 1n+k:
      +j = col
      walk(tail,k,tensor,tab,s2,lam,1n+j,from(tensor,tab,s2,lam,j,weight,acc))
    case _ _: A.Aff{acc,[],F.zero()}

def weighted(n:Nat,w:B.Elements,+start:Nat,tensor:G.Tensor,tab:Nat,s2:Nat,lam:Nat,bias:Nat,acc:List<&2,A.Cell>) -> A.Aff:
  walk(List.drop(&2,X.E3,w,start),n,tensor,tab,s2,lam,Nat.sub(start,bias),acc)

def weights(n:Nat,+z:B.Elements,+seg:G.Segment,+unit:Nat,acc:B.Elements) -> B.Elements:
  match n:
    case 0n: acc
    case 1n+k:
      +i = k
      weights(i,z,seg,unit,A.eq(z,Nat.div(G.pos(seg,Nat.mul(unit,i)),unit)) <> acc)

def width(s:G.Segment) -> Nat:
  G.Segment{_,n,_,_,_} = s
  n
def count(s:G.Segment) -> Nat:
  G.Segment{_,_,n,_,_} = s
  n
def ws(+s:G.Shape,key:B.Elements,+sn:String,+log:Nat) -> B.Elements:
  +seg = G.segment(s,sn)
  +bits = width(seg)
  +n = count(seg)
  +unit = A.size(log)
  weights(Nat.div(n,unit),Z.take(G.zj(s,key,sn),Nat.sub(bits,log)),seg,unit,[])

def segment_weights(+s:G.Shape,key:B.Elements,sn:String) -> B.Elements: ws(s,key,sn,G.field(s,"ls"))
def length(t:G.Tensor) -> Nat:
  G.Tensor{_,_,_,_,n} = t
  n

def bounded(+s:G.Shape,ws:B.Elements,n:String,point:String,lam:Nat,+low:Nat,hi:Nat,base:Nat) -> A.Aff:
  +ten = G.tensor(s,n)
  +size = G.field(s,"S2")
  weighted(Nat.div(Nat.sub(hi,low),size),ws,Nat.div(low,size),ten,table(s,ten,point),size,lam,Nat.div(base,size),[])

def whole(+s:G.Shape,+ws:B.Elements,n:String,point:String,lam:Nat) -> A.Aff:
  +ten = G.tensor(s,n)
  +ncols = List.length(&2,X.E3,ws)
  weighted(ncols,ws,0n,ten,table(s,ten,point),G.field(s,"S2"),lam,0n,[])

def residual(+s:G.Shape,ws:B.Elements,pt:String,+stream:Nat) -> A.Aff:
  +last = Nat.mul(2n,G.field(s,"Lam"))
  +edge = Nat.is_eq(stream,0n) || Nat.is_eq(stream,last)
  tn = Bool.pick(String,edge,"xb","xs")
  mn = Bool.pick(String,edge,Bool.pick(String,Nat.is_eq(stream,0n),"xbI","xbO"),"af")
  +size = G.field(s,"S2")
  weighted(Nat.div(G.field(s,"d"),size),ws,0n,G.tensor(s,tn),G.head_cols(s,mn,pt),size,Nat.mul(Nat.sub(stream,1n),Bool.pick(Nat,edge,0n,1n)),0n,[])
def xs(+s:G.Shape,key:B.Elements,sn:String,point:String,stream:Nat) -> A.Aff:
  residual(s,segment_weights(s,key,sn),point,stream)
