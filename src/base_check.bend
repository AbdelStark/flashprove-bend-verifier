import Base
import ./goldilocks.bend as Field
import ./opening_bytes.bend as OB
import ./hash_bytes.bend as H
import ./extension.bend as Ext
import ./sumcheck.bend as E
import ./code_eval.bend as Eval

def Elements() -> Data:
  List<&2,Ext.E3>

type Code is Data:
  Code{log_n: Nat, ell: Nat, tail: Nat}

type Rows is Data:
  Rows{main_log: Nat, mask_log: Nat, main: Elements, mask: Elements, main_tail: Elements, mask_tail: Elements}

def code_ok(code: Code) -> Bool:
  Code{+n,+m,r} = code
  +limit = Nat.pow(2n,Nat.min(n,32n))
  Nat.is_le(1n,n) && Nat.is_le(n,32n) && Nat.is_le(1n,m) && Nat.is_le(m,limit) && Nat.is_le(r,Nat.sub(limit,m))

# Called only for canonical, complete 24-byte extension elements. The wire limbs are (low, high).
def elements(words: H.Bytes, acc: Elements) -> Elements:
  match words:
    case a <> b <> c <> d <> e <> f <> rest: elements(rest,Ext.E3{b,a,d,c,f,e} <> acc)
    case _: List.reverse(&2,Ext.E3,acc)

def split(main: Code, mask: Code, +all: Elements) -> Rows:
  Code{a,+m,+r} = main
  Code{b,+n,s} = mask
  +after_main = List.drop(&2,Ext.E3,all,m)
  +tails = List.drop(&2,Ext.E3,after_main,n)
  Rows{a,b,List.take(&2,Ext.E3,all,m),List.take(&2,Ext.E3,after_main,n),
    List.take(&2,Ext.E3,tails,r),List.drop(&2,Ext.E3,tails,r)}

# Consume one extension element at a time. The small fixture's BASE is 64,608 bytes.
def read_elements(count: Nat, raw: H.Bytes, acc: Elements, good: Bool) -> Maybe<&2,Elements>:
  match count raw good:
    case 0n Nil{} True{}: Some{List.reverse(&2,Ext.E3,acc)}
    case 1n+k Con{x,xs} True{}:
      +buf: H.Bytes = x <> xs
      +chunk = List.take(&2,U32,buf,24n)
      +words = H.u32s(chunk)
      ok = Nat.is_eq(List.length(&2,U32,chunk),24n) && List.all(&2,U32,b => U32.is_le(b,255),chunk) && OB.canonical(words)
      read_elements(k,List.drop(&2,U32,buf,24n),List.append(&2,Ext.E3,elements(words,[]),acc),ok)
    case _ _ _: None{}

def decoded(main: Code, mask: Code, value: Maybe<&2,Elements>) -> Maybe<&2,Rows>:
  match value:
    case Some{xs}: Some{split(main,mask,xs)}
    case None{}: None{}

def read(main: Code, mask: Code, raw: H.Bytes) -> Maybe<&2,Rows>:
  Code{+a,+m,+r} = main
  Code{+b,+n,+s} = mask
  count = Nat.add(Nat.add(m,r),Nat.add(n,s))
  good = code_ok(Code{a,m,r}) && code_ok(Code{b,n,s}) && Nat.is_le(b,a)
  decoded(Code{a,m,r},Code{b,n,s},read_elements(count,raw,[],good))

def equal(x: Ext.E3, y: Ext.E3) -> Bool:
  Ext.E3{a,b,c,d,e,f} = x
  Ext.E3{g,h,i,j,k,l} = y
  U32.is_eq(a,g) && U32.is_eq(b,h) && U32.is_eq(c,i) && U32.is_eq(d,j) && U32.is_eq(e,k) && U32.is_eq(f,l)

def masked(star: Ext.E3, lambda: Ext.E3, original: Ext.E3) -> Ext.E3:
  E.add(star,E.mul(lambda,original))

# R7.1 orders both main rows before either mask row when the masking oracle rides with the last switch.
def at_points(rows: Rows, +lambda: Ext.E3, column: Elements, a: Maybe<&2,Field.Gl>, b: Maybe<&2,Field.Gl>) -> Bool:
  match rows column a b:
    case Rows{_,_,main,mask,r,s} Con{v,Con{star,Con{w,Con{mask_star,Nil{}}}}} Some{z} Some{short_z}:
      equal(Eval.symbol_e(z,main,r),masked(star,lambda,v)) && equal(Eval.symbol_e(short_z,mask,s),masked(mask_star,lambda,w))
    case _ _ _ _: False{}

def at_place(+rows: Rows, lambda: Ext.E3, +pos: Nat, +words: H.Bytes) -> Bool:
  Rows{+a,+b,m,n,r,s} = rows
  good = Nat.is_eq(List.length(&2,U32,words),24n) && OB.canonical(words)
  good && at_points(Rows{a,b,m,n,r,s},lambda,elements(words,[]),Eval.point(a,pos),Eval.point(b,OB.short(b,pos)))

def compare(+rows: Rows, +lambda: Ext.E3, places: OB.Places, columns: OB.Columns) -> Bool:
  match places columns:
    case Nil{} Nil{}: True{}
    case Con{+pos,tail} Con{OB.Column{i,words},rest}:
      Nat.is_eq(pos,i) && at_place(rows,lambda,pos,words) && compare(rows,lambda,tail,rest)
    case _ _: False{}

def symbols(+rows: Rows, lambda: Ext.E3, +places: OB.Places, columns: OB.Columns) -> Bool:
  Rows{+a,b,m,n,r,s} = rows
  OB.valid_places(places,a) && compare(Rows{a,b,m,n,r,s},lambda,places,columns)

def dot(xs: Elements, ws: Elements, acc: Ext.E3) -> Maybe<&2,Ext.E3>:
  match xs ws:
    case Nil{} Nil{}: Some{acc}
    case Con{x,rest} Con{w,more}: dot(rest,more,E.add(acc,E.mul(w,x)))
    case _ _: None{}

def finish_dot(value: Maybe<&2,Ext.E3>, expected: Ext.E3) -> Bool:
  match value:
    case None{}: False{}
    case Some{v}: equal(v,expected)

def mask_dot(left: Maybe<&2,Ext.E3>, mask: Elements, weights: Elements, expected: Ext.E3) -> Bool:
  match left:
    case None{}: False{}
    case Some{v}: finish_dot(dot(mask,weights,v),expected)

# BASE's random tails enter the symbol tests only. The weights and target come from the carried claim.
def linear(rows: Rows, lambda: Ext.E3, target_star: Ext.E3, target: Ext.E3, main_weights: Elements, mask_weights: Elements) -> Bool:
  Rows{_,_,m,n,_,_} = rows
  mask_dot(dot(m,main_weights,Ext.E3{0,0,0,0,0,0}),n,mask_weights,masked(target_star,lambda,target))
