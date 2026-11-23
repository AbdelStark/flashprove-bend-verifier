import Base
import ./hash_bytes.bend as H
import ./plan.bend as P
import ./leaf_shape.bend as S
import ./key_stage_codes.bend as Codes
import ./wire_reader.bend as R
import ./header.bend as Header

# R13.13. This profile uses an extension-valued Omega, one split mask, and a driving W.
type Side is Data:
  Side{main: U32, mask: U32, rows: U32, mask_rows: U32}

type Shape is Data:
  Shape{table: S.Shape, low: Nat, matrix: Nat, omega: Side, w: Side, omega_stages: List<&2,S.Stage>, own_stages: List<&2,S.Stage>}

def cut(+xs: H.Bytes, pos: Nat, count: Nat) -> H.Bytes:
  List.take(&2,U32,List.drop(&2,U32,xs,pos),count)

def side(xs: H.Bytes) -> IO(Side):
  match xs:
    case [c,z,r,3,m,1]: IO.pure(Side,Side{c,z,r,m})
    case _: IO.die(Side,1,"NO: lin-oracle-shape")

def stages(n: Nat, words: H.Bytes, +codes: S.Codes) -> IO(List<&2,S.Stage>):
  match n words:
    case 0n Nil{}: IO.pure(List<&2,S.Stage>,[])
    case 1n+k Con{a,Con{b,Con{rows,Con{masks,rest}}}}:
      do IO<List<&2,S.Stage>>:
        head : S.Stage <- S.find_stage(codes,a,b,rows,masks)
        tail : List<&2,S.Stage> <- stages(k,rest,codes)
        return head <> tail
    case _ _: IO.die(List<&2,S.Stage>,1,"NO: lin-stage-shape")

type ListCut is Data:
  ListCut{list: List<&2,S.Stage>, rest: H.Bytes}

def read_list(xs: H.Bytes, codes: S.Codes) -> IO(ListCut):
  match xs:
    case count <> +tail:
      +n = U32.to_nat(count)
      +size = Nat.mul(4n,n)
      do IO<ListCut>:
        ok : Unit <- Header.require(Nat.is_le(2n,n) && Nat.is_le(n,32n),"NO: lin-stage-count")
        list : List<&2,S.Stage> <- stages(n,List.take(&2,U32,tail,size),codes)
        return ListCut{list,List.drop(&2,U32,tail,size)}
    case _: IO.die(ListCut,1,"NO: lin-stage-count")

def list(cut: ListCut) -> List<&2,S.Stage>:
  ListCut{a,_} = cut
  a

def rest(cut: ListCut) -> H.Bytes:
  ListCut{_,b} = cut
  b

def shape(prefix: H.Bytes, o: Side, w: Side, group: List<&2,S.Stage>, other: List<&2,S.Stage>, own: List<&2,S.Stage>) -> IO(Shape):
  match prefix:
    case [d,ell,r,v,1,salt,_,4294967295,u,3,0,1,1,0,cols,low,n]:
      IO.pure(Shape,Shape{S.Shape{d,ell,r,v,1,salt,cols,0,u,group},U32.to_nat(low),U32.to_nat(n),o,w,other,own})
    case _: IO.die(Shape,1,"NO: lin-stored-table")

def parse(+words: H.Bytes, +codes: S.Codes) -> IO(Shape):
  do IO<Shape>:
    o : Side <- side(cut(words,17n,6n))
    w : Side <- side(cut(words,23n,6n))
    valid : Unit <- Header.require(R.equal(cut(words,29n,2n),[1,1]) &&
      R.equal(cut(words,31n,1n),[4294967295]) && R.equal(cut(words,33n,4n),[0,1,1,1]) &&
      R.equal(cut(words,37n,6n),[4294967295,4294967295,0,1,0,1]) && R.equal(cut(words,49n,1n),[1]),"NO: lin-split-shape")
    +first : ListCut <- read_list(List.drop(&2,U32,words,50n),codes)
    +second : ListCut <- read_list(rest(first),codes)
    +third : ListCut <- read_list(rest(second),codes)
    end : Unit <- Header.require(R.equal(rest(third),[0,1]),"NO: lin-choices")
    shape(List.take(&2,U32,words,17n),o,w,list(first),list(second),list(third))

def load(+items: List<&2,P.Item>) -> IO(Shape):
  do IO<Shape>:
    raw : H.Bytes <- Codes.item(items,"codes")
    nums : H.Bytes <- R.words(H.u32s(raw))
    codes : S.Codes <- S.codes(nums)
    words : H.Bytes <- Codes.table_words(items)
    parse(words,codes)
