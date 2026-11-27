# Lemmas behind LAWS.bend: n-bit adders and subtractors on Base's bit-list words, and the
# little natural-number algebra they need. Base has no arithmetic library, so it is built here.
import Base
import ../src/goldilocks.bend as Gl
import ../LAWS.bend as Laws

law add_zero_r:
  for +x: Nat
  {Nat.add(x, 0n) == x : Nat}

def add_zero_r(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, z => 1n+z, Nat.add(p, 0n), p, add_zero_r(p))

law add_succ_r:
  for +x: Nat
  for +y: Nat
  {Nat.add(x, 1n+y) == 1n+Nat.add(x, y) : Nat}

def add_succ_r(x, y):
  match x:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, z => 1n+z, Nat.add(p, 1n+y), 1n+Nat.add(p, y), add_succ_r(p, y))

law double_add:
  for +x: Nat
  for +y: Nat
  {Nat.double(Nat.add(x, y)) == Nat.add(Nat.double(x), Nat.double(y)) : Nat}

def double_add(x, y):
  match x:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, z => 2n+z, Nat.double(Nat.add(p, y)), Nat.add(Nat.double(p), Nat.double(y)), double_add(p, y))
# The carry of one full adder: true when at least two of the three bits are.
def maj(a: Bool, b: Bool, c: Bool) -> Bool:
  match a:
    case False{}:
      Bool.and(b, c)
    case True{}:
      Bool.or(b, c)

# The carry out of an n-bit addition with carry in c, bit by bit from the lowest.
def cout(n: Nat, a: Word(n), b: Word(n), c: Bool) -> Bool:
  match n:
    case 0n:
      c
    case 1n+p:
      match a b:
        case WCon{ab, at} WCon{bb, bt}:
          cout(p, at, bt, maj(ab, bb, c))

def bit(b: Bool) -> Nat:
  match b:
    case False{}:
      0n
    case True{}:
      1n

def bitv(b: Bool, z: Nat) -> Nat:
  match b:
    case False{}:
      z
    case True{}:
      1n+z

def scale(b: Bool, m: Nat) -> Nat:
  match b:
    case False{}:
      0n
    case True{}:
      m

def sum3(a: Bool, +b: Bool, +c: Bool) -> Bool:
  Bool.xor(a, Bool.xor(b, c))

law scale_double:
  for +c: Bool
  for +m: Nat
  {scale(c, Nat.double(m)) == Nat.double(scale(c, m)) : Nat}

def scale_double(c, m):
  match c:
    case False{}:
      {==}
    case True{}:
      {==}

# One bit position of the adder, after the induction hypothesis on the higher bits.
law shift:
  for +s: Nat
  for +co: Bool
  for +q: Nat
  for +x: Nat
  for +y: Nat
  for +k: Bool
  for ih: {Nat.add(s, scale(co, q)) == Nat.add(Nat.add(x, y), bit(k)) : Nat}
  {Nat.add(Nat.double(s), scale(co, Nat.double(q)))
    == Nat.add(Nat.add(Nat.double(x), Nat.double(y)), Nat.double(bit(k))) : Nat}

def shift(s, co, q, x, y, k, ih):
  +ds = Nat.double(s)
  Equal.trans(Nat, Nat.add(ds, scale(co, Nat.double(q))), Nat.add(ds, Nat.double(scale(co, q))),
    Nat.add(Nat.add(Nat.double(x), Nat.double(y)), Nat.double(bit(k))),
    Equal.cong(Nat, Nat, z => Nat.add(ds, z), scale(co, Nat.double(q)), Nat.double(scale(co, q)), scale_double(co, q)),
  Equal.trans(Nat, Nat.add(ds, Nat.double(scale(co, q))), Nat.double(Nat.add(s, scale(co, q))),
    Nat.add(Nat.add(Nat.double(x), Nat.double(y)), Nat.double(bit(k))),
    Equal.sym(Nat, Nat.double(Nat.add(s, scale(co, q))), Nat.add(ds, Nat.double(scale(co, q))), double_add(s, scale(co, q))),
  Equal.trans(Nat, Nat.double(Nat.add(s, scale(co, q))), Nat.double(Nat.add(Nat.add(x, y), bit(k))),
    Nat.add(Nat.add(Nat.double(x), Nat.double(y)), Nat.double(bit(k))),
    Equal.cong(Nat, Nat, z => Nat.double(z), Nat.add(s, scale(co, q)), Nat.add(Nat.add(x, y), bit(k)), ih),
  Equal.trans(Nat, Nat.double(Nat.add(Nat.add(x, y), bit(k))), Nat.add(Nat.double(Nat.add(x, y)), Nat.double(bit(k))),
    Nat.add(Nat.add(Nat.double(x), Nat.double(y)), Nat.double(bit(k))),
    double_add(Nat.add(x, y), bit(k)),
    Equal.cong(Nat, Nat, z => Nat.add(z, Nat.double(bit(k))), Nat.double(Nat.add(x, y)),
      Nat.add(Nat.double(x), Nat.double(y)), double_add(x, y))))))

# The full-adder table on naturals: the sum bit plus twice the carry is a + b + c.
law adder:
  for +x: Nat
  for +y: Nat
  for ab: Bool
  for bb: Bool
  for c: Bool
  {bitv(sum3(ab, bb, c), Nat.add(Nat.add(x, y), Nat.double(bit(maj(ab, bb, c)))))
    == Nat.add(Nat.add(bitv(ab, x), bitv(bb, y)), bit(c)) : Nat}

