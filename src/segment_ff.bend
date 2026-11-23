import Base
import ./ff_local.bend as Local
import ./ff_shape.bend as G
import ./ff_rounds.bend as R
import ./ff_lookup.bend as Lookup
import ./ff_stack.bend as Stack
import ./ff_stack_weights.bend as Weights
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./segment_attention_rounds.bend as Round
import ./segment_model.bend as M
import ./weight_types.bend as W
import ./weight_merge.bend as Merge
import ./plan_types.bend as Profile
import ./lin_own.bend as Own
import ./fold.bend as F
import ./header.bend as Header

# R11.2. Smallness enters between these two ordered lists of equations. The
# weight-merge result is consumed by the request's second chain.
type Prepared is Data:
  Prepared{before:M.Equations,after:M.Equations,functions:M.Functionals,used:Nat,free_slot:Nat,pending:Own.Pending}

def finish(p:Local.Prefix,after:M.Equations,m:Merge.Merged) -> IO(Prepared):
  match p m:
    case Local.Prefix{rows,fs} Merge.Merged{eq,pending,free,P.Cursor{[],used}}:
      IO.pure(Prepared,Prepared{rows,F.cat(M.Aff,after,[eq]),fs,used,free,pending})
    case _ _: IO.die(Prepared,1,"NO: feed-forward-merge-tail")

def parts(ctx:Local.Context,+input:M.Inputs) -> IO(Prepared):
  Local.Context{+s,+key,+heard} = ctx
  R.Heard{_,R.Tokens{_,+terms,+stack},R.Coins{_,_,_,_,delta},R.Points{_,_,_,ze,tkh},+merge} = heard
  M.Inputs{+link,main,_,_,+st,sh,_} = input
  do IO<Prepared>:
    prefix : Local.Prefix <- Local.prefix(Local.Context{s,key,heard},input)
    join : A.Aff <- Lookup.join(s,link,main,st,sh)
    rows : A.Equations <- Stack.run(s,link,key,st,join,terms,delta,stack)
    +cs : List<&2,W.Claim> <- Weights.claims(s,link,key,st,terms,stack,ze,tkh,Round.declared(merge))
    ok : Unit <- Header.require(Nat.is_eq(F.count(W.Claim,cs,0n),G.field(s,"NCL")),"NO: feed-forward-weight-count")
    result : Merge.Merged <- Merge.psc(merge,Weights.layout(s),cs,Nat.div(link,2n))
    finish(prefix,A.equations(rows,link,G.field(s,"u3"),[]),result)

def compute(+input:M.Inputs,p:Profile.Profile) -> IO(Prepared):
  do IO<Prepared>:
    c : Local.Context <- Local.hear(input,p)
    parts(c,input)
