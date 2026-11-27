import Base
import ./LAWS.bend as Laws
import ./proofs/words.bend as W

def Laws.carry_exact(a, b):
  W.carry_exact(a, b)

def Laws.borrow_exact(a, b):
  W.borrow_exact(a, b)