def adder(x, y, ab, bb, c):
  match ab bb c:
    case False{} False{} False{}:
      {==}
    case False{} False{} True{}:
      Equal.sym(Nat, Nat.add(Nat.add(x, y), 1n), 1n+Nat.add(Nat.add(x, y), 0n), add_succ_r(Nat.add(x, y), 0n))
    case False{} True{} False{}:
      Equal.sym(Nat, Nat.add(Nat.add(x, 1n+y), 0n), Nat.add(1n+Nat.add(x, y), 0n),
        Equal.cong(Nat, Nat, z => Nat.add(z, 0n), Nat.add(x, 1n+y), 1n+Nat.add(x, y), add_succ_r(x, y)))
    case False{} True{} True{}:
      Equal.trans(Nat, Nat.add(Nat.add(x, y), 2n), 1n+Nat.add(Nat.add(x, y), 1n), Nat.add(Nat.add(x, 1n+y), 1n),
        add_succ_r(Nat.add(x, y), 1n),
        Equal.sym(Nat, Nat.add(Nat.add(x, 1n+y), 1n), Nat.add(1n+Nat.add(x, y), 1n),
          Equal.cong(Nat, Nat, z => Nat.add(z, 1n), Nat.add(x, 1n+y), 1n+Nat.add(x, y), add_succ_r(x, y))))
    case True{} False{} False{}:
      {==}
    case True{} False{} True{}:
      add_succ_r(Nat.add(x, y), 1n)
    case True{} True{} False{}:
      Equal.trans(Nat, Nat.add(Nat.add(x, y), 2n), 2n+Nat.add(Nat.add(x, y), 0n), Nat.add(Nat.add(1n+x, 1n+y), 0n),
        Equal.trans(Nat, Nat.add(Nat.add(x, y), 2n), 1n+Nat.add(Nat.add(x, y), 1n), 2n+Nat.add(Nat.add(x, y), 0n),
          add_succ_r(Nat.add(x, y), 1n),
          Equal.cong(Nat, Nat, z => 1n+z, Nat.add(Nat.add(x, y), 1n), 1n+Nat.add(Nat.add(x, y), 0n), add_succ_r(Nat.add(x, y), 0n))),
        Equal.sym(Nat, 1n+Nat.add(Nat.add(x, 1n+y), 0n), 2n+Nat.add(Nat.add(x, y), 0n),
          Equal.cong(Nat, Nat, z => 1n+Nat.add(z, 0n), Nat.add(x, 1n+y), 1n+Nat.add(x, y), add_succ_r(x, y))))
    case True{} True{} True{}:
      Equal.cong(Nat, Nat, z => 1n+z, Nat.add(Nat.add(x, y), 2n), Nat.add(Nat.add(x, 1n+y), 1n),
        Equal.trans(Nat, Nat.add(Nat.add(x, y), 2n), 1n+Nat.add(Nat.add(x, y), 1n), Nat.add(Nat.add(x, 1n+y), 1n),
          add_succ_r(Nat.add(x, y), 1n),
          Equal.sym(Nat, Nat.add(Nat.add(x, 1n+y), 1n), Nat.add(1n+Nat.add(x, y), 1n),
            Equal.cong(Nat, Nat, z => Nat.add(z, 1n), Nat.add(x, 1n+y), 1n+Nat.add(x, y), add_succ_r(x, y)))))

# The n-bit adder computes a + b + c exactly: the sum word plus its carry out times 2^n.
law value:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +c: Bool
  {Nat.add(Word.to_nat(n, Word.adc(n, a, b, False{}, c)), scale(cout(n, a, b, c), Laws.pow2(n)))
    == Nat.add(Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)), bit(c)) : Nat}

def value(n, a, b, c):
  match n:
    case 0n:
      match a b c:
        case WNil{} WNil{} False{}:
          {==}
        case WNil{} WNil{} True{}:
          {==}
    case 1n+p:
      match a b c:
        case WCon{False{}, at} WCon{False{}, bt} False{}:
          Equal.trans(Nat, Nat.add(Word.to_nat(1n+p, WCon{False{}, Word.adc(p, at, bt, False{}, False{})}), scale(cout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))), bitv(False{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(False{})))), Nat.add(Nat.add(Word.to_nat(1n+p, WCon{False{}, at}), Word.to_nat(1n+p, WCon{False{}, bt})), bit(False{})),
            Equal.cong(Nat, Nat, z => bitv(False{}, z),
              Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, False{}, False{}))), scale(cout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(False{}))),
              shift(Word.to_nat(p, Word.adc(p, at, bt, False{}, False{})), cout(p, at, bt, False{}), Laws.pow2(p), Word.to_nat(p, at), Word.to_nat(p, bt), False{}, value(p, at, bt, False{}))),
            adder(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt)), False{}, False{}, False{}))
        case WCon{False{}, at} WCon{False{}, bt} True{}:
          Equal.trans(Nat, Nat.add(Word.to_nat(1n+p, WCon{True{}, Word.adc(p, at, bt, False{}, False{})}), scale(cout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))), bitv(True{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(False{})))), Nat.add(Nat.add(Word.to_nat(1n+p, WCon{False{}, at}), Word.to_nat(1n+p, WCon{False{}, bt})), bit(True{})),
            Equal.cong(Nat, Nat, z => bitv(True{}, z),
              Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, False{}, False{}))), scale(cout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(False{}))),
              shift(Word.to_nat(p, Word.adc(p, at, bt, False{}, False{})), cout(p, at, bt, False{}), Laws.pow2(p), Word.to_nat(p, at), Word.to_nat(p, bt), False{}, value(p, at, bt, False{}))),
            adder(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt)), False{}, False{}, True{}))
        case WCon{False{}, at} WCon{True{}, bt} False{}:
          Equal.trans(Nat, Nat.add(Word.to_nat(1n+p, WCon{True{}, Word.adc(p, at, bt, False{}, False{})}), scale(cout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))), bitv(True{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(False{})))), Nat.add(Nat.add(Word.to_nat(1n+p, WCon{False{}, at}), Word.to_nat(1n+p, WCon{True{}, bt})), bit(False{})),
            Equal.cong(Nat, Nat, z => bitv(True{}, z),
              Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, False{}, False{}))), scale(cout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(False{}))),
              shift(Word.to_nat(p, Word.adc(p, at, bt, False{}, False{})), cout(p, at, bt, False{}), Laws.pow2(p), Word.to_nat(p, at), Word.to_nat(p, bt), False{}, value(p, at, bt, False{}))),
            adder(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt)), False{}, True{}, False{}))
        case WCon{False{}, at} WCon{True{}, bt} True{}:
          Equal.trans(Nat, Nat.add(Word.to_nat(1n+p, WCon{False{}, Word.adc(p, at, bt, False{}, True{})}), scale(cout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))), bitv(False{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(True{})))), Nat.add(Nat.add(Word.to_nat(1n+p, WCon{False{}, at}), Word.to_nat(1n+p, WCon{True{}, bt})), bit(True{})),
            Equal.cong(Nat, Nat, z => bitv(False{}, z),
              Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, False{}, True{}))), scale(cout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(True{}))),
              shift(Word.to_nat(p, Word.adc(p, at, bt, False{}, True{})), cout(p, at, bt, True{}), Laws.pow2(p), Word.to_nat(p, at), Word.to_nat(p, bt), True{}, value(p, at, bt, True{}))),
            adder(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt)), False{}, True{}, True{}))
        case WCon{True{}, at} WCon{False{}, bt} False{}:
          Equal.trans(Nat, Nat.add(Word.to_nat(1n+p, WCon{True{}, Word.adc(p, at, bt, False{}, False{})}), scale(cout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))), bitv(True{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(False{})))), Nat.add(Nat.add(Word.to_nat(1n+p, WCon{True{}, at}), Word.to_nat(1n+p, WCon{False{}, bt})), bit(False{})),
            Equal.cong(Nat, Nat, z => bitv(True{}, z),
              Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, False{}, False{}))), scale(cout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(False{}))),
              shift(Word.to_nat(p, Word.adc(p, at, bt, False{}, False{})), cout(p, at, bt, False{}), Laws.pow2(p), Word.to_nat(p, at), Word.to_nat(p, bt), False{}, value(p, at, bt, False{}))),
            adder(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt)), True{}, False{}, False{}))
        case WCon{True{}, at} WCon{False{}, bt} True{}:
          Equal.trans(Nat, Nat.add(Word.to_nat(1n+p, WCon{False{}, Word.adc(p, at, bt, False{}, True{})}), scale(cout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))), bitv(False{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(True{})))), Nat.add(Nat.add(Word.to_nat(1n+p, WCon{True{}, at}), Word.to_nat(1n+p, WCon{False{}, bt})), bit(True{})),
            Equal.cong(Nat, Nat, z => bitv(False{}, z),
              Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, False{}, True{}))), scale(cout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(True{}))),
              shift(Word.to_nat(p, Word.adc(p, at, bt, False{}, True{})), cout(p, at, bt, True{}), Laws.pow2(p), Word.to_nat(p, at), Word.to_nat(p, bt), True{}, value(p, at, bt, True{}))),
            adder(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt)), True{}, False{}, True{}))
        case WCon{True{}, at} WCon{True{}, bt} False{}:
          Equal.trans(Nat, Nat.add(Word.to_nat(1n+p, WCon{False{}, Word.adc(p, at, bt, False{}, True{})}), scale(cout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))), bitv(False{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(True{})))), Nat.add(Nat.add(Word.to_nat(1n+p, WCon{True{}, at}), Word.to_nat(1n+p, WCon{True{}, bt})), bit(False{})),
            Equal.cong(Nat, Nat, z => bitv(False{}, z),
              Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, False{}, True{}))), scale(cout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(True{}))),
              shift(Word.to_nat(p, Word.adc(p, at, bt, False{}, True{})), cout(p, at, bt, True{}), Laws.pow2(p), Word.to_nat(p, at), Word.to_nat(p, bt), True{}, value(p, at, bt, True{}))),
            adder(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt)), True{}, True{}, False{}))
        case WCon{True{}, at} WCon{True{}, bt} True{}:
          Equal.trans(Nat, Nat.add(Word.to_nat(1n+p, WCon{True{}, Word.adc(p, at, bt, False{}, True{})}), scale(cout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))), bitv(True{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(True{})))), Nat.add(Nat.add(Word.to_nat(1n+p, WCon{True{}, at}), Word.to_nat(1n+p, WCon{True{}, bt})), bit(True{})),
            Equal.cong(Nat, Nat, z => bitv(True{}, z),
              Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, False{}, True{}))), scale(cout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(True{}))),
              shift(Word.to_nat(p, Word.adc(p, at, bt, False{}, True{})), cout(p, at, bt, True{}), Laws.pow2(p), Word.to_nat(p, at), Word.to_nat(p, bt), True{}, value(p, at, bt, True{}))),
            adder(Nat.double(Word.to_nat(p, at)), Nat.double(Word.to_nat(p, bt)), True{}, True{}, True{}))
