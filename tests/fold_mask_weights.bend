import Base
import ../src/base_check.bend as B
import ../src/extension.bend as X
import ../src/fold.bend as F
import ../src/fold_cs.bend as CS
import ../src/leaf_shape.bend as S

def e(c: U32,x: U32,xx: U32) -> X.E3: X.E3{0,c,0,x,0,xx}

def equal(a: B.Elements,b: B.Elements) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x,xs} Con{y,ys}: B.equal(x,y) && equal(xs,ys)
    case _ _: False{}

def check_mask(claim: Maybe<&2,F.Claim>, expected: B.Elements) -> Bool:
  match claim:
    case Some{F.Claim{_,mask,_}}: equal(mask,expected)
    case None{}: False{}

# R7 generator rows, with both openings at index zero (evaluation point 7).
# At theta=X in X³=2 the two draws contribute p=X²,2X² and q=2,4.
# Thus main-tail entry j adds 3X²*7^j, and the old/fresh mask entries add
# 6*7^j and 6X*7^j. The all-zero sampling point leaves only the final pad X.
def check(+r: Nat,+s: Nat,draws: CS.Draws, +theta: X.E3, head: B.Elements) -> Bool:
  from: S.Stage = S.Stage{B.Code{5n,4n,r},B.Code{4n,2n,s},2,1}
  to: S.Stage = S.Stage{B.Code{4n,2n,1n},B.Code{4n,8n,1n},1,1}
  row: F.Single = F.Single{[],[e(7,0,0),e(11,0,0)],[e(13,0,0),e(17,0,0)],F.zero()}
  seed: CS.Seed = CS.Seed{CS.zeros(5n),F.one()}
  +prefix = head
  pad = F.fill(Nat.sub(15n,F.count(X.E3,prefix,0n)),F.zero(),[theta])
  check_mask(CS.switch(from,to,row,theta,draws,seed,F.zero()),F.cat(X.E3,prefix,pad))

def main() -> IO(Unit):
  +x = e(0,1,0)
  +d: CS.Draw = CS.Draw{0n,F.one(),F.one(),F.one()}
  full = check(2n,1n,[d,d],x,[e(49,0,0),e(305,0,0),e(13,42,0),e(17,294,0),
    e(0,0,3),e(0,0,21),e(6,0,0),e(0,6,0)])
  empty_tails = check(0n,0n,[d,d],x,[e(13,0,0),e(53,0,0),e(13,6,0),e(17,42,0)])
  +old: B.Elements = [e(7,0,0),e(11,0,0),e(13,0,0),e(17,0,0)]
  IO.print(Bool.show(full && empty_tails && check(0n,0n,[],x,old) && check(0n,0n,[d],F.zero(),old)))

#|True
