import Base
import ./base_check.bend as BaseCase
import ./hash_bytes.bend as H
import ./plan.bend as Plan
import ./wire_reader.bend as R
import ./header.bend as Header
import ./commitment.bend as Commitment

type Stage is Data:
  Stage{main: BaseCase.Code, mask: BaseCase.Code, k: U32, h: U32}

type Shape is Data:
  Shape{table_depth: U32, message: U32, random: U32, row_bits: U32, samples: U32, salt: U32,
    first_count: U32, further_count: U32, rows: U32, stages: List<&2,Stage>}

def absent(-A: Type) -> IO(A):
  IO.die(A, 1, "NO: leaf-shape")

def parse_codes(xs: H.Bytes) -> List<&2, BaseCase.Code>:
  match xs:
    case depth <> ell <> tail <> rest:
      BaseCase.Code{U32.to_nat(depth),U32.to_nat(ell),U32.to_nat(tail)} <> parse_codes(rest)
    case _: []

type Codes is Data:
  Codes{main: List<&2,BaseCase.Code>, mask: List<&2,BaseCase.Code>}

def masks(xs: H.Bytes, main: List<&2,BaseCase.Code>) -> IO(Codes):
  match xs:
    case +n <> +tail:
      do IO<Codes>:
        valid : Unit <- Header.require(Nat.is_eq(List.length(&2,U32,tail),Nat.mul(3n,U32.to_nat(n))), "NO: leaf-codes")
        return Codes{main,parse_codes(tail)}
    case _: absent(Codes)

def codes(xs: H.Bytes) -> IO(Codes):
  match xs:
    case n <> +tail:
      +count = Nat.mul(3n,U32.to_nat(n))
      masks(List.drop(&2,U32,tail,count),parse_codes(List.take(&2,U32,tail,count)))
    case _: absent(Codes)

def stage(a: Maybe<&2,BaseCase.Code>, b: Maybe<&2,BaseCase.Code>, k: U32, h: U32) -> IO(Stage):
  match a b:
    case Some{m} Some{mask}: IO.pure(Stage,Stage{m,mask,k,h})
    case _ _: absent(Stage)

def find_stage(cs: Codes, c: U32, m: U32, k: U32, h: U32) -> IO(Stage):
  Codes{main,mask} = cs
  stage(List.get(&2,BaseCase.Code,main,U32.to_nat(c)),List.get(&2,BaseCase.Code,mask,U32.to_nat(m)),k,h)

def end(xs: H.Bytes) -> IO(List<&2,Stage>):
  match xs:
    case [1]: IO.pure(List<&2,Stage>,[])
    case _: absent(List<&2,Stage>)

def later(n: Nat, xs: H.Bytes, +cs: Codes) -> IO(List<&2,Stage>):
  match n xs:
    case 0n tail: end(tail)
    case 1n+p Con{c,Con{m,Con{k,Con{h,rest}}}}:
      do IO<List<&2,Stage>>:
        s : Stage <- find_stage(cs,c,m,k,h)
        tail : List<&2,Stage> <- later(p,rest,cs)
        return s <> tail
    case _ _: absent(List<&2,Stage>)

# All four admitted configurations use one OOD answer, high rows and a riding mask.
def geometry(xs: H.Bytes, +cs: Codes) -> IO(Shape):
  match xs:
    case depth <> ell <> rand <> v <> 1 <> salt <> a <> b <> c <> m <> +rows <> 1 <> 0 <> 1 <> n <> rest:
      +k = U32.from_nat(Nat.add(1n,Commitment.variables(rows)))
      do IO<Shape>:
        first : Stage <- find_stage(cs,c,m,k,0)
        tail : List<&2,Stage> <- later(U32.to_nat(n),rest,cs)
        return Shape{depth,ell,rand,v,1,salt,a,b,rows,first <> tail}
    case _: absent(Shape)

def from_items(items: List<&2,Plan.Item>) -> IO(Shape):
  match items:
    case [Plan.Item{"codes",raw_codes}, Plan.Item{"the link",raw_link}]:
      do IO<Shape>:
        words : H.Bytes <- R.words(H.u32s(raw_codes))
        cs : Codes <- codes(words)
        link : H.Bytes <- R.words(H.u32s(raw_link))
        geometry(link,cs)
    case _: absent(Shape)