# The comparison a carry test makes: s below a, or equal to a with a carry in.
def below(c: Bool, +x: Cmp) -> Bool:
  Bool.or(Cmp.is_lt(x), Bool.and(c, Cmp.is_eq(x)))

# One more low bit under a comparison of the higher bits.
law fin:
  for x: Cmp
  for s: Bool
  for a: Bool
  for c: Bool
  {below(c, Word.cmp.fin(s, a, x)) == below(below(c, Bool.cmp(s, a)), x) : Bool}

def fin(x, s, a, c):
  match x s a c:
    case LT{} _ _ _:
      {==}
    case EQ{} False{} False{} False{}:
      {==}
    case EQ{} False{} False{} True{}:
      {==}
    case EQ{} False{} True{} False{}:
      {==}
    case EQ{} False{} True{} True{}:
      {==}
    case EQ{} True{} False{} False{}:
      {==}
    case EQ{} True{} False{} True{}:
      {==}
    case EQ{} True{} True{} False{}:
      {==}
    case EQ{} True{} True{} True{}:
      {==}
    case GT{} False{} False{} False{}:
      {==}
    case GT{} False{} False{} True{}:
      {==}
    case GT{} False{} True{} False{}:
      {==}
    case GT{} False{} True{} True{}:
      {==}
    case GT{} True{} False{} False{}:
      {==}
    case GT{} True{} False{} True{}:
      {==}
    case GT{} True{} True{} False{}:
      {==}
    case GT{} True{} True{} True{}:
      {==}

# The carry out of a + b + c is exactly the comparison: a + b + c (mod 2^n) is below a,
# or equals a with a carry in.
law carry_below:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +c: Bool
  {cout(n, a, b, c) == below(c, Word.cmp(n, Word.adc(n, a, b, False{}, c), a)) : Bool}

