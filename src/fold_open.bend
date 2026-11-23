import Base
import ./fold.bend as F
import ./fold_cs.bend as CS
import ./fold_verify.bend as FV
import ./leaf_shape.bend as S
import ./base_check.bend as B
import ./opening_bytes.bend as O
import ./hash_bytes.bend as H
import ./goldilocks.bend as G
import ./extension.bend as E
import ./sumcheck.bend as A

# R13.12. Each segment occupies a consecutive run in its authenticated physical column.
# The offset is the first row of its aligned block in the logical main or mask table.
type Part is Data:
  Main{}
  Mask{}
  Fresh{}
  Kept{}
type Segment is Data:
  Segment{part: Part, base: Bool, offset: Nat, count: Nat}
type Source is Data:
  Source{depth: Nat, segments: List<&2,Segment>, columns: O.Columns}
type Weighted is Data:
  Weighted{part: Part, base: Bool, count: Nat, weights: B.Elements}
type Table is Data:
  Table{depth: Nat, values: CS.Draws}
type Packed is Data:
  Packed{sum: E.E3, rest: H.Bytes}

def select(part: Part, main: B.Elements, mask: B.Elements) -> B.Elements:
  match part:
    case Main{}: main
    case _: mask

def add(+d: CS.Draw, part: Part, x: E.E3) -> CS.Draw:
  CS.Draw{i,m,n,f} = d
  match part:
    case Main{}: CS.Draw{i,A.add(m,x),n,f}
    case Mask{}: CS.Draw{i,m,A.add(n,x),f}
    case Fresh{}: CS.Draw{i,m,n,A.add(f,x)}
    case Kept{}: CS.Draw{i,m,n,f}

def segment_weights(+part: Part, main: B.Elements, mask: B.Elements, i: Nat, count: Nat) -> B.Elements:
  match part:
    case Kept{}: CS.zeros(count)
    case Main{}: F.take(E.E3,List.drop(&2,E.E3,main,i),count)
    case _: F.take(E.E3,List.drop(&2,E.E3,mask,i),count)

def plan(xs: List<&2,Segment>, +main: B.Elements, +mask: B.Elements) -> List<&2,Weighted>:
  match xs:
    case []: []
    case Segment{+part,base,i,+count} <> rest:
      weights = segment_weights(part,main,mask,i,count)
      Weighted{part,base,count,weights} <> plan(rest,main,mask)

def consume(count: Nat, weights: B.Elements, +base: Bool, raw: H.Bytes, acc: E.E3) -> Maybe<&2,Packed>:
  match count weights base raw:
    case 0n Nil{} _ ws: Some{Packed{acc,ws}}
    case 1n+k Con{w,tail} True{} Con{l,Con{h,ws}}:
      consume(k,tail,True{},ws,A.add(acc,CS.scale(G.Gl{h,l},w)))
    case 1n+k Con{w,tail} False{} Con{a,Con{b,Con{c,Con{d,Con{e,Con{f,ws}}}}}}:
      consume(k,tail,False{},ws,A.add(acc,A.mul(w,E.E3{b,a,d,c,f,e})))
    case _ _ _ _: None{}

type Partial is Data:
  Partial{words: H.Bytes, draw: CS.Draw}

def updated(value: Maybe<&2,Packed>, part: Part, sum: CS.Draw) -> Maybe<&2,Partial>:
  match value:
    case Some{Packed{x,raw}}: Some{Partial{raw,add(sum,part,x)}}
    case _: None{}

def segments(xs: List<&2,Weighted>, acc: Maybe<&2,Partial>) -> Maybe<&2,CS.Draw>:
  match xs acc:
    case Nil{} Some{Partial{Nil{},sum}}: Some{sum}
    case Con{Weighted{part,b,n,ws},tail} Some{Partial{raw,sum}}:
      segments(tail,updated(consume(n,ws,b,raw,F.zero()),part,sum))
    case _ _: None{}

def collected(xs: O.Places, cols: O.Columns, +runs: List<&2,Weighted>, acc: Maybe<&2,CS.Draws>) -> Maybe<&2,CS.Draws>:
  match xs cols acc:
    case Nil{} Nil{} v: v
    case Con{+i,rest} Con{O.Column{j,+ws},tail} Some{ys}:
      result = segments(runs,Some{Partial{ws,CS.Draw{i,F.zero(),F.zero(),F.zero()}}})
      next = Bool.pick(Maybe<&2,CS.Draws>,Nat.is_eq(i,j) && O.canonical(ws),FV.prepend(result,ys),None{})
      collected(rest,tail,runs,next)
    case _ _ _: None{}

def make_table(values: Maybe<&2,CS.Draws>, depth: Nat, tail: List<&2,Table>, good: Bool) -> Maybe<&2,List<&2,Table>>:
  match values good:
    case Some{v} True{}: Some{Table{depth,v} <> tail}
    case _ _: None{}

def tables(xs: List<&2,Source>, +depth: Nat, +draws: O.Places, +main: B.Elements, +mask: B.Elements,
           acc: Maybe<&2,List<&2,Table>>) -> Maybe<&2,List<&2,Table>>:
  match xs acc:
    case Nil{} v: v
    case Con{Source{+b,segments,cols},tail} Some{sofar}:
      ys = collected(O.positions(b,draws),cols,plan(segments,main,mask),Some{[]})
      next = make_table(ys,b,sofar,Nat.is_le(b,depth))
      tables(tail,depth,draws,main,mask,next)
    case _ _: None{}

