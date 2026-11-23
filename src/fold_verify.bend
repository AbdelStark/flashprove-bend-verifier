import Base
import ./fold.bend as F
import ./fold_cs.bend as CS
import ./base_check.bend as B
import ./leaf_walk.bend as W
import ./leaf_shape.bend as S
import ./opening_bytes.bend as OB
import ./extension.bend as Ext
import ./transcript.bend as T
import ./hash_bytes.bend as H

def Events() -> Data: List<&2,W.EntryRound>
def pick(xs: B.Elements) -> Ext.E3: Maybe.default(&2,Ext.E3,List.head(&2,Ext.E3,xs),F.zero())
def first(s: T.Stream) -> Ext.E3: T.value(Ext.E3,T.element(s))

def only(xs: Maybe<&2,B.Elements>) -> Maybe<&2,Ext.E3>:
  match xs:
    case Some{Con{x,Nil{}}}: Some{x}
    case _: None{}

def value(msg: H.Bytes) -> Maybe<&2,Ext.E3>: only(B.read_elements(1n,msg,[],True{}))

def single(xs: B.Elements, gs: B.Elements) -> Ext.E3: pick(F.fold_low(gs,xs))

def vector(+xs: B.Elements, n: Nat) -> B.Elements:
  List.append(&2,Ext.E3,xs,CS.zeros(Nat.sub(n,List.length(&2,Ext.E3,xs))))

# LINK's first switch opens two aligned blocks of real rows with zero padding, then a fresh mask.
# Later switches open a complete main table, an old mask table and the fresh mask table.
def combine(+pos: Nat, +gs: B.Elements, +h: Nat, real: Nat, +xs: B.Elements) -> CS.Draw:
  match real:
    case 0n:
      +main_n = CS.size(List.length(&2,Ext.E3,gs))
      +mask_n = CS.size(h)
      +low = List.take(&2,Ext.E3,gs,h)
      +masks = List.drop(&2,Ext.E3,xs,main_n)
      main = single(List.take(&2,Ext.E3,xs,main_n),gs)
      mask = single(List.take(&2,Ext.E3,masks,mask_n),low)
      CS.Draw{pos,main,mask,single(List.drop(&2,Ext.E3,masks,mask_n),low)}
    case 1n+n:
      +count: Nat = 1n+n
      +block = Nat.div(CS.size(List.length(&2,Ext.E3,gs)),2n)
      +further = List.drop(&2,Ext.E3,xs,count)
      a = vector(List.take(&2,Ext.E3,xs,count),block)
      b = vector(List.take(&2,Ext.E3,further,count),block)
      main = single(List.append(&2,Ext.E3,a,b),gs)
      CS.Draw{pos,main,F.zero(),single(List.drop(&2,Ext.E3,further,count),List.take(&2,Ext.E3,gs,h))}

def columns(places: OB.Places, cs: OB.Columns, +gamma: B.Elements, +h: Nat, +real: Nat, +limbs: Nat, acc: CS.Draws, good: Bool) -> Maybe<&2,CS.Draws>:
  match places cs good:
    case Nil{} Nil{} True{}: Some{acc}
    case Con{+i,tail} Con{OB.Column{j,+ws},rest} True{}:
      ok = Nat.is_eq(i,j) && Nat.is_eq(List.length(&2,U32,ws),limbs) && OB.canonical(ws)
      d = combine(i,gamma,h,real,B.elements(ws,[]))
      columns(tail,rest,gamma,h,real,limbs,d <> acc,ok)
    case _ _ _: None{}

def find(+pos: Nat, xs: CS.Draws) -> Maybe<&2,CS.Draw>:
  match xs:
    case []: None{}
    case CS.Draw{+i,m,n,f} <> tail:
      Maybe.or(&2,CS.Draw,Bool.pick(Maybe<&2,CS.Draw>,Nat.is_eq(pos,i),Some{CS.Draw{i,m,n,f}},None{}),find(pos,tail))

def prepend(d: Maybe<&2,CS.Draw>, acc: CS.Draws) -> Maybe<&2,CS.Draws>:
  match d:
    case None{}: None{}
    case Some{x}: Some{x <> acc}