def carry_below(n, a, b, c):
  match n:
    case 0n:
      match a b c:
        case WNil{} WNil{} False{}:
          {==}
        case WNil{} WNil{} True{}:
          {==}
    case 1n+p:
      match a b c:
        case WCon{False{}, at} WCon{False{}, bt} False{}:
          Equal.trans(Bool, cout(p, at, bt, False{}), below(False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at)),
            below(False{}, Word.cmp.fin(False{}, False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at))),
            carry_below(p, at, bt, False{}),
            Equal.sym(Bool, below(False{}, Word.cmp.fin(False{}, False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at))), below(False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at)),
              fin(Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at), False{}, False{}, False{})))
        case WCon{False{}, at} WCon{False{}, bt} True{}:
          Equal.trans(Bool, cout(p, at, bt, False{}), below(False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at)),
            below(True{}, Word.cmp.fin(True{}, False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at))),
            carry_below(p, at, bt, False{}),
            Equal.sym(Bool, below(True{}, Word.cmp.fin(True{}, False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at))), below(False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at)),
              fin(Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at), True{}, False{}, True{})))
        case WCon{False{}, at} WCon{True{}, bt} False{}:
          Equal.trans(Bool, cout(p, at, bt, False{}), below(False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at)),
            below(False{}, Word.cmp.fin(True{}, False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at))),
            carry_below(p, at, bt, False{}),
            Equal.sym(Bool, below(False{}, Word.cmp.fin(True{}, False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at))), below(False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at)),
              fin(Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at), True{}, False{}, False{})))
        case WCon{False{}, at} WCon{True{}, bt} True{}:
          Equal.trans(Bool, cout(p, at, bt, True{}), below(True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at)),
            below(True{}, Word.cmp.fin(False{}, False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at))),
            carry_below(p, at, bt, True{}),
            Equal.sym(Bool, below(True{}, Word.cmp.fin(False{}, False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at))), below(True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at)),
              fin(Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at), False{}, False{}, True{})))
        case WCon{True{}, at} WCon{False{}, bt} False{}:
          Equal.trans(Bool, cout(p, at, bt, False{}), below(False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at)),
            below(False{}, Word.cmp.fin(True{}, True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at))),
            carry_below(p, at, bt, False{}),
            Equal.sym(Bool, below(False{}, Word.cmp.fin(True{}, True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at))), below(False{}, Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at)),
              fin(Word.cmp(p, Word.adc(p, at, bt, False{}, False{}), at), True{}, True{}, False{})))
        case WCon{True{}, at} WCon{False{}, bt} True{}:
          Equal.trans(Bool, cout(p, at, bt, True{}), below(True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at)),
            below(True{}, Word.cmp.fin(False{}, True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at))),
            carry_below(p, at, bt, True{}),
            Equal.sym(Bool, below(True{}, Word.cmp.fin(False{}, True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at))), below(True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at)),
              fin(Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at), False{}, True{}, True{})))
        case WCon{True{}, at} WCon{True{}, bt} False{}:
          Equal.trans(Bool, cout(p, at, bt, True{}), below(True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at)),
            below(False{}, Word.cmp.fin(False{}, True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at))),
            carry_below(p, at, bt, True{}),
            Equal.sym(Bool, below(False{}, Word.cmp.fin(False{}, True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at))), below(True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at)),
              fin(Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at), False{}, True{}, False{})))
        case WCon{True{}, at} WCon{True{}, bt} True{}:
          Equal.trans(Bool, cout(p, at, bt, True{}), below(True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at)),
            below(True{}, Word.cmp.fin(True{}, True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at))),
            carry_below(p, at, bt, True{}),
            Equal.sym(Bool, below(True{}, Word.cmp.fin(True{}, True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at))), below(True{}, Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at)),
              fin(Word.cmp(p, Word.adc(p, at, bt, False{}, True{}), at), True{}, True{}, True{})))
law or_false:
  for b: Bool
  {Bool.or(b, False{}) == b : Bool}

def or_false(b):
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

def bits(a: U32) -> Word(32n):
  match a:
    case U32{x}:
      x

# Gl.carry(a, a + b) is 1 exactly when the 32-bit addition overflows.
law carry_flag:
  for +a: U32
  for +b: U32
  {Gl.carry(a, U32.add(a, b)) == Bool.to_u32(cout(32n, bits(a), bits(b), False{})) : U32}

def carry_flag(a, b):
  match a b:
    case U32{x} U32{y}:
      Equal.cong(Bool, U32, f => Bool.to_u32(f),
        Cmp.is_lt(Word.cmp(32n, Word.adc(32n, x, y, False{}, False{}), x)),
        cout(32n, x, y, False{}),
        Equal.sym(Bool, cout(32n, x, y, False{}), Cmp.is_lt(Word.cmp(32n, Word.adc(32n, x, y, False{}, False{}), x)),
          Equal.trans(Bool, cout(32n, x, y, False{}), below(False{}, Word.cmp(32n, Word.adc(32n, x, y, False{}, False{}), x)),
            Cmp.is_lt(Word.cmp(32n, Word.adc(32n, x, y, False{}, False{}), x)),
            carry_below(32n, x, y, False{}),
            or_false(Cmp.is_lt(Word.cmp(32n, Word.adc(32n, x, y, False{}, False{}), x))))))

law flag_scale:
  for +co: Bool
  for +m: Nat
  {Nat.mul(U32.to_nat(Bool.to_u32(co)), m) == scale(co, m) : Nat}

def flag_scale(co, m):
  match co:
    case False{}:
      {==}
    case True{}:
      add_zero_r(m)

law same_cout:
  for +x: Word(32n)
  for +y: Word(32n)
  {cout(32n, bits(U32{x}), bits(U32{y}), False{}) == cout(32n, x, y, False{}) : Bool}

def same_cout(x, y):
  {==}

law same_sum:
  for +x: Word(32n)
  for +y: Word(32n)
  {U32.to_nat(U32.add(U32{x}, U32{y})) == Word.to_nat(32n, Word.adc(32n, x, y, False{}, False{})) : Nat}

def same_sum(x, y):
  {==}

law same_args:
  for +x: Word(32n)
  for +y: Word(32n)
  {Nat.add(Word.to_nat(32n, x), Word.to_nat(32n, y)) == Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})) : Nat}

def same_args(x, y):
  {==}

# REQ-ASSURE-5, limb law 1: a 32-bit sum and Gl.carry together give a + b exactly.
law carry_exact:
  for +a: U32
  for +b: U32
  {Nat.add(U32.to_nat(U32.add(a, b)), Nat.mul(U32.to_nat(Gl.carry(a, U32.add(a, b))), Laws.pow2(32n)))
    == Nat.add(U32.to_nat(a), U32.to_nat(b)) : Nat}

