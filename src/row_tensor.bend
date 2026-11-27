import Base
import ./fold.bend as F
import ./sumcheck.bend as E
import ./extension.bend as Ext
import ./base_check.bend as B
import ./goldilocks.bend as Field
import ./pow2.bend as P2

def eq(xs: B.Elements) -> F.Factors:
  match xs:
    case []: []
    case +x <> tail: F.Factor{F.sub(F.one(),x),x} <> eq(tail)

def select(bit: Nat) -> F.Factor:
  match bit:
    case 0n: F.Low{}
    case _: F.High{}

type Member is Data:
  Only{}
  Left{}
  Right{}

def member_bit(member: Member, remaining: F.Factors) -> F.Factors:
  match member:
    case Only{}: remaining
    case Left{}: select(0n) <> remaining
    case Right{}: select(1n) <> remaining

def choice(bits: Nat, +index: Nat) -> F.Factors:
  match bits:
    case 0n: []
    case 1n+k: select(Nat.mod(index,2n)) <> choice(k,Nat.div(index,2n))

def scalar(v: Field.Gl) -> Ext.E3:
  Field.Gl{h,l} = v
  Ext.E3{h,l,0,0,0,0}

def powers(bits: Nat, +z: Field.Gl) -> F.Factors:
  match bits:
    case 0n: []
    case 1n+k: F.Factor{F.one(),scalar(z)} <> powers(k,Ext.product(z,z))

def entry(fs: F.Factors, +n: Nat, acc: Ext.E3) -> Ext.E3:
  match fs:
    case []: acc
    case f <> tail:
      pick = F.at_bit(f,Nat.is_eq(Nat.mod(n,2n),1n))
      entry(tail,Nat.div(n,2n),E.mul(acc,pick))

# A dyadic block keeps the low coordinates free and fixes the high coordinates to its prefix.
def fixed(fs: F.Factors, +prefix: Nat) -> F.Factors:
  match fs:
    case []: []
    case +x <> tail:
      l = F.at_bit(x,False{})
      h = F.at_bit(x,True{})
      f = Bool.pick(F.Factor,Nat.is_eq(Nat.mod(prefix,2n),0n),F.Factor{l,F.zero()},F.Factor{F.zero(),h})
      f <> fixed(tail,Nat.div(prefix,2n))

def block(+fs: F.Factors, +low: Nat, prefix: Nat) -> F.Factors:
  List.append(&2,F.Factor,List.take(&2,F.Factor,fs,low),fixed(List.drop(&2,F.Factor,fs,low),prefix))

def append_block(bit: Nat, +fs: F.Factors, +low: Nat, +n: Nat, weight: Ext.E3, tail: F.Form) -> F.Form:
  match bit:
    case 0n: tail
    case _: F.Term{weight,block(fs,low,Nat.mul(2n,n))} <> tail

def blocks(bits: Nat, +fs: F.Factors, +n: Nat, +low: Nat, +weight: Ext.E3) -> F.Form:
  match bits:
    case 0n: []
    case 1n+k:
      +next = Nat.div(n,2n)
      append_block(Nat.mod(n,2n),fs,low,next,weight,blocks(k,fs,next,1n+low,weight))

def below(+fs: F.Factors, +length: Nat, +weight: Ext.E3) -> F.Form:
  +bits = List.length(&2,F.Factor,fs)
  Bool.pick(F.Form,Nat.is_eq(length,P2.pow2(bits)),[F.Term{weight,fs}],blocks(bits,fs,length,0n,weight))

def extend(terms: F.Form, +bits: Nat, +pos: Nat) -> F.Form:
  match terms:
    case []: []
    case F.Term{w,+fs} <> tail:
      extra = choice(Nat.sub(bits,List.length(&2,F.Factor,fs)),pos)
      F.Term{w,List.append(&2,F.Factor,fs,extra)} <> extend(tail,bits,pos)

# The stored table's folded vector has row bits high. The oracle's column has row bits low.
def rows_high(terms: F.Form, +places: Nat, +side: Member) -> F.Form:
  match terms:
    case []: []
    case F.Term{w,+fs} <> tail:
      ordered = List.append(&2,F.Factor,List.drop(&2,F.Factor,fs,places),member_bit(side,List.take(&2,F.Factor,fs,places)))
      F.Term{w,ordered} <> rows_high(tail,places,side)

def side_bit(terms: F.Form, +rows: Nat, +side: Member) -> F.Form:
  match terms:
    case []: []
    case F.Term{w,+fs} <> tail:
      ordered = List.append(&2,F.Factor,List.take(&2,F.Factor,fs,rows),member_bit(side,List.drop(&2,F.Factor,fs,rows)))
      F.Term{w,ordered} <> side_bit(tail,rows,side)

def scale_by(+mode: U32, terms: F.Form, +s: Ext.E3, acc: F.Form) -> F.Form:
  match terms:
    case []: acc
    case F.Term{w,fs} <> rest: scale_by(mode,rest,s,F.Term{E.by(mode,s,w),fs} <> acc)

def scale(terms: F.Form, +s: Ext.E3, acc: F.Form) -> F.Form: scale_by(E.unit(s),terms,s,acc)
