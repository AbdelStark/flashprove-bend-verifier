import Base
import ./fold.bend as F
import ./fold_frame.bend as R
import ./fold_carry.bend as C
import ./fold_open.bend as O
import ./fold_cs.bend as S
import ./fold_request_shape.bend as Q
import ./leaf_shape.bend as L
import ./base_check.bend as B
import ./opening_bytes.bend as OB
import ./hash_bytes.bend as H
import ./extension.bend as E

# All three opened segment trees have the segment's code depth. R7.1 puts all main
# symbols first and all mask symbols second within each tree of a prover message.
type Span is Data:
  Span{limb: Nat, count: Nat, base: Bool}
type Physical is Data:
  Physical{source: O.Source, kept: List<&2,Span>}

def segs(ns: Q.Notices, +ms: R.Members, +mask: Bool, rev: List<&2,O.Segment>) -> List<&2,O.Segment>:
  match ns:
    case []: List.reverse(&2,O.Segment,rev)
    case Q.Notice{R.Member{+id,n,d,m,keep},_,_} <> tail:
      +len = Bool.pick(Nat,mask,m,n)
      part = Bool.pick(O.Part,mask,O.Mask{},Bool.pick(O.Part,keep,O.Kept{},O.Main{}))
      base = Bool.not(mask) && Nat.is_eq(d,1n)
      offset = R.rank(ms,True{},mask,id,O.ceil_power(len),0n)
      next: O.Segment = O.Segment{part,base,offset,len}
      segs(tail,ms,mask,next <> rev)

def spans(ns: Q.Notices, +limb: Nat, +rev: List<&2,Span>) -> List<&2,Span>:
  match ns:
    case []: List.reverse(&2,Span,rev)
    case Q.Notice{R.Member{_,+n,+d,_,kept},_,_} <> rest:
      next: Span = Span{limb,n,Nat.is_eq(d,1n)}
      spans(rest,Nat.add(limb,Nat.mul(2n,Nat.mul(n,d))),Bool.pick(List<&2,Span>,kept,next <> rev,rev))

def tree(+ns: Q.Notices, +ms: R.Members, a: Nat, fresh: Nat, cols: OB.Columns) -> Physical:
  +st = segs(ns,ms,False{},[])
  rows = List.concat(&2,O.Segment,[st,segs(ns,ms,True{},[]),[O.fresh_run(fresh)]])
  Physical{O.Source{a,rows,cols},spans(ns,0n,[])}

def trees(xs: List<&2,OB.Columns>, i: Nat, +ns: Q.Notices, +ms: R.Members, +a: Nat, +fresh: Nat) -> List<&2,Physical>:
  match xs:
    case []: []
    case cols <> tail:
      +j = i
      part = tree(Q.moment(ns,j,[]),ms,a,Bool.pick(Nat,Nat.is_eq(j,0n),fresh,0n),cols)
      part <> trees(tail,1n+j,ns,ms,a,fresh)

def sources(xs: List<&2,Physical>) -> List<&2,O.Source>:
  match xs:
    case []: []
    case Physical{s,_} <> more: s <> sources(more)

def find(+i: Nat, xs: OB.Columns) -> Maybe<&2,H.Bytes>:
  match xs:
    case []: None{}
    case OB.Column{j,w} <> more:
      Maybe.or(&2,H.Bytes,Bool.pick(Maybe<&2,H.Bytes>,Nat.is_eq(i,j),Some{w},None{}),find(i,more))

def values(n: Nat, +base: Bool, xs: H.Bytes, acc: B.Elements) -> Maybe<&2,B.Elements>:
  match n base xs:
    case 0n _ _: Some{List.reverse(&2,E.E3,acc)}
    case 1n+k True{} Con{a,Con{b,tail}}: values(k,True{},tail,E.E3{b,a,0,0,0,0} <> acc)
    case 1n+k False{} Con{a,Con{b,Con{c,Con{d,Con{e,Con{f,tail}}}}}}:
      values(k,False{},tail,E.E3{b,a,d,c,f,e} <> acc)
    case _ _ _: None{}

def append(xs: Maybe<&2,B.Elements>, ys: Maybe<&2,B.Elements>) -> Maybe<&2,B.Elements>:
  match xs ys:
    case Some{x} Some{y}: Some{F.cat(E.E3,x,y)}
    case _ _: None{}

def parts(xs: List<&2,Span>, +raw: H.Bytes) -> Maybe<&2,B.Elements>:
  match xs:
    case []: Some{[]}
    case Span{i,n,b} <> rest: append(values(n,b,List.drop(&2,U32,raw,i),[]),parts(rest,raw))

def kept(xs: List<&2,Span>, raw: Maybe<&2,H.Bytes>) -> Maybe<&2,B.Elements>:
  match raw:
    case Some{ws}: parts(xs,ws)
    case _: None{}

def hold(+i: Nat, ts: List<&2,Physical>) -> Maybe<&2,B.Elements>:
  match ts:
    case []: Some{[]}
    case Physical{_,Nil{}} <> tail: hold(i,tail)
    case Physical{O.Source{_,_,cols},Con{s,rest}} <> tail:
      append(kept(s <> rest,find(i,cols)),hold(i,tail))

def push(draw: S.Draw, acc: List<&2,C.Opening>, xs: Maybe<&2,B.Elements>) -> Maybe<&2,List<&2,C.Opening>>:
  match xs:
    case None{}: None{}
    case Some{k}: Some{C.Opening{draw,k} <> acc}

def opened(xs: S.Draws, +ts: List<&2,Physical>, acc: Maybe<&2,List<&2,C.Opening>>) -> Maybe<&2,List<&2,C.Opening>>:
  match xs acc:
    case Nil{} Some{ys}: Some{List.reverse(&2,C.Opening,ys)}
    case Con{S.Draw{+i,m,n,f},tail} Some{ys}: opened(tail,ts,push(S.Draw{i,m,n,f},ys,hold(i,ts)))
    case _ _: None{}

def finish(ds: Maybe<&2,S.Draws>, ts: List<&2,Physical>, good: Bool) -> Maybe<&2,List<&2,C.Opening>>:
  match ds good:
    case Some{draws} True{}: opened(draws,ts,Some{[]})
    case _ _: None{}

def read(+ns: Q.Notices, +stage: L.Stage, gamma: B.Elements, xs: OB.Places, +cols: List<&2,OB.Columns>, expected: Nat) -> Maybe<&2,List<&2,C.Opening>>:
  L.Stage{B.Code{a,_,_},_,_,h} = stage
  +ts = trees(cols,0n,ns,Q.members(ns),a,S.size(U32.to_nat(h)))
  finish(O.open(sources(ts),stage,gamma,xs),ts,Nat.is_eq(List.length(&2,OB.Columns,cols),expected))
