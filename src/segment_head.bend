import Base
import ./head_types.bend as G
import ./head_catalog.bend as C
import ./head_rounds.bend as R
import ./head_weights.bend as W
import ./head_coverage.bend as V
import ./head_aff.bend as Aff
import ./head_norm.bend as Norm
import ./head_policy.bend as Policy
import ./head_tables.bend as Tables
import ./head_lookup.bend as Lookup
import ./segment_planes.bend as Planes
import ./segment_model.bend as Model
import ./segment_forest.bend as Forest
import ./segment_tables.bend as S
import ./weight_merge.bend as Merge
import ./weight_types.bend as Weights
import ./weight_catalog.bend as Layout
import ./plan_types.bend as P
import ./lin_own.bend as Own
import ./fold.bend as F
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as PSC
import ./key_stage_trace.bend as Trace
import ./header.bend as H

type Prepared is Data:
  Prepared{before: Model.Equations, after: Model.Equations, functions: Model.Functionals,
    used: Nat, free_slot: Nat, pending: Own.Pending}

def weights(p: P.Profile) -> Weights.Layout:
  match p:
    case P.SmallExact{}: Layout.small()
    case P.SmallClipped{}: Layout.small()
    case _: Layout.full()

def next_slot(v: A.Value) -> Nat:
  A.Value{_,i,_} = v
  1n+i

def used(h: R.Heard) -> Nat:
  R.Heard{_,_,_,_,_,_,_,_,l} = h
  next_slot(A.at(PSC.ends(l),1n))

def bundled(p: Planes.Parts, m: Merge.Merged, prev: Model.Equations, after: Model.Equations,
  funcs: Model.Functionals, n: Nat, slots: Nat) -> IO(Prepared):
  match p m:
    case Planes.Parts{rows,more} Merge.Merged{row,pending,free,PSC.Cursor{[],at}}:
      do IO<Prepared>:
        ok : Unit <- H.require(Nat.is_eq(at,slots),"NO: head-slot-count")
        return Prepared{F.cat(Model.Aff,prev,rows),F.cat(Model.Aff,after,[row]),F.cat(Model.Functional,funcs,more),n,free,pending}
    case _ _: IO.die(Prepared,1,"NO: head-merge-tail")

def forms(+s: G.Shape, +k: R.Keys, +cov: V.Covered, +heard: R.Heard, +f: Forest.Claims, +shape: S.Forest,
  +link: Nat, m: Merge.Merged) -> IO(Prepared):
  +n = C.u3(s)
  do IO<Prepared>:
    norm : Model.Equations <- Norm.norm(s,heard,k,link)
    joined : Aff.Aff <- Lookup.join(s,k,cov,heard,f,shape)
    prefix : Model.Equations = F.cat(Model.Aff,Model.mask_rows(f),F.cat(Model.Aff,norm,
      Aff.equation(joined,link) <> Policy.equations(s,cov,k,link)))
    planes : Planes.Parts <- Planes.on_u3(f,shape,link,C.mask_bits(s),[G.offset(s,12n),G.offset(s,13n),G.offset(s,14n)],
      n,Nat.add(C.n_hf(s),2n))
    bundled(planes,m,prefix,Norm.logits(s,heard,link),Tables.functions(s,k,heard,cov),used(heard),C.slots(s))

def compute(input: Model.Inputs,+profile: P.Profile) -> IO(Prepared):
  Model.Inputs{+link,+f,_,+events,st,+shape,_} = input
  +s = C.select(profile)
  +layout = weights(profile)
  +k = R.keys(f,shape,C.lt(s))
  do IO<Prepared>:
    +cov : V.Covered <- V.load(st,s)
    +h : R.Heard <- R.hear(s,k,events)
    c : Weights.Claim <- W.make(s,k,cov,h,layout)
    m : Merge.Merged <- W.merge(s,layout,c,events,Nat.div(link,2n))
    forms(s,k,cov,h,f,shape,link,m)
