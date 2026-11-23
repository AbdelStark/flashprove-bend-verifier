import Base
import ./hash_bytes.bend as H
import ./header.bend as Header
import ./plan.bend as P
import ./wire_reader.bend as R
import ./leaf_shape.bend as Shape
import ./base_check.bend as B

type Final is Data:
  Final{main: B.Code, mask: B.Code}

type Finals is Data:
  Finals{ranges: Final, folded: Final, omega: Final, own: Final}

def named(entry: P.Item, wanted: String) -> Bool:
  P.Item{id,_} = entry
  String.eq(id,wanted)

def chosen(x: Maybe<&2,P.Item>) -> IO(H.Bytes):
  match x:
    case Some{P.Item{_,raw}}: IO.pure(H.Bytes,raw)
    case _: IO.die(H.Bytes,1,"NO: key-plan-item")

def lookup(items: List<&2,P.Item>, +wanted: String) -> Maybe<&2,P.Item>:
  match items:
    case []: None{}
    case +entry <> tail: Bool.pick(Maybe<&2,P.Item>,named(entry,wanted),Some{entry},lookup(tail,wanted))

def item(items: List<&2,P.Item>, +wanted: String) -> IO(H.Bytes):
  chosen(lookup(items,wanted))

def table_words(items: List<&2,P.Item>) -> IO(H.Bytes):
  do IO<H.Bytes>:
    raw : H.Bytes <- item(items,"the test on the table")
    R.words(H.u32s(raw))

def final(stage: Shape.Stage) -> Final:
  Shape.Stage{m,n,_,_} = stage
  Final{m,n}

def stage(xs: H.Bytes, codes: Shape.Codes) -> IO(Final):
  match xs:
    case [base,mask,0,0]:
      do IO<Final>:
        stage : Shape.Stage <- Shape.find_stage(codes,base,mask,0,0)
        return final(stage)
    case _: IO.die(Final,1,"NO: key-final-code")

def range_final(+bytes: H.Bytes, codes: Shape.Codes) -> IO(Final):
  # R13.14 ends in its stages followed by the choices word. Earlier lookup weights are full field words.
  suffix = List.drop(&2,U32,bytes,Nat.sub(H.length(bytes),40n))
  do IO<Final>:
    +ws : H.Bytes <- R.words(H.u32s(suffix))
    ok : Unit <- Header.require(R.equal(List.drop(&2,U32,ws,4n),[1]),"NO: key-range-choices")
    stage(List.take(&2,U32,ws,4n),codes)

type Rest is Data:
  Rest{last: Final, remaining: H.Bytes}

def last(xs: H.Bytes, codes: Shape.Codes) -> IO(Rest):
  match xs:
    case +n <> +rest:
      +words = Nat.mul(4n,U32.to_nat(n))
      code = List.take(&2,U32,List.drop(&2,U32,rest,Nat.sub(words,4n)),4n)
      do IO<Rest>:
        ok : Unit <- Header.require(U32.is_ge(n,2) && Nat.is_le(words,H.length(rest)),"NO: key-stage-list")
        fin : Final <- stage(code,codes)
        return Rest{fin,List.drop(&2,U32,rest,words)}
    case _: IO.die(Rest,1,"NO: key-stage-list")

def finish(own: Rest, ranges: Final, folded: Final, omega: Final) -> IO(Finals):
  Rest{f,after} = own
  do IO<Finals>:
    ok : Unit <- Header.require(R.equal(after,[0,1]),"NO: key-split-choices")
    return Finals{ranges,folded,omega,f}

def own(omega: Rest, codes: Shape.Codes, ranges: Final, folded: Final) -> IO(Finals):
  Rest{f,after} = omega
  do IO<Finals>:
    v : Rest <- last(after,codes)
    finish(v,ranges,folded,f)

def omega(folded: Rest, +codes: Shape.Codes, ranges: Final) -> IO(Finals):
  Rest{f,after} = folded
  do IO<Finals>:
    v : Rest <- last(after,codes)
    own(v,codes,ranges,f)

def load(+items: List<&2,P.Item>) -> IO(Finals):
  do IO<Finals>:
    raw : H.Bytes <- item(items,"codes")
    decoded : H.Bytes <- R.words(H.u32s(raw))
    +codes : Shape.Codes <- Shape.codes(decoded)
    ranges : H.Bytes <- item(items,"ranges")
    r : Final <- range_final(ranges,codes)
    words : H.Bytes <- table_words(items)
    folded : Rest <- last(List.drop(&2,U32,words,50n),codes)
    omega(folded,codes,r)
