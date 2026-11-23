import Base
import ./plan.bend as Plan
import ./key_stage_codes.bend as C
import ./key_stage_openings.bend as K
import ./wire_reader.bend as R
import ./hash_bytes.bend as H
import ./header.bend as Header

type Run is Data:
  Run{cell: U32, row: U32, count: U32, stride: U32}
type Part is Data:
  Part{bits: U32, runs: List<&2,Run>}
type Lookup is Data:
  Lookup{digits: U32, planes: U32, live: U32, weights: H.Bytes, offset: U32, pad: U32,
    parts: List<&2,Part>, first: H.Bytes}
type Metadata is Data:
  Metadata{lookups: List<&2,Lookup>, col_bits: Nat, matrix_rows: Nat, main_rows: U32, mask_rows: U32}

type Read<-A: Data> is Data:
  Read{value: A, rest: H.Bytes}

def fail(-A: Data) -> IO(A):
  IO.die(A,1,"NO: key-lookup-shape")

def numbers(xs: H.Bytes) -> IO(Read<H.Bytes>):
  match xs:
    case +count <> +tail:
      +n = U32.to_nat(count)
      do IO<Read<H.Bytes>>:
        ok : Unit <- Header.require(Nat.is_le(n,H.length(tail)),"NO: key-lookup-vector")
        return Read{H.take(tail,n),List.drop(&2,U32,tail,n)}
    case _: fail(Read<H.Bytes>)

def runs(n: Nat, xs: H.Bytes, acc: List<&2,Run>) -> IO(Read<List<&2,Run>>):
  match n xs:
    case 0n more: IO.pure(Read<List<&2,Run>>,Read{List.reverse(&2,Run,acc),more})
    case 1n+k a <> b <> c <> d <> rest: runs(k,rest,Run{a,b,c,d} <> acc)
    case _ _: fail(Read<List<&2,Run>>)

def with_run(parsed: Read<List<&2,Run>>, bits: U32, acc: List<&2,Part>) -> Read<List<&2,Part>>:
  Read{rows,rest} = parsed
  Read{Part{bits,rows} <> acc,rest}

def parts(n: Nat, parsed: Read<List<&2,Part>>) -> IO(Read<List<&2,Part>>):
  match n parsed:
    case 0n Read{acc,rest}: IO.pure(Read<List<&2,Part>>,Read{List.reverse(&2,Part,acc),rest})
    case 1n+k Read{acc,bits <> count <> rest}:
      do IO<Read<List<&2,Part>>>:
        found : Read<List<&2,Run>> <- runs(U32.to_nat(count),rest,[])
        parts(k,with_run(found,bits,acc))
    case _ _: fail(Read<List<&2,Part>>)

def lookup(order: Read<H.Bytes>, parts: List<&2,Part>, d: U32, mu: U32, live: U32, ws: H.Bytes, off: U32, pad: U32) -> Read<Lookup>:
  Read{first,rest} = order
  Read{Lookup{d,mu,live,ws,off,pad,parts,first},rest}

def finish_parts(found: Read<List<&2,Part>>, d: U32, mu: U32, live: U32, ws: H.Bytes, off: U32, pad: U32) -> IO(Read<Lookup>):
  Read{parts,rest} = found
  do IO<Read<Lookup>>:
    order : Read<H.Bytes> <- numbers(rest)
    return lookup(order,parts,d,mu,live,ws,off,pad)

def extras(weights: Read<H.Bytes>, d: U32, +mu: U32, +live: U32) -> IO(Read<Lookup>):
  match weights:
    case Read{ws,off <> pad <> n <> rest}:
      width = Bool.pick(U32,U32.is_zero(live),U32.shln(1,U32.to_nat(mu)),live)
      do IO<Read<Lookup>>:
        found : Read<List<&2,Part>> <- parts(U32.to_nat(n),Read{[],rest})
        finish_parts(found,d,mu,width,ws,off,pad)
    case _: fail(Read<Lookup>)

def more(row: Read<Lookup>, acc: List<&2,Lookup>) -> Read<List<&2,Lookup>>:
  Read{x,tail} = row
  Read{x <> acc,tail}

def lookups(n: Nat, buf: Read<List<&2,Lookup>>) -> IO(Read<List<&2,Lookup>>):
  match n buf:
    case 0n Read{acc,tail}: IO.pure(Read<List<&2,Lookup>>,Read{List.reverse(&2,Lookup,acc),tail})
    case 1n+k Read{acc,d <> mu <> live <> rest}:
      do IO<Read<List<&2,Lookup>>>:
        ws : Read<H.Bytes> <- numbers(rest)
        row : Read<Lookup> <- extras(ws,d,mu,live)
        lookups(k,more(row,acc))
    case _ _: fail(Read<List<&2,Lookup>>)

def shapes(found: Read<List<&2,Lookup>>, +table: H.Bytes) -> IO(Metadata):
  match found:
    case Read{rows,_ <> _ <> main <> _ <> mask <> _}:
      +b = List.drop(&2,U32,table,3n)
      +c = List.drop(&2,U32,table,15n)
      do IO<Metadata>:
        v : U32 <- K.need(U32,List.head(&2,U32,b),"NO: key-table-rows")
        lo : U32 <- K.need(U32,List.head(&2,U32,c),"NO: key-table-columns")
        m : U32 <- K.need(U32,List.get(&2,U32,c,1n),"NO: key-matrix-rows")
        return Metadata{rows,Nat.add(U32.to_nat(v),U32.to_nat(lo)),U32.to_nat(m),main,mask}
    case _: fail(Metadata)

def ranges(xs: H.Bytes, table: H.Bytes) -> IO(Metadata):
  match xs:
    case n <> rest:
      do IO<Metadata>:
        found : Read<List<&2,Lookup>> <- lookups(U32.to_nat(n),Read{[],rest})
        shapes(found,table)
    case _: fail(Metadata)

def load(+items: List<&2,Plan.Item>) -> IO(Metadata):
  do IO<Metadata>:
    raw : H.Bytes <- C.item(items,"ranges")
    # All numbers, including the lookup digit weights and offset, fit U32 in the admitted profiles.
    fields : H.Bytes <- R.words(H.u32s(raw))
    table : H.Bytes <- C.table_words(items)
    ranges(fields,table)
