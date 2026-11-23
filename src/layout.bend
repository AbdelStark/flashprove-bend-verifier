import Base
import ./hash_bytes.bend as H
import ./header.bend as Header
import ./policy.bend as P
import ./policy_frame.bend as Frame
import ./plan.bend as Plan
import ./wire_reader.bend as Reader

# Plain decimal layout encoding (§13.4). Coordinates may occupy 48 bits.
# A rectangle stores half-open bounds. Nat keeps area and coordinate sums exact.
type Rect is Data:
  Rect{x: Nat, y: Nat, end_x: Nat, end_y: Nat}

type Group is Data:
  Group{link: U32, moment: U32, group: U32, degree: U32, rows: Nat, life: U32}

type Block is Data:
  Block{link: U32, moment: U32, group: U32, name: String, life: U32, source: Rect, target: Rect, bytes: H.Bytes}

type Lines is Data:
  Lines{groups: List<&2,Group>, blocks: List<&2,Block>}

def nat_limit() -> Nat:
  Nat.add(Nat.pow(2n,47n),Nat.sub(Nat.pow(2n,47n),1n))

def nat_value(value: Maybe<&2,Nat>) -> IO(Nat):
  match value:
    case Some{+n}:
      do IO<Nat>:
        ok : Unit <- Header.require(Nat.is_le(n,nat_limit()), "NO: plan-layout")
        return n
    case None{}: IO.die(Nat,1,"NO: plan-layout")

def coord(+s: String) -> IO(Nat):
  do IO<Nat>:
    ok : Unit <- Header.require(Bool.not(String.is_empty(s)) && Nat.is_le(String.length(s),15n) &&
      (Bool.not(String.starts_with(s,"0")) || String.eq(s,"0")) &&
      List.all(&2,Char,Char.is_digit,String.to_list(s)), "NO: plan-layout")
    ok : Unit <- Header.require(Nat.is_lt(String.length(s),15n) || String.is_le(s,"281474976710655"), "NO: plan-layout")
    nat_value(Nat.read(s))

def number(s: String, low: Nat, high: Nat) -> IO(U32):
  do IO<U32>:
    +n : Nat <- coord(s)
    ok : Unit <- Header.require(Nat.is_ge(n,low) && Nat.is_le(n,high), "NO: plan-layout")
    return U32.from_nat(n)

def le64(+n: Nat) -> H.Bytes:
  H.cat([H.le(U32.from_nat(n)),H.le(U32.from_nat(Nat.div(n,Nat.pow(2n,32n))))])

# The segment's first moment lists private matrices first, then matrices
# another segment reads. G0's private xbI therefore precedes qa and xbO.
type Model is Data:
  Model{links: U32, qa: U32, attention: U32, head: U32}

def own_count(model: Model, +link: U32) -> U32:
  Model{links,qa,attn,head} = model
  ff = U32.add(qa,Bool.pick(U32,U32.is_eq(link,1),3,2))
  Bool.pick(U32,U32.is_eq(link,links),head,Bool.pick(U32,U32.is_zero(U32.and(link,1)),attn,ff))

def matrix(model: Model, +link: U32, +a: U32) -> IO(String & U32):
  Model{+links,+qa,attn,head} = model
  +ff = U32.is_ne(link,links) && U32.is_ne(U32.and(link,1),0)
  +move = U32.is_eq(link,1) && U32.is_ge(a,qa)
  +mu = Bool.pick(U32,move,Bool.pick(U32,U32.is_eq(a,qa),U32.add(qa,2),U32.sub(a,1)),a)
  life = Bool.pick(U32,ff,Bool.pick(U32,U32.is_eq(mu,qa),1,Bool.pick(U32,U32.is_eq(mu,U32.add(qa,1)),2,0)),0)
  do IO<String & U32>:
    ok : Unit <- Header.require(U32.is_lt(a,own_count(Model{links,qa,attn,head},link)), "NO: plan-layout")
    return ("M" ++ U32.show(mu),life)

def array_name(model: Model, link: U32, moment: U32, +a: U32) -> IO(String & U32):
  match moment:
    case 1: matrix(model,link,a)
    case 2:
      do IO<String & U32>:
        ok : Unit <- Header.require(U32.is_zero(a), "NO: plan-layout")
        return ("U3",0)
    case 3:
      do IO<String & U32>:
        ok : Unit <- Header.require(U32.is_le(a,1), "NO: plan-layout")
        return (Bool.pick(String,U32.is_zero(a),"ZZ","BZ"),0)
    case _: IO.die(String & U32,1,"NO: plan-layout")

