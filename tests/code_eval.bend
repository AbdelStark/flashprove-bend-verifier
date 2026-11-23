import Base
import ../src/code_eval.bend as Code
import ../src/goldilocks.bend as Field
import ../src/extension.bend as Ext

def show(value: Field.Gl) -> String:
  Field.Gl{hi,lo} = value
  U32.show(hi) ++ " " ++ U32.show(lo)

def point(value: Maybe<&2,Field.Gl>) -> String:
  match value:
    case None{}: "outside"
    case Some{z}: show(z)

def position(value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: "outside"
    case Some{x}: Nat.show(x)

# Pinned format-vectors.txt, R12.11: m[j]=1000003*j+17, t[j]=p-1-5*j.
def sample(value: Maybe<&2,Field.Gl>) -> String:
  match value:
    case None{}: "outside"
    case Some{+z}:
      m: List<&2,Field.Gl> = [Field.Gl{0,17},Field.Gl{0,1000020},Field.Gl{0,2000023},Field.Gl{0,3000026},Field.Gl{0,4000029},Field.Gl{0,5000032},Field.Gl{0,6000035},Field.Gl{0,7000038}]
      t: List<&2,Field.Gl> = [Field.Gl{4294967295,0},Field.Gl{4294967294,4294967291},Field.Gl{4294967294,4294967286}]
      show(z) ++ " / " ++ show(Code.symbol_f(z,m,t))

def small(pos: Nat) -> IO(Unit):
  IO.print(sample(Code.point(4n,pos)))

def show_e(v: Ext.E3) -> String:
  Ext.E3{ah,al,bh,bl,ch,cl} = v
  show(Field.Gl{ah,al}) ++ " " ++ show(Field.Gl{bh,bl}) ++ " " ++ show(Field.Gl{ch,cl})

# Pinned C++ blk::symbol_at(Code{32,2,1}, 0xffffffff, m, t), over the cubic extension.
def extension(value: Maybe<&2,Field.Gl>) -> String:
  match value:
    case None{}: "outside"
    case Some{z}:
      show_e(Code.symbol_e(z,[Ext.E3{0,1,0,2,0,3},Ext.E3{0,4,0,5,0,6}],[Ext.E3{0,7,0,8,0,9}]))

def main() -> IO(Unit):
  do IO<Unit>:
    List.for_each(&2,Nat,small,List.range(16n))
    IO.print(point(Code.point(15n,12345n)))
    IO.print(point(Code.point(15n,2n)))
    IO.print(point(Code.point(14n,9999n)))
    # Pinned blk::gl64_point and symbol_at with the same message and tail at the largest domain.
    IO.print(sample(Code.point(32n,2147483648n)))
    IO.print(sample(Code.point(32n,4294967295n)))
    IO.print(extension(Code.point(32n,4294967295n)))
    IO.print(position(Code.short_position(32n,4n,2147483653n)))
    IO.print(position(Code.short_position(32n,32n,4294967295n)))
    IO.print(position(Code.short_position(4n,0n,15n)))
    IO.print(point(Code.point(0n,0n)))
    IO.print(point(Code.point(33n,0n)))
    IO.print(point(Code.point(32n,Nat.add(4294967295n,1n))))
    IO.print(position(Code.short_position(4n,5n,0n)))
    IO.print(position(Code.short_position(4n,2n,16n)))

#|0 7 / 524327 564880998
#|4294967294 4294967290 / 410030 712609226
#|458752 0 / 1644270684 3993982837
#|4294508543 1 / 2649789099 2693552424
#|0 117440512 / 634556055 2087623472
#|4294967294 4177526785 / 2318192319 2824877806
#|1791 4294965504 / 3155341241 1452857908
#|4294965503 1793 / 2481871815 3866118620
#|0 28672 / 1522088743 96314625
#|4294967294 4294938625 / 4234853611 2082180022
#|1879048192 0 / 519958994 2309902036
#|2415919103 1 / 3778013616 1445590655
#|112 0 / 3990688911 2896300071
#|4294967183 1 / 3005825989 3723555542
#|7340031 4287627264 / 3611347720 2257310320
#|4287627263 7340033 / 812005198 1352081798
#|1082432863 3940621152
#|458752 0
#|2173477760 1981583255
#|852234941 1659038724 / 1290421118 3976189604
#|2801514728 1763443588 / 538666881 323381360
#|3703675910 3534379057 288279992 1445589214 1167851368 3651766668
#|5
#|4294967295
#|0
#|outside
#|outside
#|outside
#|outside
#|outside