def carry_exact(a, b):
  match a b:
    case U32{x} U32{y}:
      Equal.trans(Nat, Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), Nat.mul(U32.to_nat(Gl.carry(U32{x}, U32.add(U32{x}, U32{y}))), Laws.pow2(32n))), Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), Nat.mul(U32.to_nat(Bool.to_u32(cout(32n, bits(U32{x}), bits(U32{y}), False{}))), Laws.pow2(32n))), Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})),
        Equal.cong(U32, Nat, f => Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), Nat.mul(U32.to_nat(f), Laws.pow2(32n))), Gl.carry(U32{x}, U32.add(U32{x}, U32{y})), Bool.to_u32(cout(32n, bits(U32{x}), bits(U32{y}), False{})), carry_flag(U32{x}, U32{y})),
        Equal.trans(Nat, Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), Nat.mul(U32.to_nat(Bool.to_u32(cout(32n, bits(U32{x}), bits(U32{y}), False{}))), Laws.pow2(32n))), Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), scale(cout(32n, bits(U32{x}), bits(U32{y}), False{}), Laws.pow2(32n))), Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})),
        Equal.cong(Nat, Nat, z => Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), z), Nat.mul(U32.to_nat(Bool.to_u32(cout(32n, bits(U32{x}), bits(U32{y}), False{}))), Laws.pow2(32n)), scale(cout(32n, bits(U32{x}), bits(U32{y}), False{}), Laws.pow2(32n)), flag_scale(cout(32n, bits(U32{x}), bits(U32{y}), False{}), Laws.pow2(32n))),
        Equal.trans(Nat, Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), scale(cout(32n, bits(U32{x}), bits(U32{y}), False{}), Laws.pow2(32n))), Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), scale(cout(32n, x, y, False{}), Laws.pow2(32n))), Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})),
        Equal.cong(Bool, Nat, z => Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), scale(z, Laws.pow2(32n))), cout(32n, bits(U32{x}), bits(U32{y}), False{}), cout(32n, x, y, False{}), same_cout(x, y)),
        Equal.trans(Nat, Nat.add(U32.to_nat(U32.add(U32{x}, U32{y})), scale(cout(32n, x, y, False{}), Laws.pow2(32n))), Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, False{}, False{})), scale(cout(32n, x, y, False{}), Laws.pow2(32n))), Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})),
        Equal.cong(Nat, Nat, z => Nat.add(z, scale(cout(32n, x, y, False{}), Laws.pow2(32n))), U32.to_nat(U32.add(U32{x}, U32{y})), Word.to_nat(32n, Word.adc(32n, x, y, False{}, False{})), same_sum(x, y)),
        Equal.trans(Nat, Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, False{}, False{})), scale(cout(32n, x, y, False{}), Laws.pow2(32n))), Nat.add(Nat.add(Word.to_nat(32n, x), Word.to_nat(32n, y)), bit(False{})), Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})),
        value(32n, x, y, False{}),
        Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(32n, x), Word.to_nat(32n, y)), bit(False{})), Nat.add(Nat.add(Word.to_nat(32n, x), Word.to_nat(32n, y)), 0n), Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})),
        Equal.cong(Nat, Nat, z => Nat.add(Nat.add(Word.to_nat(32n, x), Word.to_nat(32n, y)), z), bit(False{}), 0n, {==}),
        Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(32n, x), Word.to_nat(32n, y)), 0n), Nat.add(Word.to_nat(32n, x), Word.to_nat(32n, y)), Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})),
        add_zero_r(Nat.add(Word.to_nat(32n, x), Word.to_nat(32n, y))),
        same_args(x, y))))))))

# Borrow out of a - b with carry in c (c true means no borrow in), bit by bit from the lowest.
def bout(n: Nat, a: Word(n), b: Word(n), c: Bool) -> Bool:
  match n:
    case 0n:
      Bool.not(c)
    case 1n+p:
      match a b:
        case WCon{ab, at} WCon{bb, bt}:
          bout(p, at, bt, maj(ab, Bool.not(bb), c))

# The borrow out of a - b - r is a below b, or equal to b with a borrow in.
law borrow_below:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +c: Bool
  {bout(n, a, b, c) == below(Bool.not(c), Word.cmp(n, a, b)) : Bool}

def borrow_below(n, a, b, c):
  match n:
    case 0n:
      match a b c:
        case WNil{} WNil{} False{}:
          {==}
        case WNil{} WNil{} True{}:
          {==}
    case 1n+p:
      match a b c:
        case WCon{False{}, at} WCon{False{}, bt} False{}:
          Equal.trans(Bool, bout(p, at, bt, False{}), below(True{}, Word.cmp(p, at, bt)),
            below(True{}, Word.cmp.fin(False{}, False{}, Word.cmp(p, at, bt))),
            borrow_below(p, at, bt, False{}),
            Equal.sym(Bool, below(True{}, Word.cmp.fin(False{}, False{}, Word.cmp(p, at, bt))), below(True{}, Word.cmp(p, at, bt)),
              fin(Word.cmp(p, at, bt), False{}, False{}, True{})))
        case WCon{False{}, at} WCon{False{}, bt} True{}:
          Equal.trans(Bool, bout(p, at, bt, True{}), below(False{}, Word.cmp(p, at, bt)),
            below(False{}, Word.cmp.fin(False{}, False{}, Word.cmp(p, at, bt))),
            borrow_below(p, at, bt, True{}),
            Equal.sym(Bool, below(False{}, Word.cmp.fin(False{}, False{}, Word.cmp(p, at, bt))), below(False{}, Word.cmp(p, at, bt)),
              fin(Word.cmp(p, at, bt), False{}, False{}, False{})))
        case WCon{False{}, at} WCon{True{}, bt} False{}:
          Equal.trans(Bool, bout(p, at, bt, False{}), below(True{}, Word.cmp(p, at, bt)),
            below(True{}, Word.cmp.fin(False{}, True{}, Word.cmp(p, at, bt))),
            borrow_below(p, at, bt, False{}),
            Equal.sym(Bool, below(True{}, Word.cmp.fin(False{}, True{}, Word.cmp(p, at, bt))), below(True{}, Word.cmp(p, at, bt)),
              fin(Word.cmp(p, at, bt), False{}, True{}, True{})))
        case WCon{False{}, at} WCon{True{}, bt} True{}:
          Equal.trans(Bool, bout(p, at, bt, False{}), below(True{}, Word.cmp(p, at, bt)),
            below(False{}, Word.cmp.fin(False{}, True{}, Word.cmp(p, at, bt))),
            borrow_below(p, at, bt, False{}),
            Equal.sym(Bool, below(False{}, Word.cmp.fin(False{}, True{}, Word.cmp(p, at, bt))), below(True{}, Word.cmp(p, at, bt)),
              fin(Word.cmp(p, at, bt), False{}, True{}, False{})))
        case WCon{True{}, at} WCon{False{}, bt} False{}:
          Equal.trans(Bool, bout(p, at, bt, True{}), below(False{}, Word.cmp(p, at, bt)),
            below(True{}, Word.cmp.fin(True{}, False{}, Word.cmp(p, at, bt))),
            borrow_below(p, at, bt, True{}),
            Equal.sym(Bool, below(True{}, Word.cmp.fin(True{}, False{}, Word.cmp(p, at, bt))), below(False{}, Word.cmp(p, at, bt)),
              fin(Word.cmp(p, at, bt), True{}, False{}, True{})))
        case WCon{True{}, at} WCon{False{}, bt} True{}:
          Equal.trans(Bool, bout(p, at, bt, True{}), below(False{}, Word.cmp(p, at, bt)),
            below(False{}, Word.cmp.fin(True{}, False{}, Word.cmp(p, at, bt))),
            borrow_below(p, at, bt, True{}),
            Equal.sym(Bool, below(False{}, Word.cmp.fin(True{}, False{}, Word.cmp(p, at, bt))), below(False{}, Word.cmp(p, at, bt)),
              fin(Word.cmp(p, at, bt), True{}, False{}, False{})))
        case WCon{True{}, at} WCon{True{}, bt} False{}:
          Equal.trans(Bool, bout(p, at, bt, False{}), below(True{}, Word.cmp(p, at, bt)),
            below(True{}, Word.cmp.fin(True{}, True{}, Word.cmp(p, at, bt))),
            borrow_below(p, at, bt, False{}),
            Equal.sym(Bool, below(True{}, Word.cmp.fin(True{}, True{}, Word.cmp(p, at, bt))), below(True{}, Word.cmp(p, at, bt)),
              fin(Word.cmp(p, at, bt), True{}, True{}, True{})))
        case WCon{True{}, at} WCon{True{}, bt} True{}:
          Equal.trans(Bool, bout(p, at, bt, True{}), below(False{}, Word.cmp(p, at, bt)),
            below(False{}, Word.cmp.fin(True{}, True{}, Word.cmp(p, at, bt))),
            borrow_below(p, at, bt, True{}),
            Equal.sym(Bool, below(False{}, Word.cmp.fin(True{}, True{}, Word.cmp(p, at, bt))), below(False{}, Word.cmp(p, at, bt)),
              fin(Word.cmp(p, at, bt), True{}, True{}, False{})))

