import Base
import ../src/header.bend as Header

def sample() -> List<&2, U32>:
  [1,0,0,0, 2,0,0,0, 0,0,0,0, 1,0,0,0]

def describe(s: Header.RequestStatus) -> String:
  match s:
    case Header.Valid{}: "valid"
    case Header.RangeError{}: "statement-range"
    case Header.TokenError{}: "token-range"

def main() -> IO(Unit):
  +req = sample()
  do IO<Unit>:
    index : U32 <- Header.leaf_index([67,80,80,70,72,56,50,49, 1,2,3,4])
    _ : Unit <- IO.print(U32.show(index))
    _ : Unit <- IO.print(describe(Header.request_status(req, 0, 2, 3, 0, True{})))
    _ : Unit <- IO.print(describe(Header.request_status(req, 0, 2, 2, 0, True{})))
    _ : Unit <- IO.print(describe(Header.request_status(req, 0, 2, 3, 1, True{})))
    _ : Unit <- IO.print(describe(Header.request_status(req, 0, 1, 3, 0, True{})))
    IO.print(describe(Header.request_status(List.append(&2, U32, req, [0]), 0, 2, 3, 0, True{})))

#|67305985
#|valid
#|token-range
#|statement-range
#|statement-range
#|statement-range
