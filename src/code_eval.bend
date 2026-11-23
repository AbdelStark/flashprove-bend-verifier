import Base
import ./goldilocks.bend as Field
import ./extension.bend as Ext
import ./chain.bend as Bits

# R12.11 permits 1 <= log_n <= 32. A Nat position is checked before its U32 conversion.
def valid(+log_n: Nat, pos: Nat) -> Bool:
  Nat.is_le(1n,log_n) && Nat.is_le(log_n,32n) && Nat.is_lt(pos,Nat.pow(2n,Nat.min(log_n,32n)))

# In descending bit order, root goes from order 2^32 to order 2 by repeated squaring.
def point_bits(count: Nat, +pos: U32, +root: Field.Gl, +acc: Field.Gl) -> Field.Gl:
  match count:
    case 0n: acc
    case 1n+k:
      +i = k
      bit = U32.and(U32.shrn(pos,i),1)
      next = Bool.pick(Field.Gl,U32.is_zero(bit),acc,Ext.product(acc,root))
      point_bits(i,pos,Ext.product(root,root),next)

def point_checked(pos: U32, good: Bool) -> Maybe<&2,Field.Gl>:
  match good:
    case False{}: None{}
    case True{}: Some{point_bits(32n,pos,Field.Gl{3803148387,1464139046},Field.Gl{0,7})}

def point(+log_n: Nat, +pos: Nat) -> Maybe<&2,Field.Gl>:
  point_checked(U32.from_nat(pos),valid(log_n,pos))

# R7.2 repeats short rows by position, including the full-width identity at log_short=32.
def short_position(+log_n: Nat, +log_short: Nat, +pos: Nat) -> Maybe<&2,Nat>:
  good = valid(log_n,pos) && Nat.is_le(log_short,log_n)
  Bool.pick(Maybe<&2,Nat>,good,Some{U32.to_nat(U32.and(U32.from_nat(pos),Bits.mask32(log_short)))},None{})

def horner(~A: Data, ~step: Field.Gl -> A -> A -> A, +z: Field.Gl, descending: List<&2,A>, acc: A) -> A:
  match descending:
    case []: acc
    case c <> rest: horner(A,step,z,rest,step(z,acc,c))

# Tail coefficients have the lowest powers. Each input list is in increasing degree order.
def row(~A: Data, ~step: Field.Gl -> A -> A -> A, +z: Field.Gl, message: List<&2,A>, tail: List<&2,A>, zero: A) -> A:
  high = horner(A,step,z,List.reverse(&2,A,message),zero)
  horner(A,step,z,List.reverse(&2,A,tail),high)

def step_f(z: Field.Gl, acc: Field.Gl, c: Field.Gl) -> Field.Gl:
  Ext.add(Ext.product(acc,z),c)

def symbol_f(z: Field.Gl, message: List<&2,Field.Gl>, tail: List<&2,Field.Gl>) -> Field.Gl:
  row(Field.Gl,step_f,z,message,tail,Field.Gl{0,0})

def step_e(point: Field.Gl, acc: Ext.E3, c: Ext.E3) -> Ext.E3:
  Ext.E3{ah,al,bh,bl,ch,cl} = acc
  Ext.E3{dh,dl,eh,el,fh,fl} = c
  +z = point
  Ext.pack(Ext.add(Ext.product(Field.Gl{ah,al},z),Field.Gl{dh,dl}),
           Ext.add(Ext.product(Field.Gl{bh,bl},z),Field.Gl{eh,el}),
           Ext.add(Ext.product(Field.Gl{ch,cl},z),Field.Gl{fh,fl}))

def symbol_e(z: Field.Gl, message: List<&2,Ext.E3>, tail: List<&2,Ext.E3>) -> Ext.E3:
  row(Ext.E3,step_e,z,message,tail,Ext.E3{0,0,0,0,0,0})