law sub_shift:
  for +s: Nat
  for +y: Nat
  for +q: Bool
  for +x: Nat
  for +bo: Bool
  for +m: Nat
  for ih: {Nat.add(Nat.add(s, y), bit(q)) == Nat.add(x, scale(bo, m)) : Nat}
  {Nat.add(Nat.add(Nat.double(s), Nat.double(y)), Nat.double(bit(q)))
    == Nat.add(Nat.double(x), scale(bo, Nat.double(m))) : Nat}

def sub_shift(s, y, q, x, bo, m, ih):
  Equal.trans(Nat, Nat.add(Nat.add(Nat.double(s), Nat.double(y)), Nat.double(bit(q))),
    Nat.add(Nat.double(Nat.add(s, y)), Nat.double(bit(q))),
    Nat.add(Nat.double(x), scale(bo, Nat.double(m))),
    Equal.cong(Nat, Nat, z => Nat.add(z, Nat.double(bit(q))), Nat.add(Nat.double(s), Nat.double(y)),
      Nat.double(Nat.add(s, y)), Equal.sym(Nat, Nat.double(Nat.add(s, y)), Nat.add(Nat.double(s), Nat.double(y)), double_add(s, y))),
  Equal.trans(Nat, Nat.add(Nat.double(Nat.add(s, y)), Nat.double(bit(q))),
    Nat.double(Nat.add(Nat.add(s, y), bit(q))),
    Nat.add(Nat.double(x), scale(bo, Nat.double(m))),
    Equal.sym(Nat, Nat.double(Nat.add(Nat.add(s, y), bit(q))), Nat.add(Nat.double(Nat.add(s, y)), Nat.double(bit(q))),
      double_add(Nat.add(s, y), bit(q))),
  Equal.trans(Nat, Nat.double(Nat.add(Nat.add(s, y), bit(q))), Nat.double(Nat.add(x, scale(bo, m))),
    Nat.add(Nat.double(x), scale(bo, Nat.double(m))),
    Equal.cong(Nat, Nat, z => Nat.double(z), Nat.add(Nat.add(s, y), bit(q)), Nat.add(x, scale(bo, m)), ih),
  Equal.trans(Nat, Nat.double(Nat.add(x, scale(bo, m))), Nat.add(Nat.double(x), Nat.double(scale(bo, m))),
    Nat.add(Nat.double(x), scale(bo, Nat.double(m))),
    double_add(x, scale(bo, m)),
    Equal.cong(Nat, Nat, z => Nat.add(Nat.double(x), z), Nat.double(scale(bo, m)), scale(bo, Nat.double(m)),
      Equal.sym(Nat, scale(bo, Nat.double(m)), Nat.double(scale(bo, m)), scale_double(bo, m)))))))

# The subtractor table on naturals: s + b + r = a + 2q at one bit.
law subber:
  for +x: Nat
  for +y: Nat
  for ab: Bool
  for bb: Bool
  for c: Bool
  {Nat.add(Nat.add(bitv(sum3(ab, Bool.not(bb), c), x), bitv(bb, y)), bit(Bool.not(c)))
    == bitv(ab, Nat.add(Nat.add(x, y), Nat.double(bit(Bool.not(maj(ab, Bool.not(bb), c)))))) : Nat}

def subber(x, y, ab, bb, c):
  match ab bb c:
    case False{} False{} False{}:
      Equal.sym(Nat, Nat.add(Nat.add(x, y), 2n), 1n+Nat.add(Nat.add(x, y), 1n), add_succ_r(Nat.add(x, y), 1n))
    case False{} False{} True{}:
      {==}
    case False{} True{} False{}:
      Equal.sym(Nat, Nat.add(Nat.add(x, y), 2n), Nat.add(Nat.add(x, 1n+y), 1n), adder(x, y, False{}, True{}, True{}))
    case False{} True{} True{}:
      Equal.sym(Nat, Nat.add(Nat.add(x, y), 2n), Nat.add(Nat.add(1n+x, 1n+y), 0n), adder(x, y, True{}, True{}, False{}))
    case True{} False{} False{}:
      add_succ_r(Nat.add(x, y), 0n)
    case True{} False{} True{}:
      {==}
    case True{} True{} False{}:
      Equal.cong(Nat, Nat, z => 1n+z, Nat.add(Nat.add(x, 1n+y), 1n), Nat.add(Nat.add(x, y), 2n),
        Equal.sym(Nat, Nat.add(Nat.add(x, y), 2n), Nat.add(Nat.add(x, 1n+y), 1n), adder(x, y, False{}, True{}, True{})))
    case True{} True{} True{}:
      Equal.cong(Nat, Nat, z => Nat.add(z, 0n), Nat.add(x, 1n+y), 1n+Nat.add(x, y), add_succ_r(x, y))