def new_block(link: U32, moment: U32, group: U32, named: String & U32, source: Rect, target: Rect, bytes: H.Bytes) -> Block:
  (name,life) = named
  Block{link,moment,group,name,life,source,target,bytes}

def rectangle(+x: Nat, +y: Nat, a: U32, b: U32) -> IO(Rect):
  +dx = Nat.pow(2n,U32.to_nat(a))
  +dy = Nat.pow(2n,U32.to_nat(b))
  do IO<Rect>:
    ok : Unit <- Header.require(Nat.is_eq(Nat.mod(x,dx),0n) && Nat.is_eq(Nat.mod(y,dy),0n), "NO: layout-alignment")
    ok : Unit <- Header.require(Nat.is_le(x,Nat.sub(nat_limit(),dx)) && Nat.is_le(y,Nat.sub(nat_limit(),dy)), "NO: layout-placement")
    return Rect{x,y,Nat.add(x,dx),Nat.add(y,dy)}

def parse_line(xs: P.Lines, acc: Lines, model: Model) -> IO(Lines):
  match xs acc:
    case [ls,ms,gsn,+cls,rs,life] Lines{gs,bs}:
      do IO<Lines>:
        +link : U32 <- number(ls,1n,1048575n)
        moment : U32 <- number(ms,1n,3n)
        group : U32 <- number(gsn,1n,1048575n)
        rows : U32 <- number(rs,1n,4294967295n)
        +keep : U32 <- number(life,0n,1048575n)
        ok : Unit <- Header.require((String.eq(cls,"N") || String.eq(cls,"W") || String.eq(cls,"B")) &&
          Bool.not(Bool.xor(String.eq(cls,"B"),U32.is_ne(keep,0))), "NO: plan-layout")
        return Lines{Group{link,moment,group,Bool.pick(U32,String.eq(cls,"W"),3,1),U32.to_nat(rows),keep} <> gs,bs}
    case [ls,ms,gsn,ars,rs,ais,cs,ecs,+direction,rows,ps,rbs,pbs,last] Lines{gs,bs}:
      do IO<Lines>:
        ok : Unit <- Header.require((String.eq(direction,"r") || String.eq(direction,"c")) && String.eq(last,"0"), "NO: plan-layout")
        +link : U32 <- number(ls,1n,1048575n)
        +moment : U32 <- number(ms,1n,3n)
        group : U32 <- number(gsn,1n,1048575n)
        arr : U32 <- number(ars,0n,1048575n)
        named : String & U32 <- array_name(model,link,moment,arr)
        +r : Nat <- coord(rs)
        +c : Nat <- coord(cs)
        +row : Nat <- coord(rows)
        +place : Nat <- coord(ps)
        +a : U32 <- number(ais,0n,47n)
        +e : U32 <- number(ecs,0n,47n)
        +br : U32 <- number(rbs,0n,47n)
        +bj : U32 <- number(pbs,0n,47n)
        ok : Unit <- Header.require(U32.is_eq(U32.add(a,e),U32.add(br,bj)), "NO: layout-block-size")
        from : Rect <- rectangle(r,c,a,e)
        to : Rect <- rectangle(row,place,br,bj)
        bytes : H.Bytes = H.cat([le64(r),le64(c),le64(row),le64(place),H.word(a),H.word(e),
          H.word(br),H.word(bj),H.word(Bool.pick(U32,String.eq(direction,"r"),1,0))])
        return Lines{gs,new_block(link,moment,group,named,from,to,bytes) <> bs}
    case _ _: IO.die(Lines,1,"NO: plan-layout")

def parse_lines(xs: P.Lines, acc: Lines, +model: Model) -> IO(Lines):
  match xs:
    case []:
      Lines{gs,bs} = acc
      IO.pure(Lines,Lines{List.reverse(&2,Group,gs),List.reverse(&2,Block,bs)})
    case +line <> tail:
      +skip = String.is_empty(line) || String.starts_with(line,"#")
      action = Bool.pick(Lines -> IO(Lines),skip,x => IO.pure(Lines,x),x => parse_line(String.split(line,' '),x,model))
      do IO<Lines>:
        next : Lines <- action(acc)
        parse_lines(tail,next,model)

