import Base
import ../src/opening_bytes.bend as O
import ../src/opening.bend as Path
import ../src/merkle.bend as M
import ../src/hash_bytes.bend as H

# R7 and R14 vectors from the pinned docs/format/format-vectors.txt.
def pattern(count: Nat, +at: Nat, +a: Nat, +b: Nat) -> H.Bytes:
  match count:
    case 0n: []
    case 1n+p: U32.from_nat(Nat.mod(Nat.add(Nat.mul(at,a),b),251n)) <> pattern(p,Nat.add(at,1n),a,b)

def increasing(n: Nat, +at: U32) -> H.Bytes:
  match n:
    case 0n: []
    case 1n+p: H.cat([H.word(at),increasing(p,U32.add(at,1))])

def start() -> M.Digest:
  M.Digest{269157889,606018069,942878249,1279738429,1616598609,1953458789,2290318969,2627179149}

def config() -> M.Digest:
  M.Digest{2164831719,3142626686,1752119359,347161300,3901988369,2803117039,126878167,1608206419}

def root() -> M.Digest:
  M.Digest{1123753355,2929749762,3214280483,763333275,3097501950,3382159946,4252285765,714174201}

def show_digest(v: Maybe<&2,M.Digest>) -> String:
  match v:
    case Some{d}: H.hex(O.digest_bytes(d))
    case None{}: "invalid"

def leaf(+w: Nat) -> String:
  show_digest(O.leaf(O.Shape{164,5,3n,w,40n,start()},6n,increasing(w,1),pattern(40n,0n,3n,9n)))

def item(+x: U32) -> H.Bytes:
  H.cat([H.word(U32.add(100,x)),H.word(U32.add(200,x)),H.word(U32.add(300,U32.and(x,1))),pattern(40n,0n,3n,Nat.add(9n,U32.to_nat(x)))])

def shape() -> O.Shape:
  O.Shape{164,5,3n,3n,40n,start()}

def opening1() -> H.Bytes:
  H.cat([item(1),item(3),item(6),[127,111,211,65,145,91,16,165,229,56,217,68,107,255,150,77,23,142,28,45,63,226,139,115,111,35,49,118,135,221,98,28,134,233,216,179,139,53,11,140,101,80,154,236,244,13,82,122,80,7,96,233,240,73,77,52,126,46,136,91,179,221,180,165,17,155,17,164,178,212,45,202,208,114,27,160,101,106,189,250,211,154,198,80,102,157,108,8,21,117,205,118,120,212,140,81,32,91,249,193,227,93,168,203,113,117,21,67,129,32,143,220,138,212,91,94,93,222,8,51,64,217,53,19,77,105,25,156]])

def opening2() -> H.Bytes:
  H.cat([item(3),item(5),[134,233,216,179,139,53,11,140,101,80,154,236,244,13,82,122,80,7,96,233,240,73,77,52,126,46,136,91,179,221,180,165,8,134,13,236,220,94,189,249,112,233,135,252,152,230,93,166,6,118,203,199,109,194,1,130,174,197,234,236,6,21,8,174,58,181,105,44,179,227,61,40,39,246,185,77,186,246,77,65,209,124,162,229,188,12,163,86,177,233,221,238,93,18,38,170,77,106,82,252,172,0,25,79,116,72,15,140,117,167,106,40,233,85,29,76,127,37,201,142,33,36,130,69,252,116,244,164]])

def xs() -> O.Places:
  O.positions(3n,[6n,1n,6n,3n])

def encoded(v: Maybe<&2,Nat>) -> String:
  match v:
    case Some{n}: Nat.show(n)
    case None{}: "invalid"

def accepted(v: Maybe<&2,O.Opened>) -> String:
  match v:
    case Some{_}: "checked"
    case None{}: "invalid"

def next(v: Maybe<&2,O.Opened>) -> String:
  match v:
    case Some{O.Opened{_,session}}: accepted(O.verify(shape(),config(),root(),[3n,5n],opening2(),session))
    case None{}: "first opening failed"

def conflict() -> O.Session:
  +zero: M.Digest = M.Digest{0,0,0,0,0,0,0,0}
  record = Map.set(&2,Path.Value,Map.new(&2,Path.Value),"2/1",Some{zero})
  Map.set(&2,Path.Record,O.empty_session(),H.hex(O.digest_bytes(root())),record)