def restore(xs: OB.Places, +table: CS.Draws, acc: Maybe<&2,CS.Draws>) -> Maybe<&2,CS.Draws>:
  match xs acc:
    case Nil{} Some{rev}: Some{List.reverse(&2,CS.Draw,rev)}
    case Con{x,tail} Some{rev}: restore(tail,table,prepend(find(x,table),rev))
    case _ _: None{}

def ordered(draws: OB.Places, xs: Maybe<&2,CS.Draws>) -> Maybe<&2,CS.Draws>:
  match xs:
    case None{}: None{}
    case Some{table}: restore(draws,table,Some{[]})

def opened(+old: S.Stage, +gamma: B.Elements, +real: Nat, +draws: OB.Places, cs: OB.Columns) -> Maybe<&2,CS.Draws>:
  S.Stage{B.Code{+a,_,_},_,k,h} = old
  +m = CS.size(U32.to_nat(k))
  +n = CS.size(U32.to_nat(h))
  units = Bool.pick(Nat,Nat.is_eq(real,0n),Nat.add(m,Nat.mul(2n,n)),Nat.add(Nat.mul(2n,real),n))
  +places = OB.positions(a,draws)
  good = OB.valid_places(places,a) && List.all(&2,Nat,x => Nat.is_le(x,4294967295n),draws)
  xs = columns(places,cs,gamma,U32.to_nat(h),real,Nat.mul(6n,units),[],good)
  ordered(draws,xs)

# A caller supplies the first folded-opening layout; subsequent oracle switches share the regular layout.
def Open() -> Type:
  S.Stage -> B.Elements -> OB.Places -> OB.Columns -> OB.Columns -> Maybe<&2,CS.Draws>

def leaf_open(real: Nat, old: S.Stage, gs: B.Elements, draws: OB.Places, cols: OB.Columns, further: OB.Columns) -> Maybe<&2,CS.Draws>:
  match further:
    case Nil{}: opened(old,gs,real,draws,cols)
    case _: None{}

type Progress is Data:
  Progress{claim: F.Claim, events: Events}
  Failed{}

def switched(row: Maybe<&2,F.Claim>, events: Events) -> Progress:
  match row:
    case None{}: Failed{}
    case Some{c}: Progress{c,events}

def invoke(old: S.Stage, next: S.Stage, rows: F.Single, theta: Ext.E3, ds: Maybe<&2,CS.Draws>, seed: CS.Seed, answer: Maybe<&2,Ext.E3>, rest: Events) -> Progress:
  match ds answer:
    case Some{draws} Some{y}: switched(CS.switch(old,next,rows,theta,draws,seed,y),rest)
    case _ _: Failed{}

def after_rounds(+old: S.Stage, +next: S.Stage, c: F.Claim, +gamma: B.Elements, eps: Ext.E3, target: Ext.E3, open_cs: Open, events: Events) -> Progress:
  S.Stage{B.Code{+depth,_,_},B.Code{_,mask,_},_,h} = old
  S.Stage{B.Code{_,m,_},B.Code{_,n,_},a,b} = next
  match events:
    case W.EntryRound{a_name,_,stream,_,_,_} <> W.EntryRound{b_name,body,positions,+xs,cols,extra} <> tail:
      bits = Nat.max(Nat.add(U32.to_nat(a),CS.bits(m)),Nat.add(U32.to_nat(b),CS.bits(n)))
      seed = CS.seed(1n+bits,[],stream)
      after = T.after(OB.Places,T.draws(List.length(&2,Nat,xs),depth,positions))
      rows = F.finish(c,gamma,U32.to_nat(h),mask,eps,target)
      Bool.pick(Progress,String.eq(a_name,"SEND seed") && String.eq(b_name,"CS"),invoke(old,next,rows,first(after),open_cs(old,gamma,xs,cols,extra),seed,value(body),tail),Failed{})
    case _: Failed{}

def rounds(n: Nat, +old: S.Stage, +next: S.Stage, +c: F.Claim, +eps: Ext.E3, target: Ext.E3, gs: B.Elements, open_cs: Open, events: Events) -> Progress:
  match n events:
    case 0n rest: after_rounds(old,next,c,List.reverse(&2,Ext.E3,gs),eps,target,open_cs,rest)
    case 1n+p Con{W.EntryRound{name,+msg,stream,_,_,_},tail}:
      +g = first(stream)
      +coeff = B.elements(H.u32s(msg),[])
      next_target = F.round(target,pick(coeff),pick(List.drop(&2,Ext.E3,coeff,1n)),g)
      checked = String.eq(name,"FOLD round") && Nat.is_eq(List.length(&2,U32,msg),48n) && OB.canonical(H.u32s(msg))
      Bool.pick(Progress,checked,rounds(p,old,next,c,eps,next_target,g <> gs,open_cs,tail),Failed{})
    case _ _: Failed{}