def overlaps(left: Rect, right: Rect) -> Bool:
  Rect{x,y,ex,ey} = left
  Rect{u,v,eu,ev} = right
  Nat.is_lt(x,eu) && Nat.is_lt(u,ex) && Nat.is_lt(y,ev) && Nat.is_lt(v,ey)

def free(prev: List<&2,Rect>, +rect: Rect) -> Bool:
  match prev:
    case []: True{}
    case h <> tail: Bool.not(overlaps(h,rect)) && free(tail,rect)

type Placed is Data:
  Placed{message: U32, rows: Nat, columns: Nat, area: Nat, source: List<&2,Rect>, bytes: List<&2,H.Bytes>}

type Segment is Data:
  Segment{names: P.Lines, arrays: Map<&2,Maybe<&2,Placed>>, occupied: Map<&2,List<&2,Rect>>}

def inside(group: Group, +message: U32, +width: Nat, rect: Rect, moment: U32, required_life: U32) -> Bool:
  Group{_,_,_,+degree,+rows,life} = group
  Rect{_,_,+end_r,+end_c} = rect
  +pad = Bool.pick(Nat,U32.is_eq(degree,3),1n,3n)
  Bool.not(Bool.xor(U32.is_eq(degree,3),U32.is_eq(moment,2))) && Nat.is_le(end_r,rows) &&
    U32.is_ge(life,required_life) && Nat.is_le(end_c,width) && (U32.is_zero(message) || Nat.is_lt(end_r,rows) || Nat.is_le(end_c,Nat.sub(width,pad)))

def select_group(gs: List<&2,Group>, +moment: U32, +group: U32, +n: U32) -> IO(Group & U32):
  match gs:
    case []: IO.die(Group & U32,1,"NO: plan-layout")
    case +h <> tail:
      Group{_,m,g,_,_,_} = h
      act = Bool.pick(Unit -> IO(Group & U32),U32.is_eq(moment,m) && U32.is_eq(group,g),
        _ => IO.pure(Group & U32,(h,n)),_ => select_group(tail,moment,group,U32.add(n,1)))
      act(Unit{})

def placed(previous: Maybe<&2,Placed>, +message: U32) -> Placed:
  match previous:
    case None{}: Placed{message,0n,0n,0n,[],[]}
    case Some{p}: p

def is_new(x: Maybe<&2,Placed>) -> Bool:
  match x:
    case None{}: True{}
    case Some{_}: False{}

def record(from: Rect, +to: Rect, location: Group & U32, moment: U32, life: U32, raw: H.Bytes,
    value: Placed, pair: Map<&2,List<&2,Rect>> & List<&2,Rect>, key: String,
    names: P.Lines, arrays: Map<&2,Maybe<&2,Placed>>, name: String, width: Nat) -> IO(Segment):
  Rect{+r,+c,+er,+ec} = from
  (g,+message) = location
  Placed{m,rows,cols,+area,+rs,bs} = value
  (occupied,+taken) = pair
  +source : Rect = Rect{r,c,er,ec}
  do IO<Segment>:
    ok : Unit <- Header.require(U32.is_eq(m,message) && inside(g,message,width,to,moment,life), "NO: layout-placement")
    ok : Unit <- Header.require(free(rs,source) && free(taken,to), "NO: layout-overlap")
    ok : Unit <- Header.require(Nat.is_le(Nat.sub(er,r),Nat.div(Nat.sub(nat_limit(),area),Nat.sub(ec,c))), "NO: unsupported-layout-area")
    next : Placed = Placed{message,Nat.max(rows,er),Nat.max(cols,ec),Nat.add(area,Nat.mul(Nat.sub(er,r),Nat.sub(ec,c))),source <> rs,raw <> bs}
    return Segment{names,Map.set(&2,Maybe<&2,Placed>,arrays,name,Some{next}),Map.set(&2,List<&2,Rect>,occupied,key,to <> taken)}

def add_known(b: Block, loc: Group & U32, +names: P.Lines, occupied: Map<&2,List<&2,Rect>>,
    existing: Map<&2,Maybe<&2,Placed>> & Maybe<&2,Placed>, width: Nat) -> IO(Segment):
  Block{_,moment,_,+name,life,from,to,raw} = b
  (g,+message) = loc
  (arrays,+found) = existing
  +key = U32.show(message)
  record(from,to,(g,message),moment,life,raw,placed(found,message),Map.get(List<&2,Rect>,[],occupied,key),key,
    Bool.pick(P.Lines,is_new(found),name <> names,names),arrays,name,width)

