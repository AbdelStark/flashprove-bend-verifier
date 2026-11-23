import Base
import ./fold.bend as F
import ./sumcheck.bend as E
import ./extension.bend as X
import ./base_check.bend as B

# R13.16. X variables are either summed plainly or under an equality factor.
# PSC Y is an equality variable with z=0 and a nonzero challenge.
type Weight is Data:
  Plain{}
  Equal{z: X.E3}

type Variable is Data:
  Variable{weight: Weight, degree: Nat}

type Bound is Data:
  Bound{weight: Weight, degree: Nat, challenge: X.E3}

type Claim is Data:
  Claim{running: X.E3, epsilon: X.E3, reverse: List<&2,Bound>}

def begin(hiding: X.E3, +epsilon: X.E3, target: X.E3) -> Claim:
  Claim{E.add(hiding,E.mul(epsilon,target)),epsilon,[]}

def sum(xs: B.Elements, acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case h <> tail: sum(tail,E.add(acc,h))

def polynomial(backwards: B.Elements, +at: X.E3, acc: X.E3) -> X.E3:
  match backwards:
    case []: acc
    case h <> tail: polynomial(tail,at,E.horner(acc,at,h))

def complete(weight: Weight, running: X.E3, sent: B.Elements) -> Maybe<&2,B.Elements>:
  match weight sent:
    case _ Nil{}: None{}
    case Plain{} Con{+c,+tail}:
      linear = F.sub(F.sub(running,E.add(c,c)),sum(tail,F.zero()))
      Some{c <> linear <> tail}
    case Equal{z} +coeff:
      Some{F.sub(running,E.mul(z,sum(coeff,F.zero()))) <> coeff}

def bound(polynomial_: Maybe<&2,B.Elements>, variable: Variable, +challenge: X.E3, eps: X.E3,
  reverse: List<&2,Bound>) -> Maybe<&2,Claim>:
  match polynomial_ variable:
    case None{} _: None{}
    case Some{+coeffs} Variable{weight,+degree}:
      next = polynomial(List.reverse(&2,X.E3,coeffs),challenge,F.zero())
      new: Claim = Claim{next,eps,Bound{weight,degree,challenge} <> reverse}
      Bool.pick(Maybe<&2,Claim>,Nat.is_eq(List.length(&2,X.E3,coeffs),1n+degree),Some{new},None{})

def bind(claim: Claim, +var: Variable, coeff: B.Elements, at: X.E3) -> Maybe<&2,Claim>:
  Claim{running,eps,rev} = claim
  Variable{weight,_} = var
  bound(complete(weight,running,coeff),var,at,eps,rev)

# Coefficient masks are allocated from the first variable to the last in
# ascending power order. Only the last variable owns its constant coefficient.
def powers(n: Nat, +gamma: X.E3, +at: X.E3) -> B.Elements:
  match n:
    case 0n: []
    case 1n+k: at <> powers(k,gamma,E.mul(at,gamma))

def psi(weight: Weight, at: X.E3) -> X.E3:
  match weight:
    case Plain{}: at
    case Equal{_}: F.one()

type Form is Data:
  Form{coeffs: B.Elements, inherited: X.E3}

def form(reverse: List<&2,Bound>, +last: Bool, +tail_factor: X.E3, acc: B.Elements) -> Form:
  match reverse:
    case []: Form{acc,tail_factor}
    case Bound{w,+degree,+gamma} <> rest:
      start = Bool.pick(X.E3,last,tail_factor,E.mul(tail_factor,gamma))
      terms = powers(Bool.pick(Nat,last,1n+degree,degree),gamma,start)
      form(rest,False{},E.mul(tail_factor,psi(w,gamma)),List.append(&2,X.E3,terms,acc))

type Obligation is Data:
  Obligation{target: X.E3, fresh: B.Elements, carried: X.E3, kept: B.Elements}

def with_form(coefficients: Form, target: X.E3, +eps: X.E3, kept: B.Elements) -> Obligation:
  Form{fresh,factor} = coefficients
  Obligation{target,fresh,E.mul(eps,factor),F.scaled(kept,eps)}

def obligation(claim: Claim, constant: X.E3, kept: B.Elements) -> Obligation:
  Claim{running,+eps,rev} = claim
  with_form(form(rev,True{},F.one(),[]),F.sub(running,E.mul(eps,constant)),eps,kept)
