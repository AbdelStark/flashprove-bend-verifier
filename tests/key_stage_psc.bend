import Base
import ../src/key_stage_psc.bend as P
import ../src/oracle_sample.bend as S
import ../src/base_check.bend as B
import ../src/fold.bend as F
import ../src/extension.bend as E
import ../src/sumcheck.bend as A
import ../src/row_tensor.bend as X

def n(x: U32) -> E.E3: E.E3{0,x,0,0,0,0}
def same(a: E.E3,b: E.E3) -> Bool: B.equal(a,b)
def list(xs: B.Elements, ys: B.Elements) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case Con{x,t} Con{y,r}: same(x,y) && list(t,r)
    case _ _: False{}

def test(ob: P.Obligation) -> Bool:
  # Running: 5 + 3*17 = 56. Plain q=(4,42,6), q(2)=112.
  # Equality z=7 fixes q0=112 - 7*(3+5)=56, q(4)=148.
  # U's first variable has no constant; psi_plain(2)=2 and psi_eq(4)=1.
  P.Obligation{target,ms,carry,kept} = ob
  same(target,n(127)) && list(ms,[n(2),n(4),n(1),n(4),n(16)]) && same(carry,n(6)) && list(kept,[n(15)])

def psc2(s: Maybe<&2,P.Claim>) -> Bool:
  match s:
    case Some{x}:
      test(P.obligation(x,n(7),[n(5)]))
    case _: False{}

def psc(s: Maybe<&2,P.Claim>) -> Bool:
  match s:
    case Some{x}: psc2(P.bind(x,P.Variable{P.Equal{n(7)},2n},[n(3),n(5)],n(4)))
    case _: False{}

def weight(form: F.Form, +i: Nat, acc: E.E3) -> E.E3:
  match form:
    case []: acc
    case F.Term{v,fs} <> tail: weight(tail,i,A.add(acc,X.entry(fs,i,v)))

def sample(result: Maybe<&2,S.Sample>) -> Bool:
  match result:
    case Some{S.Sample{+main,+mask,y}}:
      # z=(2,3,5), shared top bit 5. Main has 4 places in one
      # row at group row 1; mask is split over two rows, pad at index 3.
      same(weight(main,1n,F.zero()),F.sub(F.zero(),n(8))) && same(weight(main,0n,F.zero()),F.zero()) &&
      same(weight(mask,0n,F.zero()),n(10)) && same(weight(mask,3n,F.zero()),n(11)) && same(y,n(19))
    case _: False{}

def basis(result: Maybe<&2,S.Sample>) -> Bool:
  match result:
    case Some{S.Sample{+main,_,_}}:
      same(weight(main,1n,F.zero()),n(11)) &&
      same(weight(main,2n,F.zero()),E.E3{0,0,0,11,0,0}) &&
      same(weight(main,3n,F.zero()),E.E3{0,0,0,0,0,11})
    case _: False{}

def main() -> IO(Unit):
  # Compare to direct polynomial evaluation above and to the three coefficients
  # of the field-2 basis in the format's SEND rule.
  +seed: S.Seed = S.Seed{[n(2),n(3),n(5)],n(11)}
  a = S.single(S.Member{S.Part{1n,4n,1n,1n},S.Part{2n,2n,1n,0n},True{}},seed,n(19))
  b = S.single(S.Member{S.Part{1n,4n,0n,0n},S.Part{0n,0n,0n,0n},True{}},seed,n(19))
  first = P.bind(P.begin(n(5),n(3),n(17)),P.Variable{P.Plain{},2n},[n(4),n(6)],n(2))
  IO.print(Bool.show(psc(first) && sample(a) && basis(b)))
#|True