def add(+b: Block, loc: Group & U32, seg: Segment, width: Nat) -> IO(Segment):
  Block{_,_,_,name,_,_,_,_} = b
  Segment{names,arrays,occupied} = seg
  add_known(b,loc,names,occupied,Map.get(Maybe<&2,Placed>,None{},arrays,name),width)

def place_blocks(bs: List<&2,Block>, +gs: List<&2,Group>, +width: Nat, seg: Segment) -> IO(Segment):
  match bs:
    case []: IO.pure(Segment,seg)
    case +b <> tail:
      Block{_,m,g,_,_,_,_,_} = b
      do IO<Segment>:
        location : Group & U32 <- select_group(gs,m,g,0)
        next : Segment <- add(b,location,seg,width)
        place_blocks(tail,gs,width,next)

def chars(text: String) -> H.Bytes:
  match text:
    case SNil{}: []
    case SCon{c,tail}: Char.to_u32(c) <> chars(tail)

def array_bytes(+name: String, value: Maybe<&2,Placed>) -> IO(H.Bytes):
  match value:
    case None{}: IO.die(H.Bytes,1,"NO: plan-layout")
    case Some{Placed{m,+r,+c,area,_,+bs}}:
      do IO<H.Bytes>:
        ok : Unit <- Header.require(Nat.is_le(r,Nat.div(nat_limit(),c)) &&
          Nat.is_eq(area,Nat.mul(r,c)), "NO: layout-array-cover")
        return H.cat([le64(String.length(name)),chars(name),H.word(m),le64(r),le64(c),
          le64(List.length(&2,H.Bytes,bs)),H.cat(List.reverse(&2,H.Bytes,bs))])

def found_array(existing: Map<&2,Maybe<&2,Placed>> & Maybe<&2,Placed>, name: String) -> IO(H.Bytes):
  (_,v) = existing
  array_bytes(name,v)

def encode_arrays(names: P.Lines, +arrays: Map<&2,Maybe<&2,Placed>>, acc: List<&2,H.Bytes>) -> IO(H.Bytes):
  match names:
    case []: IO.pure(H.Bytes,H.cat(acc))
    case +name <> tail:
      do IO<H.Bytes>:
        bs : H.Bytes <- found_array(Map.get(Maybe<&2,Placed>,None{},arrays,name),name)
        encode_arrays(tail,arrays,bs <> acc)

def encode(seg: Segment, own: U32) -> IO(H.Bytes):
  Segment{+names,arrays,_} = seg
  do IO<H.Bytes>:
    ok : Unit <- Header.require(Nat.is_eq(List.length(&2,String,names),Nat.add(3n,U32.to_nat(own))), "NO: layout-missing-array")
    data : H.Bytes <- encode_arrays(names,arrays,[])
    return H.cat([le64(List.length(&2,String,names)),data])

def group_shape(gs: List<&2,Group>, +last_m: U32, last_g: U32, +index: U32) -> IO(H.Bytes):
  match gs:
    case []: IO.pure(H.Bytes,[])
    case Group{_,+m,+g,deg,rows,+life} <> tail:
      +first = U32.is_zero(index)
      do IO<H.Bytes>:
        ok : Unit <- Header.require((U32.is_eq(m,last_m) && U32.is_eq(g,U32.add(last_g,1)) ||
          U32.is_eq(m,U32.add(last_m,1)) && U32.is_eq(g,1)) && (Bool.not(first) || U32.is_zero(life)), "NO: layout-group-order")
        rest : H.Bytes <- group_shape(tail,m,g,U32.add(index,1))
        return H.cat([le64(rows),H.word(deg),H.word(Bool.pick(U32,first,1,0)),H.word(0),H.word(U32.sub(m,1)),H.word(life),rest])

type Encoded is Data:
  Encoded{layout: H.Bytes, shape: H.Bytes}

def at_group(g: Group) -> U32:
  Group{link,_,_,_,_,_} = g
  link

def at_block(b: Block) -> U32:
  Block{link,_,_,_,_,_,_,_} = b
  link

