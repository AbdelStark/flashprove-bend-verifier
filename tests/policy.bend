import Base
import ../src/policy.bend as P

def main() -> IO(Unit):
  +exact : P.Claim = P.Claim{256,256,0,16,8,4,24}
  +clip : P.Claim = P.Claim{9244130,323343,1,16,8,4,24}
  +name : Maybe<&2, String> = Some{"clipped-gap,9244130,323343,1,16,8"}
  do IO<Unit>:
    _ : Unit <- IO.print(Bool.show(P.held(exact, None{}, 64, 3)))
    _ : Unit <- IO.print(Bool.show(P.held(clip, name, 64, 3)))
    _ : Unit <- IO.print(Bool.show(P.held(clip, None{}, 64, 3)))
    _ : Unit <- IO.print(Bool.show(P.held(clip, None{}, 64, 0)))
    _ : Unit <- IO.print(Bool.show(P.held(P.Claim{300,300,3,16,8,4,24}, Some{"clipped-gap,300,300,3,16,8"}, 64, 3)))
    _ : Unit <- IO.print(Bool.show(P.held(P.Claim{300,300,3,16,8,4,24}, Some{"clipped-gap,300,300,3,16,8"}, 64, 4)))
    _ : Unit <- IO.print(Bool.show(P.held(P.Claim{256,256,0,16,8,16,24}, None{}, 64, 0)))
    _ : Unit <- IO.print(Bool.show(P.option_valid("clipped-gap,9244130,323343,1,16,8")))
    IO.print(Bool.show(P.option_valid("clipped-gap,9244130,323343,01,16,8")))

#|True
#|True
#|False
#|True
#|False
#|True
#|False
#|True
#|False