def binding(+slot: Nat) -> String:
  config: M.Digest = M.Digest{403769859,875374111,1346978363,1818582615,2290186867,2761791119,3233395371,3704999623}
  path: Path.Siblings = [M.Digest{588778754,1329871150,2070963546,2812055942,3553148338,83159518,807737871,1548830267},M.Digest{723390724,1599227192,2475063660,3350900128,15655380,874977805,1750814273,2626650741}]
  show_digest(O.binding_root(2n,slot,config,pattern(32n,0n,5n,1n),pattern(40n,0n,3n,9n),40n,path))

def main() -> IO(Unit):
  +bytes = opening1()
  +opened = O.verify(shape(),config(),root(),xs(),bytes,O.empty_session())
  do IO<Unit>:
    IO.print(binding(0n))
    IO.print(binding(1n))
    IO.print(binding(2n))
    IO.print(binding(3n))
    IO.print(binding(4n))
    IO.print(leaf(3n))
    IO.print(leaf(9n))
    IO.print(leaf(10n))
    IO.print(leaf(11n))
    IO.print(leaf(14n))
    IO.print(leaf(16n))
    IO.print(leaf(25n))
    IO.print(leaf(26n))
    IO.print(show_digest(O.leaf(O.Shape{174,0,3n,3n,40n,start()},6n,increasing(3n,1),pattern(40n,0n,3n,9n))))
    IO.print(show_digest(O.leaf(O.Shape{173,0,2n,4n,40n,start()},3n,pattern(32n,0n,7n,3n),pattern(40n,0n,3n,9n))))
    IO.print(H.hex(O.leaf_index(48n,Nat.add(Nat.mul(4294967295n,65536n),65535n))))
    IO.print(H.hex(H.plain(168,0,bytes)))
    IO.print(encoded(O.encoded_size(shape(),xs())))
    IO.print(encoded(O.encoded_size(shape(),[1n,1n])))
    IO.print(encoded(O.encoded_size(shape(),[8n])))
    IO.print(accepted(opened))
    IO.print(next(opened))
    IO.print(accepted(O.verify(shape(),config(),root(),xs(),bytes,conflict())))
    IO.print(accepted(O.verify(shape(),config(),root(),xs(),H.cat([bytes,[0]]),O.empty_session())))
    IO.print(accepted(O.verify(shape(),config(),root(),xs(),H.cat([H.zero(8n),List.drop(&2,U32,bytes,8n)]),O.empty_session())))
    IO.print(accepted(O.verify(shape(),config(),root(),xs(),H.cat([List.replicate(U32,8n,255),List.drop(&2,U32,bytes,8n)]),O.empty_session())))

#|11849a2d11ba514292eb743d1e64ec3db561ca1f9bcc827f4a42f6dc0d068f4e
#|dc8b600e35209b9d3d4cbe8d7703cb42866eebbf8fdf55069f5f16e6c929f88f
#|8867ccb5e2fdefae951fc542ca447b1eff22c42267ddb65eba7f07faced2c7a9
#|174a65e766c3f047d96c6cc49696f24b1dbdbb88e83063f5a007e31060ef2a0a
#|invalid
#|89599a66474b3e68f883f399255ec7b4d1c225bc7348803919c6f927af0bc5b1
#|7b1b85a527dfe724e22bb335a49faa2afe869afea2ce46df1eec65fb0bb7959b
#|a2a01d576f6706338289077464979d99bf0a39a1843a90f0a946b4cbefb802fd
#|752ecd9d24f770ccec747c2fa279896f14cfa420de9e66ad38d73d5ae69d1d39
#|1ef4886b1ccce41a2c5453d7e4e31851c3e5a0f99a9327a8153af0c2aea3ae23
#|e8572aca9c485ebe7be99e5e2ca5c4c44d1fc634cce9608d1dee6bd65124e7b7
#|079b3341eb5ae565717ce9ddc4fb799cb19b0be92b288381621afe0b98506a23
#|5f48eb1e7378694660beed0b819bceadedfccf653603e6e571869fb8ff437b22
#|32e9d1c553ae00721507db816c3885fda15a00ab4b538a8fd70185bbcde6ada1
#|0b573addb4922151823d80974c91e8697c33ff51bf4acf7de4ff96434c05ce86
#|ffffffffffff0100
#|4399892d97c5affcfccacb46f45b4daa1931aca115231a14b99fc878c6219ef5
#|320
#|invalid
#|invalid
#|checked
#|checked
#|invalid
#|invalid
#|invalid
#|invalid
