import Base
import ../src/lin_own.bend as L
import ../src/oracle_sample.bend as Sample
import ../src/row_tensor.bend as X
import ../src/fold.bend as F
import ../src/base_check.bend as B
import ../src/extension.bend as Ext

def scalar(x: U32) -> Ext.E3: Ext.E3{0,x,0,0,0,0}

# Three rows reserve a four-row block. Member rows 0..3 map to group rows 8..11.
# With four places the member's linear index is place + 4*row. Preserve surplus
# high bits as an extra row dimension, as in rows_high and group_form.
def addresses(n: Nat, +width: Nat, +fs: F.Factors, +moved: F.Factors) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +i = k
      +extra = Nat.pow(2n,Nat.sub(width,4n))
      +block = Nat.div(i,16n)
      place = Nat.div(block,extra)
      row = Nat.add(Nat.mod(i,4n),Nat.mul(4n,Nat.mod(block,extra)))
      +source = Nat.add(place,Nat.mul(4n,row))
      inside = Nat.is_eq(Nat.mod(Nat.div(i,4n),4n),2n) && Nat.is_lt(source,Nat.pow(2n,width))
      expected = Bool.pick(Ext.E3,inside,X.entry(fs,source,scalar(13)),F.zero())
      B.equal(X.entry(moved,i,scalar(13)),expected) && addresses(i,width,fs,moved)

def check_table(+width: Nat, +fs: F.Factors, form: F.Form) -> Bool:
  match form:
    case [F.Term{w,+moved}]:
      +bits = Nat.add(Nat.max(4n,width),2n)
      B.equal(w,scalar(13)) && Nat.is_eq(List.length(&2,F.Factor,moved),bits) &&
        addresses(Nat.pow(2n,bits),width,fs,moved)
    case _: False{}

# group_form can also receive a short list directly. Insert the two selector
# bits immediately after the available member-row coordinates.
def group_addresses(n: Nat, +cut: Nat, +fs: F.Factors, +moved: F.Factors) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +i = k
      +high = Nat.div(i,cut)
      source = Nat.add(Nat.mod(i,cut),Nat.mul(cut,Nat.div(high,4n)))
      expected = Bool.pick(Ext.E3,Nat.is_eq(Nat.mod(high,4n),2n),X.entry(fs,source,scalar(13)),F.zero())
      B.equal(X.entry(moved,i,scalar(13)),expected) && group_addresses(i,cut,fs,moved)

def check_group(+width: Nat, +fs: F.Factors, form: F.Form) -> Bool:
  match form:
    case [F.Term{w,+moved}]:
      +bits = Nat.add(width,2n)
      B.equal(w,scalar(13)) && Nat.is_eq(List.length(&2,F.Factor,moved),bits) &&
        group_addresses(Nat.pow(2n,bits),Nat.pow(2n,Nat.min(2n,width)),fs,moved)
    case _: False{}

def unchanged(n: Nat, +fs: F.Factors, +moved: F.Factors) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +i = k
      B.equal(X.entry(fs,i,scalar(13)),X.entry(moved,i,scalar(13))) && unchanged(i,fs,moved)

def no_prefix(+width: Nat, fs: F.Factors, form: F.Form) -> Bool:
  match form:
    case [F.Term{w,+moved}]: B.equal(w,scalar(13)) && Nat.is_eq(List.length(&2,F.Factor,moved),width) &&
      unchanged(Nat.pow(2n,width),fs,moved)
    case _: False{}

def widths(n: Nat, +all: F.Factors) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +width = k
      +fs = List.take(&2,F.Factor,all,width)
      +term: F.Form = [F.Term{scalar(13),fs}]
      check_table(width,fs,L.table(term,3n,4n,4n,8n)) &&
        check_group(width,fs,Sample.group_form(term,2n,4n,8n)) &&
        no_prefix(width,fs,Sample.group_form(term,2n,2n,0n)) && widths(width,all)

def main() -> IO(Unit):
  IO.print(Bool.show(widths(7n,X.eq([scalar(2),scalar(3),scalar(5),scalar(7),scalar(11),scalar(13)]))))

#|True
