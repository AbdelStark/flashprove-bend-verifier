import Base
import ../src/key_stage_matrix.bend as M
import ../src/key_stage_lookup_plan.bend as Plan
import ../src/extension.bend as Ext
import ../src/sumcheck.bend as E
import ../src/row_tensor.bend as X
import ../src/fold.bend as F
import ../src/base_check.bend as B

def at(form: F.Form, +i: Nat, acc: Ext.E3) -> Ext.E3:
  match form:
    case []: acc
    case F.Term{w,factors} <> tail: at(tail,i,E.add(acc,X.entry(factors,i,w)))

def verify(n: Nat, +cell: Nat, +row: Nat, +count: Nat, +form: F.Form, +eq: F.Factors, +scale: Ext.E3) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +p = k
      inside = Nat.is_le(row,p) && Nat.is_lt(p,Nat.add(row,count))
      expected = Bool.pick(Ext.E3,inside,X.entry(eq,Nat.add(cell,Nat.sub(p,row)),scale),F.zero())
      B.equal(at(form,p,F.zero()),expected) && verify(p,cell,row,count,form,eq,scale)

def direct(n: Nat, +p: F.Factors, i: Nat, acc: Ext.E3) -> Ext.E3:
  match n:
    case 0n: acc
    case 1n+k:
      +j = i
      direct(k,p,1n+j,E.add(acc,X.entry(p,j,F.one())))

def cases(count: Nat, +cell: Nat, +row: Nat, +fs: F.Factors, +point: B.Elements) -> Bool:
  match count:
    case 0n: True{}
    case 1n+k:
      +prev = k
      +n: Nat = 1n+prev
      +scale: Ext.E3 = Ext.E3{0,11,0,13,0,17}
      form = M.stretch(9n,4n,cell,row,n,fs,scale,[])
      mass = M.coverage([Plan.Run{U32.from_nat(cell),0,U32.from_nat(n),0}],point,F.zero())
      verify(16n,cell,row,n,form,fs,scale) && B.equal(mass,direct(n,fs,cell,F.zero())) &&
        cases(prev,cell,row,fs,point)

def each_row(n: Nat, +cell: Nat, +fs: F.Factors, +point: B.Elements) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +row = k
      cases(Nat.sub(16n,Nat.max(cell,row)),cell,row,fs,point) && each_row(row,cell,fs,point)

def each_cell(n: Nat, +fs: F.Factors, +point: B.Elements) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +cell = k
      each_row(16n,cell,fs,point) && each_cell(cell,fs,point)

def main() -> IO(Unit):
  +point: B.Elements = [Ext.E3{0,2,0,3,0,1},Ext.E3{0,5,0,7,0,2},Ext.E3{0,11,0,13,0,3},Ext.E3{0,17,0,19,0,4}]
  IO.print(Bool.show(each_cell(16n,X.eq(point),point)))
#|True
