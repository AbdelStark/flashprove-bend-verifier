import Base
import ./fold_frame.bend as F
import ./fold_open.bend as O
import ./fold_cs.bend as C
import ./leaf_shape.bend as S
import ./base_check.bend as B
import ./hash_bytes.bend as H
import ./wire_reader.bend as R
import ./header.bend as Header
import ./key_stage_codes.bend as Codes
import ./key_stage_openings.bend as K
import ./plan.bend as P

type Notice is Data:
  Notice{member: F.Member, moment: Nat, life: Nat}
def Notices() -> Data: List<&2,Notice>
type Link is Data:
  Link{plain: Nat, own: Notices}
type Shape is Data:
  Shape{main: B.Code, mask: B.Code, links: List<&2,Link>, stages: List<&2,S.Stage>}
type Read<-A: Data> is Data:
  Read{value: A, rest: H.Bytes}

def bad(-A: Data) -> IO(A): IO.die(A,1,"NO: request-group-geometry")

# Stable member labels within a request. Zero is reserved for the new carrier at every switch.
# Actual oracle numbers change at each remint; a surviving member keeps its private group label.
def label(link: Nat, +index: Nat) -> Nat:
  +diagonal = Nat.add(link,index)
  1n+Nat.add(index,Nat.div(Nat.mul(diagonal,1n+diagonal),2n))

def notices(n: Nat, xs: H.Bytes, +link: Nat, +at: Nat, acc: Notices) -> IO(Read<Notices>):
  match n xs:
    case 0n rest: IO.pure(Read<Notices>,Read{List.reverse(&2,Notice,acc),rest})
    case 1n+k Con{+m,Con{+d,Con{+w,Con{0,Con{+t,Con{+f,tail}}}}}}:
      +id = label(link,at)
      +hold = U32.is_lt(0,f)
      member: F.Member = F.Member{id,U32.to_nat(m),U32.to_nat(d),U32.to_nat(w),hold}
      item: Notice = Notice{member,U32.to_nat(t),U32.to_nat(f)}
      do IO<Read<Notices>>:
        valid : Unit <- Header.require(U32.is_lt(0,m) && (U32.is_eq(d,1) || U32.is_eq(d,3)) &&
          (Bool.not(hold) || U32.is_zero(w)) && U32.is_le(t,2),"NO: request-member-shape")
        notices(k,tail,link,1n+at,item <> acc)
    case _ _: bad(Read<Notices>)

def link_step(row: Read<Notices>, plain: Nat, before: List<&2,Link>) -> Read<List<&2,Link>>:
  Read{own,after} = row
  Read{Link{plain,own} <> before,after}

def links(n: Nat, cursor: Read<List<&2,Link>>, +i: Nat) -> IO(Read<List<&2,Link>>):
  match n cursor:
    case 0n Read{acc,tail}: IO.pure(Read<List<&2,Link>>,Read{List.reverse(&2,Link,acc),tail})
    case 1n+k Read{acc,Con{p,Con{m,tail}}}:
      do IO<Read<List<&2,Link>>>:
        read : Read<Notices> <- notices(U32.to_nat(m),tail,i,0n,[])
        links(k,link_step(read,U32.to_nat(p),acc),1n+i)
    case _ _: bad(Read<List<&2,Link>>)

def end(codes: S.Codes, main: B.Code, mask: B.Code, data: Read<List<&2,Link>>) -> IO(Shape):
  match data:
    case Read{ls,1 <> 4294967295 <> _ <> 0 <> 1 <> 1 <> 1 <> 1 <> 1 <> n <> tail}:
      do IO<Shape>:
        later : List<&2,S.Stage> <- S.later(U32.to_nat(n),tail,codes)
        return Shape{main,mask,ls,later}
    case _: bad(Shape)

def read(+codes: S.Codes, words: H.Bytes) -> IO(Shape):
  S.Codes{m,w} = codes
  match words:
    case a <> b <> n <> xs:
      do IO<Shape>:
        main : B.Code <- K.need(B.Code,List.get(&2,B.Code,m,U32.to_nat(a)),"NO: request-main-code")
        mask : B.Code <- K.need(B.Code,List.get(&2,B.Code,w,U32.to_nat(b)),"NO: request-mask-code")
        data : Read<List<&2,Link>> <- links(U32.to_nat(n),Read{[],xs},0n)
        end(codes,main,mask,data)
    case _: bad(Shape)

def load(+items: List<&2,P.Item>) -> IO(Shape):
  do IO<Shape>:
    bytes : H.Bytes <- Codes.item(items,"codes")
    codes : H.Bytes <- R.words(H.u32s(bytes))
    all : S.Codes <- S.codes(codes)
    raw : H.Bytes <- Codes.item(items,"request's shape")
    words : H.Bytes <- R.words(H.u32s(raw))
    read(all,words)

def carry() -> Notice: Notice{F.Member{0n,2n,3n,0n,False{}},0n,0n}

def moment(xs: Notices, +at: Nat, +acc: Notices) -> Notices:
  match xs:
    case []: List.reverse(&2,Notice,acc)
    case Notice{m,+t,f} <> rest:
      n: Notice = Notice{m,t,f}
      moment(rest,at,Bool.pick(Notices,Nat.is_eq(at,t),n <> acc,acc))

def survivors(xs: Notices, acc: Notices) -> Notices:
  match xs:
    case []: List.reverse(&2,Notice,acc)
    case Notice{F.Member{id,n,d,_,_},_,0n} <> tail: survivors(tail,acc)
    case Notice{F.Member{id,n,d,_,_},_,1n+p} <> tail:
      +life = p
      next: Notice = Notice{F.Member{id,n,d,0n,Nat.is_lt(0n,life)},0n,life}
      survivors(tail,next <> acc)

def members(xs: Notices) -> F.Members:
  match xs:
    case []: []
    case Notice{m,_,_} <> tail: m <> members(tail)

def size(ms: F.Members, +mask: Bool, acc: Nat) -> Nat:
  match ms:
    case []: acc
    case x <> rest: size(rest,mask,Nat.add(acc,O.ceil_power(F.used(mask,x))))

def layout(xs: Notices, main: B.Code, mask: B.Code) -> F.Layout:
  B.Code{_,n,_} = main
  B.Code{_,m,_} = mask
  +ms = members(xs)
  +h = C.bits(O.ceil_power(size(ms,True{},0n)))
  k = Nat.max(1n,Nat.max(h,C.bits(O.ceil_power(size(ms,False{},0n)))))
  F.Layout{ms,k,h,C.bits(n),C.bits(m)}
