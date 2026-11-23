import Base
import ./header.bend as Header
import ./hash_bytes.bend as H
import ./policy.bend as P
import ./policy_frame.bend as Fr
import ./policy_hash.bend as K
import ./policy_model.bend as Model
import ./policy_scales.bend as Scales
import ./policy_tables.bend as T

def bytes(text: String) -> H.Bytes:
  match text:
    case SNil{}: []
    case SCon{c,tail}: Char.to_u32(c) <> bytes(tail)

def text_words(text: String) -> Fr.Words:
  H.u32s(bytes(text))

def call_text(lines: P.Lines, +prefix: String, acc: String) -> String:
  match lines:
    case []: acc
    case +line <> tail:
      text = Bool.pick(String,String.starts_with(line,prefix),line ++ "\n","")
      call_text(tail,prefix,acc ++ text)

def head_calls() -> String:
  "callH R16a R16 NF NFH HD0\ncallH R16b R16 HD1\ncallH R8 R8 ROW HD2\ncallH FEa FE HE0\ncallH FEb FE HE1\ncallH FC FC CNF\n"

def td(table: T.Table) -> Fr.Words:
  T.Table{_,digest} = table
  digest

def table_size(table: T.Table) -> U32:
  T.Table{words,_} = table
  U32.from_nat(List.length(&2,U32,words))

def soft_size(tables: T.Tables) -> U32:
  T.Tables{_,_,_,soft} = tables
  table_size(soft)

# R15.5's 177 words. The initial request statement fixes word 171 to zero.
# The y token is compared with the opened output-head scalar at its own round.
def encode(parts: Model.Parts, frame: Fr.Frame, tables: T.Tables,
    scales: Fr.Words, request: Fr.Words) -> Fr.Words:
  Model.Parts{base,ff,attention,head,+calls} = parts
  Fr.Frame{sec,_,_,_,_,_,_,b,n,_,m,w} = frame
  T.Tables{silu,sig,rot,soft} = tables
  +head_text = call_text(calls,"callH ","")
  hh = K.k(73,text_words(Bool.pick(String,String.is_empty(head_text),head_calls(),head_text)))
  H.cat([[1295397120,Header.le32(72,56,50,49)],base,K.k(73,text_words(call_text(calls,"call ",""))),ff,
    td(silu),td(sig),td(rot),K.tk(scales),attention,td(soft),K.k(73,text_words(call_text(calls,"callA ",""))),
    head,hh,K.tk(request),[0,sec,w,b,n,m]])

type Statement is Data:
  Statement{words: Fr.Words, request: Fr.Words, y: U32, tables: T.Tables, scales: Fr.Words,
    frame: Fr.Frame, model: Model.Parts, policy: P.Lines}

def request_input(dims: U32 & U32, req_path: String, y_path: String) -> IO(Fr.Words & U32):
  (+t,v) = dims
  do IO<Fr.Words & U32>:
    +bytes : H.Bytes <- Header.bytes(req_path,U32.add(U32.shln(t,2n),9))
    raw_y : H.Bytes <- Header.bytes(y_path,5)
    +y : U32 <- Header.token_word(raw_y)
    ok : Unit <- Header.request_result(Header.request_status(bytes,0,t,v,y,True{}))
    return (H.u32s(bytes),y)

def count_words(tail: Fr.Words, t: U32) -> IO(U32):
  match tail:
    case [r,e]: P.count_covered(H.cat([H.le(r),H.le(e)]),t)
    case _: IO.die(U32,1,"NO: statement-range")

def checked(value: Fr.Words & U32, +frame: Fr.Frame, +tables: T.Tables, +model: Model.Parts,
    +scales: Fr.Words, +lines: P.Lines, named: Maybe<&2,String>, +length: U32) -> IO(Statement):
  (+req,y) = value
  do IO<Statement>:
    claim : P.Claim <- P.parse(lines)
    tail : Fr.Words = List.drop(&2,U32,req,U32.to_nat(length))
    +count : U32 <- count_words(tail,length)
    ok : Unit <- Header.require(P.held(claim,named,length,count),"NO: policy")
    words : Fr.Words = encode(model,frame,tables,scales,req)
    return Statement{words,req,y,tables,scales,frame,model,lines}

def load(+config: String, req: String, y: String, tables_dir: String, named: Maybe<&2,String>) -> IO(Statement):
  do IO<Statement>:
    +lines : P.Lines <- P.document(config ++ "/policy.txt")
    frame : Fr.Frame <- Fr.parse(lines)
    model : Model.Parts <- Model.parse(lines)
    +tables : T.Tables <- T.load(lines,tables_dir)
    scales : Fr.Words <- Scales.load(lines,config,soft_size(tables))
    dims : U32 & U32 <- Header.policy_fields(lines)
    value : Fr.Words & U32 <- request_input(dims,req,y)
    lt : U32 <- P.field(lines,"lt")
    checked(value,frame,tables,model,scales,lines,named,U32.shln(1,U32.to_nat(lt)))