def group_for(xs: List<&2,Group>, +link: U32) -> List<&2,Group>:
  match xs:
    case []: []
    case +x <> tail:
      +rest = group_for(tail,link)
      Bool.pick(List<&2,Group>,U32.is_eq(at_group(x),link),x <> rest,rest)

def blocks_for(xs: List<&2,Block>, +link: U32) -> List<&2,Block>:
  match xs:
    case []: []
    case +x <> tail:
      +rest = blocks_for(tail,link)
      Bool.pick(List<&2,Block>,U32.is_eq(at_block(x),link),x <> rest,rest)

def block_links(xs: List<&2,Block>, +limit: U32) -> Bool:
  match xs:
    case []: True{}
    case b <> tail: U32.is_le(at_block(b),limit) && block_links(tail,limit)

def append_segment(result: Encoded, layout: H.Bytes, shape: H.Bytes) -> Encoded:
  Encoded{ls,ss} = result
  Encoded{H.cat([layout,ls]),H.cat([shape,ss])}

def segments(count: Nat, +link: U32, +gs: List<&2,Group>, +bs: List<&2,Block>, +width: Nat, +model: Model) -> IO(Encoded):
  match count:
    case 0n: IO.pure(Encoded,Encoded{[],[]})
    case 1n+ +p:
      +own = group_for(gs,link)
      blocks = blocks_for(bs,link)
      do IO<Encoded>:
        ok : Unit <- Header.require(Bool.not(List.is_empty(&2,Group,own)), "NO: plan-layout")
        message_shape : H.Bytes <- group_shape(own,0,0,0)
        seg : Segment <- place_blocks(blocks,own,width,Segment{[],Map.new(&2,Maybe<&2,Placed>),Map.new(&2,List<&2,Rect>)})
        data : H.Bytes <- encode(seg,own_count(model,link))
        tail : Encoded <- segments(p,U32.add(link,1),gs,bs,width,model)
        return append_segment(tail,data,H.cat([H.word(Bool.pick(U32,Nat.is_eq(p,0n),1,0)),le64(List.length(&2,Group,own)),message_shape]))

def ordered(gs: List<&2,Group>, +previous: U32, +limit: U32) -> Bool:
  match gs:
    case []: U32.is_eq(previous,limit)
    case g <> tail:
      +link = at_group(g)
      (U32.is_eq(link,previous) || U32.is_eq(link,U32.add(previous,1))) &&
        U32.is_le(link,limit) && ordered(tail,link,limit)

def item(items: List<&2,Plan.Item>, +name: String) -> IO(H.Bytes):
  match items:
    case []: IO.die(H.Bytes,1,"NO: plan-item")
    case Plan.Item{key,raw} <> tail:
      f = Bool.pick(Unit -> IO(H.Bytes),String.eq(key,name),_ => IO.pure(H.Bytes,raw),_ => item(tail,name))
      f(Unit{})

def match_plan(built: Encoded, +count: U32, layout: H.Bytes, shape: H.Bytes) -> IO(Unit):
  Encoded{ls,ss} = built
  +prefix = H.cat([H.word(count), ss])
  do IO<Unit>:
    ok : Unit <- Header.require(Reader.equal(H.cat([H.word(count),ls]),layout), "NO: layout-plan-mismatch")
    Header.require(Reader.equal(List.take(&2,U32,List.drop(&2,U32,shape,16n),List.length(&2,U32,prefix)),prefix), "NO: layout-shape-mismatch")

def checked(lines: Lines, +model: Model, width: Nat, +items: List<&2,Plan.Item>) -> IO(Unit):
  Lines{+gs,+bs} = lines
  Model{+count,_,_,_} = model
  do IO<Unit>:
    ok : Unit <- Header.require(ordered(gs,0,count) && block_links(bs,count), "NO: layout-group-order")
    built : Encoded <- segments(U32.to_nat(count),1,gs,bs,width,model)
    layout : H.Bytes <- item(items,"layout")
    shape : H.Bytes <- item(items,"request's shape")
    match_plan(built,count,layout,shape)

def check(raw: H.Bytes, +model: Model, width: Nat, +items: List<&2,Plan.Item>) -> IO(Unit):
  do IO<Unit>:
    lines : Lines <- parse_lines(String.lines(P.ascii(raw)),Lines{[],[]},model)
    checked(lines,model,width,items)
