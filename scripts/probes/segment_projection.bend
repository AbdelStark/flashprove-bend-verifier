import Base
import ../../src/base_check.bend as B
import ../../src/key_stage_lookup_rows.bend as L
import ../../src/key_stage_lookup.bend as KL
import ../../src/segment_forest.bend as S
import ../../src/segment_stage.bend as G
import ../../src/fold.bend as F
import ../../src/sumcheck.bend as E
import ../../src/extension.bend as X
import ../../src/hash_bytes.bend as H

# Test-only projection of all mask-only rows using the synthetic point
# mask[j]=j+1. Results are compared to a read-only oracle snapshot.
def dot(xs: L.Masks, a: X.E3) -> X.E3:
  match xs:
    case []: a
    case L.Mask{_,i,w} <> rest: dot(rest,E.add(a,E.mul(KL.small(1n+i),w)))

def step(acc: X.E3, x: X.E3) -> X.E3:
  E.add(E.mul(acc,KL.small(257n)),x)

def values(xs: B.Elements, a: X.E3) -> X.E3:
  match xs:
    case []: a
    case v <> rest: values(rest,step(a,v))

def project(rows: List<&2,L.Row>, acc: X.E3) -> X.E3:
  match rows:
    case L.Row{[],m,t} <> rest: project(rest,step(step(acc,t),dot(m,F.zero())))
    case L.Row{[L.Plane{_,F.Term{w,_}}],_,_} <> _: step(acc,w)
    case _: acc

def print(x: X.E3) -> String:
  X.E3{a,b,c,d,e,f} = x
  H.hex(H.cat([H.le(b),H.le(a),H.le(d),H.le(c),H.le(f),H.le(e)]))

def groups(xs: G.Groups) -> IO(Unit):
  match xs:
    case []: IO.pure(Unit,Unit{})
    case S.Claims{L.Point{coords,_,_},_,_,rows} <> tail:
      do IO<Unit>:
        ok : Unit <- IO.print("forest " ++ print(values(coords,project(rows,F.zero()))))
        groups(tail)