# The n-bit subtractor computes a - b - r exactly: the difference word plus b and the borrow in
# equals a plus the borrow out times 2^n.
law sub_value:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +c: Bool
  {Nat.add(Nat.add(Word.to_nat(n, Word.adc(n, a, b, True{}, c)), Word.to_nat(n, b)), bit(Bool.not(c)))
    == Nat.add(Word.to_nat(n, a), scale(bout(n, a, b, c), Laws.pow2(n))) : Nat}

def sub_value(n, a, b, c):
  match n:
    case 0n:
      match a b c:
        case WNil{} WNil{} False{}:
          {==}
        case WNil{} WNil{} True{}:
          {==}
    case 1n+p:
      match a b c:
        case WCon{False{}, at} WCon{False{}, bt} False{}:
          Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(1n+p, WCon{True{}, Word.adc(p, at, bt, True{}, False{})}), Word.to_nat(1n+p, WCon{False{}, bt})), bit(Bool.not(False{}))), bitv(False{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(False{}))))), bitv(False{}, Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, False{}), Nat.double(Laws.pow2(p))))),
            subber(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt)), False{}, False{}, False{}),
            Equal.cong(Nat, Nat, z => bitv(False{}, z),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(False{})))),
              Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))),
              sub_shift(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{})), Word.to_nat(p, bt), Bool.not(False{}), Word.to_nat(p, at), bout(p, at, bt, False{}), Laws.pow2(p), sub_value(p, at, bt, False{}))))
        case WCon{False{}, at} WCon{False{}, bt} True{}:
          Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(1n+p, WCon{False{}, Word.adc(p, at, bt, True{}, True{})}), Word.to_nat(1n+p, WCon{False{}, bt})), bit(Bool.not(True{}))), bitv(False{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(True{}))))), bitv(False{}, Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, True{}), Nat.double(Laws.pow2(p))))),
            subber(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt)), False{}, False{}, True{}),
            Equal.cong(Nat, Nat, z => bitv(False{}, z),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(True{})))),
              Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))),
              sub_shift(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{})), Word.to_nat(p, bt), Bool.not(True{}), Word.to_nat(p, at), bout(p, at, bt, True{}), Laws.pow2(p), sub_value(p, at, bt, True{}))))
        case WCon{False{}, at} WCon{True{}, bt} False{}:
          Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(1n+p, WCon{False{}, Word.adc(p, at, bt, True{}, False{})}), Word.to_nat(1n+p, WCon{True{}, bt})), bit(Bool.not(False{}))), bitv(False{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(False{}))))), bitv(False{}, Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, False{}), Nat.double(Laws.pow2(p))))),
            subber(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt)), False{}, True{}, False{}),
            Equal.cong(Nat, Nat, z => bitv(False{}, z),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(False{})))),
              Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))),
              sub_shift(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{})), Word.to_nat(p, bt), Bool.not(False{}), Word.to_nat(p, at), bout(p, at, bt, False{}), Laws.pow2(p), sub_value(p, at, bt, False{}))))
        case WCon{False{}, at} WCon{True{}, bt} True{}:
          Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(1n+p, WCon{True{}, Word.adc(p, at, bt, True{}, False{})}), Word.to_nat(1n+p, WCon{True{}, bt})), bit(Bool.not(True{}))), bitv(False{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(False{}))))), bitv(False{}, Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, False{}), Nat.double(Laws.pow2(p))))),
            subber(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt)), False{}, True{}, True{}),
            Equal.cong(Nat, Nat, z => bitv(False{}, z),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(False{})))),
              Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))),
              sub_shift(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{})), Word.to_nat(p, bt), Bool.not(False{}), Word.to_nat(p, at), bout(p, at, bt, False{}), Laws.pow2(p), sub_value(p, at, bt, False{}))))
        case WCon{True{}, at} WCon{False{}, bt} False{}:
          Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(1n+p, WCon{False{}, Word.adc(p, at, bt, True{}, True{})}), Word.to_nat(1n+p, WCon{False{}, bt})), bit(Bool.not(False{}))), bitv(True{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(True{}))))), bitv(True{}, Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, True{}), Nat.double(Laws.pow2(p))))),
            subber(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt)), True{}, False{}, False{}),
            Equal.cong(Nat, Nat, z => bitv(True{}, z),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(True{})))),
              Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))),
              sub_shift(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{})), Word.to_nat(p, bt), Bool.not(True{}), Word.to_nat(p, at), bout(p, at, bt, True{}), Laws.pow2(p), sub_value(p, at, bt, True{}))))
        case WCon{True{}, at} WCon{False{}, bt} True{}:
          Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(1n+p, WCon{True{}, Word.adc(p, at, bt, True{}, True{})}), Word.to_nat(1n+p, WCon{False{}, bt})), bit(Bool.not(True{}))), bitv(True{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(True{}))))), bitv(True{}, Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, True{}), Nat.double(Laws.pow2(p))))),
            subber(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt)), True{}, False{}, True{}),
            Equal.cong(Nat, Nat, z => bitv(True{}, z),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(True{})))),
              Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))),
              sub_shift(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{})), Word.to_nat(p, bt), Bool.not(True{}), Word.to_nat(p, at), bout(p, at, bt, True{}), Laws.pow2(p), sub_value(p, at, bt, True{}))))
        case WCon{True{}, at} WCon{True{}, bt} False{}:
          Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(1n+p, WCon{True{}, Word.adc(p, at, bt, True{}, False{})}), Word.to_nat(1n+p, WCon{True{}, bt})), bit(Bool.not(False{}))), bitv(True{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(False{}))))), bitv(True{}, Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, False{}), Nat.double(Laws.pow2(p))))),
            subber(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt)), True{}, True{}, False{}),
            Equal.cong(Nat, Nat, z => bitv(True{}, z),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(False{})))),
              Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, False{}), Nat.double(Laws.pow2(p)))),
              sub_shift(Word.to_nat(p, Word.adc(p, at, bt, True{}, False{})), Word.to_nat(p, bt), Bool.not(False{}), Word.to_nat(p, at), bout(p, at, bt, False{}), Laws.pow2(p), sub_value(p, at, bt, False{}))))
        case WCon{True{}, at} WCon{True{}, bt} True{}:
          Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(1n+p, WCon{False{}, Word.adc(p, at, bt, True{}, True{})}), Word.to_nat(1n+p, WCon{True{}, bt})), bit(Bool.not(True{}))), bitv(True{}, Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(True{}))))), bitv(True{}, Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, True{}), Nat.double(Laws.pow2(p))))),
            subber(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt)), True{}, True{}, True{}),
            Equal.cong(Nat, Nat, z => bitv(True{}, z),
              Nat.add(Nat.add(Nat.double(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{}))), Nat.double(Word.to_nat(p, bt))), Nat.double(bit(Bool.not(True{})))),
              Nat.add(Nat.double(Word.to_nat(p, at)), scale(bout(p, at, bt, True{}), Nat.double(Laws.pow2(p)))),
              sub_shift(Word.to_nat(p, Word.adc(p, at, bt, True{}, True{})), Word.to_nat(p, bt), Bool.not(True{}), Word.to_nat(p, at), bout(p, at, bt, True{}), Laws.pow2(p), sub_value(p, at, bt, True{}))))