def join(a: Maybe<&2,CS.Draw>, b: Maybe<&2,CS.Draw>) -> Maybe<&2,CS.Draw>:
  match a b:
    case Some{CS.Draw{i,m,n,f}} Some{CS.Draw{_,x,y,z}}: Some{CS.Draw{i,A.add(m,x),A.add(n,y),A.add(f,z)}}
    case _ _: None{}

def symbol(+pos: Nat, ts: List<&2,Table>, acc: Maybe<&2,CS.Draw>) -> Maybe<&2,CS.Draw>:
  match ts:
    case []: acc
    case Table{b,ys} <> rest: symbol(pos,rest,join(acc,FV.find(Nat.mod(pos,CS.size(b)),ys)))

def draws(xs: O.Places, +ts: List<&2,Table>, acc: Maybe<&2,CS.Draws>) -> Maybe<&2,CS.Draws>:
  match xs acc:
    case Nil{} Some{ys}: Some{List.reverse(&2,CS.Draw,ys)}
    case Con{+i,rest} Some{ys}: draws(rest,ts,FV.prepend(symbol(i,ts,Some{CS.Draw{i,F.zero(),F.zero(),F.zero()}}),ys))
    case _ _: None{}

def assembled(ts: Maybe<&2,List<&2,Table>>, xs: O.Places, good: Bool) -> Maybe<&2,CS.Draws>:
  match ts good:
    case Some{Con{t,rest}} True{}: draws(xs,t <> rest,Some{[]})
    case _ _: None{}

def in_range(xs: O.Places, +limit: Nat) -> Bool:
  match xs:
    case []: True{}
    case x <> rest: Nat.is_lt(x,limit) && in_range(rest,limit)

def open(sources: List<&2,Source>, stage: S.Stage, +gamma: B.Elements, +xs: O.Places) -> Maybe<&2,CS.Draws>:
  S.Stage{B.Code{+a,_,_},_,k,h} = stage
  +depth = U32.to_nat(h)
  main = F.factor_table(CS.eqs(gamma),F.one())
  mask = F.factor_table(CS.eqs(List.take(&2,E.E3,gamma,depth)),F.one())
  good = Nat.is_eq(List.length(&2,E.E3,gamma),U32.to_nat(k)) && in_range(xs,CS.size(a))
  assembled(tables(sources,a,xs,main,mask,Some{[]}),xs,good)

# Four admitted key-file first switches. Declared before the fold were the index mask,
# W and finally adopted Omega. Ties in aligned block size keep that order.
type KeyGroup is Data:
  Ranges{main_rows: Nat, mask_rows: Nat}
  Folded{main_rows: Nat}
  Omega{main_rows: Nat}
  Second{w_rows: Nat, w_masks: Nat, omega_rows: Nat}

def ceil_power(+n: Nat) -> Nat:
  Bool.pick(Nat,Nat.is_le(n,1n),n,CS.size(1n+CS.bits(Nat.sub(n,1n))))

def before_at(before: Nat, after: Nat) -> Nat:
  a = ceil_power(before)
  +b = ceil_power(after)
  Bool.pick(Nat,Nat.is_lt(a,b),b,0n)

def after_at(before: Nat, after: Nat) -> Nat:
  +a = ceil_power(before)
  b = ceil_power(after)
  Bool.pick(Nat,Nat.is_lt(a,b),0n,a)

def main_run(i: Nat, n: Nat) -> Segment: Segment{Main{},False{},i,n}
def mask_run(i: Nat, n: Nat) -> Segment: Segment{Mask{},False{},i,n}
def fresh_run(n: Nat) -> Segment: Segment{Fresh{},False{},0n,n}

def sources(group: KeyGroup, +a: Nat, +b: Nat, fresh: Nat, cols: List<&2,O.Columns>) -> List<&2,Source>:
  match group cols:
    case Ranges{n,m} Con{tree,Nil{}}:
      [Source{a,[Segment{Main{},True{},0n,n},mask_run(0n,m),fresh_run(fresh)],tree}]
    case Folded{n} Con{tree,Con{split,Nil{}}}:
      [Source{a,[main_run(0n,n),fresh_run(fresh)],tree},Source{b,[mask_run(0n,1n)],split}]
    case Omega{n} Con{tree,Con{split,Con{star,Nil{}}}}:
      [Source{a,[main_run(0n,n)],tree},Source{b,[mask_run(0n,1n)],split},Source{b,[fresh_run(fresh)],star}]
    case Second{+w,+m,+n} Con{index,Con{own,Con{adopted,Nil{}}}}:
      [Source{b,[mask_run(before_at(1n,m),1n)],index},Source{a,[main_run(before_at(w,n),w),mask_run(after_at(1n,m),m),fresh_run(fresh)],own},
       Source{a,[main_run(after_at(w,n),n)],adopted}]
    case _ _: []

def key(group: KeyGroup, +stage: S.Stage, gamma: B.Elements, xs: O.Places, cols: List<&2,O.Columns>) -> Maybe<&2,CS.Draws>:
  S.Stage{B.Code{a,_,_},B.Code{b,_,_},_,h} = stage
  open(sources(group,a,b,CS.size(U32.to_nat(h)),cols),stage,gamma,xs)

def ranges(n: Nat, m: Nat, stage: S.Stage, gs: B.Elements, xs: O.Places, cols: O.Columns, extra: O.Columns) -> Maybe<&2,CS.Draws>:
  match extra:
    case Nil{}: key(Ranges{n,m},stage,gs,xs,[cols])
    case _: None{}