def begun(old: S.Stage, next: S.Stage, c: F.Claim, +eps: Ext.E3, star: Maybe<&2,Ext.E3>, +target: Ext.E3, k: Nat, open_cs: Open, events: Events, valid: Bool) -> Progress:
  match star valid:
    case Some{s} True{}: rounds(k,old,next,c,eps,B.masked(s,eps,target),[],open_cs,events)
    case _ _: Failed{}

def advance(+old: S.Stage, next: S.Stage, c: F.Claim, open_cs: Open, events: Events) -> Progress:
  S.Stage{B.Code{_,m,_},B.Code{_,+n,_},+k,+h} = old
  F.Claim{+form,+ms,+target} = c
  match events:
    case W.EntryRound{name,msg,stream,_,_,_} <> tail:
      +bits = U32.to_nat(k)
      +mbits = U32.to_nat(h)
      ok = String.eq(name,"FOLD epsilon") && Nat.is_le(1n,bits) && Nat.is_le(mbits,bits) && Nat.is_le(Nat.sub(1n+Nat.mul(2n,bits),mbits),n) &&
        F.fits(form,Nat.add(bits,CS.bits(m))) && Nat.is_eq(F.count(Ext.E3,ms,0n),Nat.mul(n,CS.size(mbits)))
      begun(old,next,F.Claim{form,ms,target},first(stream),value(msg),target,bits,open_cs,tail,ok)
    case _: Failed{}

def linear_target(parsed: Maybe<&2,B.Rows>, cs: B.Elements, ds: B.Elements, +lam: Ext.E3, star: Ext.E3, target: Ext.E3, xs: OB.Places, cols: OB.Columns, valid: Bool) -> Bool:
  match parsed valid:
    case Some{+rows} True{}: B.linear(rows,lam,star,target,cs,ds) && B.symbols(rows,lam,xs,cols)
    case _ _: False{}

def base(row: F.Claim, main: B.Code, +n: Nat, mask: B.Code, lam: Ext.E3, star: Maybe<&2,Ext.E3>, raw: H.Bytes, xs: OB.Places, cols: OB.Columns) -> Bool:
  F.Claim{+form,ws,target} = row
  match star:
    case Some{v}:
      linear_target(B.read(main,mask,raw),F.expand(form,CS.zeros(n)),ws,lam,v,target,xs,cols,F.fits(form,CS.bits(n)))
    case _: False{}

def last(stage: S.Stage, claim: F.Claim, events: Events) -> Bool:
  S.Stage{B.Code{+a,+n,r},mask,k,h} = stage
  match events:
    case [W.EntryRound{a_name,star,stream,_,_,_},W.EntryRound{b_name,msg,_,xs,cols,_}]:
      String.eq(a_name,"BASE lambda") && String.eq(b_name,"BASE") && U32.is_zero(U32.or(k,h)) && base(claim,B.Code{a,n,r},n,mask,first(stream),value(star),msg,OB.positions(a,xs),cols)
    case _: False{}

def stages(xs: List<&2,S.Stage>, prog: Progress, open_cs: Open) -> Bool:
  match xs prog:
    case Con{s,Nil{}} Progress{c,events}: last(s,c,events)
    case Con{s,Con{+next,tail}} Progress{c,events}: stages(next <> tail,advance(s,next,c,open_cs,events),leaf_open(0n))
    case _ _: False{}

def custom(claim: F.Claim, ss: List<&2,S.Stage>, events: Events, open_cs: Open) -> Bool:
  stages(ss,Progress{claim,events},open_cs)

def verify(claim: F.Claim, shape: S.Shape, after_bat: Events) -> Bool:
  S.Shape{_,_,_,_,_,_,_,_,rows,ss} = shape
  custom(claim,ss,after_bat,leaf_open(U32.to_nat(rows)))