law same_sub:
  for +x: Word(32n)
  for +y: Word(32n)
  {Nat.add(U32.to_nat(U32.sub(U32{x}, U32{y})), U32.to_nat(U32{y})) == Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, True{}, True{})), Word.to_nat(32n, y)) : Nat}

def same_sub(x, y):
  {==}

law same_word:
  for +x: Word(32n)
  {Word.to_nat(32n, x) == U32.to_nat(U32{x}) : Nat}

def same_word(x):
  {==}

# Gl.borrow(a, b) is 1 exactly when the subtraction a - b wraps around.
law borrow_flag:
  for +x: Word(32n)
  for +y: Word(32n)
  {Gl.borrow(U32{x}, U32{y}) == Bool.to_u32(bout(32n, x, y, True{})) : U32}

def borrow_flag(x, y):
  Equal.cong(Bool, U32, f => Bool.to_u32(f), Cmp.is_lt(Word.cmp(32n, x, y)), bout(32n, x, y, True{}),
    Equal.sym(Bool, bout(32n, x, y, True{}), Cmp.is_lt(Word.cmp(32n, x, y)),
      Equal.trans(Bool, bout(32n, x, y, True{}), below(False{}, Word.cmp(32n, x, y)), Cmp.is_lt(Word.cmp(32n, x, y)),
        borrow_below(32n, x, y, True{}), or_false(Cmp.is_lt(Word.cmp(32n, x, y))))))

# REQ-ASSURE-5, limb law 2: a 32-bit difference plus b is a, plus 2^32 when Gl.borrow is set.
law borrow_exact:
  for +a: U32
  for +b: U32
  {Nat.add(U32.to_nat(U32.sub(a, b)), U32.to_nat(b))
    == Nat.add(U32.to_nat(a), Nat.mul(U32.to_nat(Gl.borrow(a, b)), Laws.pow2(32n))) : Nat}

def borrow_exact(a, b):
  match a b:
    case U32{x} U32{y}:
      Equal.trans(Nat, Nat.add(U32.to_nat(U32.sub(U32{x}, U32{y})), U32.to_nat(U32{y})), Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, True{}, True{})), Word.to_nat(32n, y)), Nat.add(U32.to_nat(U32{x}), Nat.mul(U32.to_nat(Gl.borrow(U32{x}, U32{y})), Laws.pow2(32n))),
        same_sub(x, y),
        Equal.trans(Nat, Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, True{}, True{})), Word.to_nat(32n, y)), Nat.add(Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, True{}, True{})), Word.to_nat(32n, y)), bit(Bool.not(True{}))), Nat.add(U32.to_nat(U32{x}), Nat.mul(U32.to_nat(Gl.borrow(U32{x}, U32{y})), Laws.pow2(32n))),
        Equal.sym(Nat, Nat.add(Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, True{}, True{})), Word.to_nat(32n, y)), 0n), Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, True{}, True{})), Word.to_nat(32n, y)), add_zero_r(Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, True{}, True{})), Word.to_nat(32n, y)))),
        Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(32n, Word.adc(32n, x, y, True{}, True{})), Word.to_nat(32n, y)), bit(Bool.not(True{}))), Nat.add(Word.to_nat(32n, x), scale(bout(32n, x, y, True{}), Laws.pow2(32n))), Nat.add(U32.to_nat(U32{x}), Nat.mul(U32.to_nat(Gl.borrow(U32{x}, U32{y})), Laws.pow2(32n))),
        sub_value(32n, x, y, True{}),
        Equal.trans(Nat, Nat.add(Word.to_nat(32n, x), scale(bout(32n, x, y, True{}), Laws.pow2(32n))), Nat.add(Word.to_nat(32n, x), Nat.mul(U32.to_nat(Bool.to_u32(bout(32n, x, y, True{}))), Laws.pow2(32n))), Nat.add(U32.to_nat(U32{x}), Nat.mul(U32.to_nat(Gl.borrow(U32{x}, U32{y})), Laws.pow2(32n))),
        Equal.cong(Nat, Nat, z => Nat.add(Word.to_nat(32n, x), z), scale(bout(32n, x, y, True{}), Laws.pow2(32n)), Nat.mul(U32.to_nat(Bool.to_u32(bout(32n, x, y, True{}))), Laws.pow2(32n)),
          Equal.sym(Nat, Nat.mul(U32.to_nat(Bool.to_u32(bout(32n, x, y, True{}))), Laws.pow2(32n)), scale(bout(32n, x, y, True{}), Laws.pow2(32n)), flag_scale(bout(32n, x, y, True{}), Laws.pow2(32n)))),
        Equal.trans(Nat, Nat.add(Word.to_nat(32n, x), Nat.mul(U32.to_nat(Bool.to_u32(bout(32n, x, y, True{}))), Laws.pow2(32n))), Nat.add(Word.to_nat(32n, x), Nat.mul(U32.to_nat(Gl.borrow(U32{x}, U32{y})), Laws.pow2(32n))), Nat.add(U32.to_nat(U32{x}), Nat.mul(U32.to_nat(Gl.borrow(U32{x}, U32{y})), Laws.pow2(32n))),
        Equal.cong(U32, Nat, f => Nat.add(Word.to_nat(32n, x), Nat.mul(U32.to_nat(f), Laws.pow2(32n))), Bool.to_u32(bout(32n, x, y, True{})), Gl.borrow(U32{x}, U32{y}),
          Equal.sym(U32, Gl.borrow(U32{x}, U32{y}), Bool.to_u32(bout(32n, x, y, True{})), borrow_flag(x, y))),
        Equal.cong(Nat, Nat, z => Nat.add(z, Nat.mul(U32.to_nat(Gl.borrow(U32{x}, U32{y})), Laws.pow2(32n))), Word.to_nat(32n, x), U32.to_nat(U32{x}), same_word(x)))))))
