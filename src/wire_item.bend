import Base
import ./hash_bytes.bend as H

def text(name: String) -> H.Bytes:
  match name:
    case SNil{}: []
    case SCon{c,tail}: Char.to_u32(c) <> text(tail)

def blob(+xs: H.Bytes) -> H.Bytes:
  H.cat([H.word(U32.from_nat(H.length(xs))),xs])

def item(name: String, value: H.Bytes) -> H.Bytes:
  H.cat([blob(text(name)),blob(value)])
