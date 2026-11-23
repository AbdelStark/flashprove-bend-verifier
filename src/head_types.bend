import Base

type Run is Data:
  Run{column: Nat, length: Nat}
type Segment is Data:
  Segment{call: Nat, column_bits: Nat, length: Nat, runs: List<&2,Run>}
type Table is Data:
  Table{matrix: Nat, segment_length: Nat, offset: Nat, partitions: List<&2,Nat>}
type Shape is Data:
  Shape{fields: List<&2,Nat>, limbs: List<&2,Nat>, segments: List<&2,Segment>, tables: List<&2,Table>}

def field(s: Shape, index: Nat) -> Nat:
  Shape{fs,_,_,_} = s
  Maybe.default(&2,Nat,List.get(&2,Nat,fs,index),0n)

def limbs(s: Shape) -> List<&2,Nat>:
  Shape{_,ls,_,_} = s
  ls

def segment(s: Shape, index: Nat) -> Segment:
  Shape{_,_,ss,_} = s
  Maybe.default(&2,Segment,List.get(&2,Segment,ss,index),Segment{0n,0n,0n,[]})

def table(s: Shape, index: Nat) -> Table:
  Shape{_,_,_,ts} = s
  Maybe.default(&2,Table,List.get(&2,Table,ts,index),Table{0n,0n,0n,[]})

def at(t: Table) -> Nat:
  Table{_,_,at,_} = t
  at

def offset(s: Shape, index: Nat) -> Nat: at(table(s,index))
