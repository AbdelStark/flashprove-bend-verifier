import Base
import ./segment_attention_aff.bend as A
import ./segment_attention_shape.bend as S
import ./segment_attention_psc.bend as P
import ./segment_attention_rounds.bend as Round
import ./segment_attention_scores.bend as Scores
import ./segment_attention_division.bend as D
import ./segment_attention_softmax.bend as V
import ./segment_attention_maximum.bend as Max
import ./segment_attention_tables.bend as Tab
import ./segment_forest.bend as Forest
import ./segment_tables.bend as Types
import ./segment_planes.bend as Pl
import ./segment_model.bend as M
import ./key_stage_lookup_rows.bend as L
import ./key_stage_trace.bend as Trace
import ./plan.bend as Plan
import ./header.bend as Header
import ./base_check.bend as B
import ./extension.bend as X

# R11.3 groups 1–9 and all evaluation functionals for group 10. The caller
# appends smallness and checks the batched equation in the request frame.
type Prepared is Data:
  Prepared{equations: M.Equations, functions: M.Functionals, used: Nat}

def owned(forest: Forest.Claims,+s: S.Shape,+keys: S.Keys,proof: Round.Proof) -> A.Equations:
  S.Keys{+rm,+rd,+fm,+fd,+w,+i,+h,_,_} = keys
  Round.Proof{+km,+kd,+se,+vm,vd,z,ms,sf,sd,hb,+gam,om,o4,o5,_} = proof
  +v = P.prefix(km)
  a = Scores.cat(Scores.kr(s,False{},rm,v,0n),Scores.kr(s,True{},rd,v,3n))
  b = Scores.cat(Scores.score(s,False{},fm,km),Scores.score(s,True{},fd,kd))
  c = D.equations(D.At{s,D.Pieces{w,i,h},se})
  j = D.joined(forest,s,keys,km,kd,se)
  d = V.equations(s,w,vm,vd,se,gam)
  e = Max.equations(Max.Stage{s,z,ms,sf,sd,hb},om,o4,o5)
  Scores.cat(a,Scores.cat(b,Scores.cat(c,j <> Scores.cat(d,e))))

def end(+tree: Forest.Claims,link: Nat,+sh: S.Shape,+ks: S.Keys,+p: Round.Proof,projected: Pl.Parts) -> Prepared:
  Round.Proof{_,_,_,_,_,_,_,_,_,_,_,_,_,_,slots} = p
  Pl.Parts{rows,functions} = projected
  cs = A.equations(owned(tree,sh,ks,p),link,S.length(sh),[])
  Prepared{List.append(&2,M.Aff,M.mask_rows(tree),List.append(&2,M.Aff,cs,rows)),
    List.append(&2,M.Functional,Tab.functions(sh,ks,p),functions),slots}

def slots(shape: Types.Forest) -> Nat:
  Types.Forest{n,k,r,c,_} = shape
  +v = Nat.add(n,r)
  +d = Nat.add(k,c)
  # Tie, key levels, table levels, leaf polynomial and bit test.
  Nat.add(Nat.add(Nat.add(Nat.add(Nat.add(Nat.add(187n,Nat.mul(v,Nat.add(v,4n))),Nat.mul(d,Nat.add(d,14n))),6n),Nat.mul(2n,d)),14n),Nat.mul(2n,d))

def rest(events: Trace.Events,n: Nat) -> IO(Trace.Events):
  match events n:
    case xs 0n: IO.pure(Trace.Events,xs)
    case Con{Trace.Observed{Plan.Round{_,_,_,bytes,0,_,_,_,_,_,_,_},_,_,_,_},tail} +left:
      +words = U32.to_nat(U32.div(bytes,24))
      do IO<Trace.Events>:
        ok : Unit <- Header.require(Nat.is_le(words,left),"NO: attention-forest-boundary")
        rest(tail,Nat.sub(left,words))
    case _ _: IO.die(Trace.Events,1,"NO: attention-forest-length")

def point(f: Forest.Claims) -> B.Elements:
  Forest.Claims{L.Point{z,_,_},_,_,_} = f
  z

def compute(input: M.Inputs) -> IO(Prepared):
  M.Inputs{+link,+main,_,events,st,+shape,_} = input
  +start = slots(shape)
  do IO<Prepared>:
    +s : S.Shape <- S.shape(st)
    +keys : S.Keys <- S.keys(shape,point(main),s)
    tail : Trace.Events <- rest(events,start)
    c : P.Cursor <- Round.scan(tail,start,[])
    p : Round.Proof <- Round.parse(s,c)
    parts : Pl.Parts <- Pl.on_u3(main,shape,link,S.mb(s),[S.bits(s,0n),S.bits(s,1n),S.bits(s,2n)],S.length(s),3n)
    return end(main,link,s,keys,p,parts)
