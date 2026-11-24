import Base
import ./outer_source.bend as O
import ./extension.bend as X
import ./fold.bend as F
import ./base_check.bend as B
import ./sumcheck.bend as E
import ./row_tensor.bend as V
import ./key_stage_matrix.bend as Shift
import ./segment_digits.bend as Dig
import ./oracle_sample.bend as Sample

def add(a: F.Form, b: F.Form) -> F.Form: List.append(&2,F.Term,a,b)

def weight_sum(fs: F.Factors, acc: X.E3) -> X.E3:
  match fs:
    case []: acc
    case F.Factor{a,b} <> tail: weight_sum(tail,E.mul(acc,E.add(a,b)))
    case _ <> tail: weight_sum(tail,acc)

def total(rows: F.Form, acc: X.E3) -> X.E3:
  match rows:
    case []: acc
    case F.Term{c,fs} <> tail: total(tail,E.add(acc,weight_sum(fs,c)))

# Place the row-dependent weights of one logical matrix into the column
# interval [offset,offset+count) of ZZ; its row axis is shared by the planes.
def move(terms: F.Form, +row: F.Factors, +count: Nat, +offset: Nat, +bits: Nat, +factor: X.E3, acc: F.Form) -> F.Form:
  match terms:
    case []: acc
    case F.Term{w,fs} <> tail:
      moved = Shift.stretch(1n+Nat.mul(2n,bits),bits,0n,offset,count,fs,E.mul(factor,w),[])
      move(tail,row,count,offset,bits,factor,List.reverse.go(&2,F.Term,Dig.attach(row,moved),acc))

def digits(+weights: F.Form, +row_factors: F.Factors, +count: Nat, +offset: Nat, +mz: Nat, +scale: X.E3) -> F.Form:
  +bits = Sample.row_bits(Nat.mul(2n,mz))
  lower = move(weights,row_factors,count,offset,bits,scale,[])
  move(weights,row_factors,count,Nat.add(mz,offset),bits,E.mul(scale,X.E3{0,1024,0,0,0,0}),lower)

# The U3 table of a functional has nsg entries per column, at offset+c*nsg+sg.
# Shift the low-bit-packed vector into a single aligned block if possible.
def at_columns(xs: B.Elements, +offset: Nat, +stride: Nat, +bits: Nat, i: Nat, +scale: X.E3, acc: F.Form) -> F.Form:
  match xs:
    case []: acc
    case v <> rest:
      +j = i
      pos = Nat.add(offset,Nat.mul(j,stride))
      at_columns(rest,offset,stride,bits,1n+j,scale,F.Term{E.mul(v,scale),V.choice(bits,pos)} <> acc)

# Two consecutive dense column coefficients share the fixed upper factors.
def dense(cols: B.Elements, +row: F.Factors, +bits: Nat, i: Nat, +scale: X.E3, acc: F.Form) -> F.Form:
  O.pairs(cols,row,bits,i,scale,acc)
