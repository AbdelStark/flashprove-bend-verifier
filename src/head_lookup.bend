import ./segment_attention_psc.bend as PSC
import Base
import ./head_types.bend as G
import ./head_catalog.bend as C
import ./head_rounds.bend as R
import ./head_aff.bend as H
import ./head_coverage.bend as V
import ./head_policy.bend as Policy
import ./segment_attention_aff.bend as A
import ./segment_attention_psc.bend as P
import ./segment_forest.bend as Forest
import ./segment_tables.bend as S
import ./key_stage_lookup_rows.bend as L
import ./key_stage_lookup.bend as Int
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F
import ./row_tensor.bend as T
import ./base_check.bend as B
import ./header.bend as Header

type Context is Data:
  Context{s: G.Shape, k: R.Keys, c: V.Covered, norm: A.Value, logits: A.Value}

def limbs(n: Nat, +s: G.Shape, +k: R.Keys, +seg: Nat, off: Nat, +stride: Nat, +w: X.E3, acc: H.Aff) -> H.Aff:
  match n:
    case 0n: acc
    case 1n+j:
      +i = off
      piece = H.placed(s,k,seg,G.offset(s,0n),Nat.div(i,A.size(C.ls(s))),C.ls(s),w)
      limbs(j,s,k,seg,Nat.add(i,stride),stride,E.mul(w,A.nat(256n)),H.plus(acc,piece))

def sl(+c: Context, seg: Nat, off: Nat, n: Nat, stride: Nat) -> H.Aff:
  Context{s,k,_,_,_} = c
  limbs(n,s,k,seg,off,stride,F.one(),H.zero())

def bias(w: X.E3, n: Nat) -> H.Aff: H.constant(E.mul(w,A.nat(n)))

def norm_at(seg: Nat, ctx: Context, w: X.E3, +d: Nat, +kf: Nat, ra: H.Aff) -> H.Aff:
  match seg:
    case 0n:
      aw = sl(ctx,0n,0n,2n,d)
      base = E.mul(w,F.sub(A.nat(A.size(Nat.sub(kf,1n))),A.nat(Nat.mul(65536n,32896n))))
      H.add(H.add(H.constant(base),aw,E.negate(A.nat(A.size(kf)))),ra,E.negate(A.nat(65536n)))
    case _: H.scale(H.plus(bias(w,32896n),ra),A.nat(A.size(Nat.sub(32n,kf))))

def norm(+ctx: Context, +seg: Nat, w: X.E3) -> H.Aff:
  Context{+s,_,_,_,_} = ctx
  +d = C.channels(s)
  +kf = C.kf(s)
  ra = sl(ctx,seg,Nat.mul(2n,d),2n,d)
  norm_at(seg,ctx,w,d,kf,ra)

def digit_at(which: Nat, ctx: Context, seg: Nat, w: X.E3, d: Nat, +v: Nat) -> H.Aff:
  match which:
    case 1n: H.plus(bias(w,32896n),sl(ctx,seg,d,2n,v))
    case _: H.plus(bias(w,128n),sl(ctx,seg,Nat.add(d,Nat.mul(2n,v)),1n,v))

def digit(+ctx: Context, +seg: Nat, which: Nat, w: X.E3) -> H.Aff:
  Context{+s,_,_,_,_} = ctx
  +d = Nat.mul(4n,C.channels(s))
  +v = C.jv(s)
  digit_at(which,ctx,seg,w,d,v)

def margin_at(seg: Nat, +ctx: Context, +s: G.Shape, +k: R.Keys, +cov: V.Covered, v: A.Value, g: G.Segment, wx: X.E3, +w: X.E3) -> H.Aff:
  match seg:
    case 3n: digit(ctx,3n,1n,w)
    case 4n: digit(ctx,4n,2n,w)
    case _:
      +erc = V.cost(cov,R.tokens(k))
      +sh = C.sh(s)
      paid = H.add(Policy.gap(s,10n,0n,erc),Policy.gap(s,10n,1n,erc),A.nat(A.size(37n)))
      first = H.add(H.scale(H.slot(v),A.nat(A.size(C.log_channels(s)))),paid,wx)
      ties = H.minus(first,H.constant(V.tie(cov,g,k,C.lt(s))))
      d1 = H.add(ties,digit(ctx,2n,1n,w),E.negate(A.nat(A.size(sh))))
      H.scale(H.minus(d1,digit(ctx,2n,2n,w)),Int.power(6n,Nat.add(sh,15n),PSC.half(),F.one()))

def margin(+ctx: Context, +seg: Nat) -> H.Aff:
  Context{+s,+k,+cov,_,v} = ctx
  +g = G.segment(s,seg)
  +wx = V.mass(g,k,C.lt(s),C.vocab(s))
  +w = E.mul(wx,V.on(cov,R.tokens(k)))
  margin_at(seg,ctx,s,k,cov,v,g,wx,w)

def exponential(+ctx: Context,+seg: Nat,w: X.E3) -> H.Aff:
  Context{+s,+k,cov,_,_} = ctx
  +v = C.jv(s)
  +first = Bool.pick(Nat,Nat.is_eq(seg,6n),C.jva(s),0n)
  +off = Nat.mul(4n,C.channels(s))
  wx = V.mass(G.segment(s,seg),k,C.lt(s),Nat.sub(C.vocab(s),first))
  d1 = H.plus(bias(E.mul(wx,V.on(cov,R.tokens(k))),32896n),sl(ctx,seg,Nat.add(off,first),2n,v))
  ex = H.plus(bias(w,8421505n),sl(ctx,seg,Nat.add(first,Nat.add(off,Nat.mul(3n,v))),3n,v))
  H.add(d1,ex,A.nat(65536n))

def ledger_mu(n: Nat) -> Nat:
  match n:
    case 9n: 4n
    case 58n: 2n
    case 59n: 128n
    case 63n: 2n
    case 76n: 2n
    case 79n: 32n
    case _: 1n

def ledger_vals(ws: B.Elements, +s: G.Shape, +offset: Nat, i: Nat, acc: H.Aff) -> H.Aff:
  match ws:
    case []: acc
    case v <> tail:
      +j = i
      cell = H.plus(H.cell(s,Nat.add(offset,j)),H.constant(A.nat(128n)))
      ledger_vals(tail,s,offset,1n+j,H.add(acc,cell,E.mul(v,A.nat(ledger_mu(j)))))

def line_at(seg: Nat, +ctx: Context, +s: G.Shape, +k: R.Keys, w: X.E3) -> H.Aff:
  match seg:
    case 0n: norm(ctx,0n,w)
    case 1n: norm(ctx,1n,w)
    case 2n: margin(ctx,2n)
    case 3n: margin(ctx,3n)
    case 4n: margin(ctx,4n)
    case 5n: exponential(ctx,5n,w)
    case 6n: exponential(ctx,6n,w)
    case 7n: ledger_vals(V.weights(G.segment(s,7n),k,C.lt(s)),s,G.offset(s,6n),0n,H.zero())
    case _:
      +d = C.channels(s)
      +at = G.offset(s,4n)
      b = H.plus(H.placed(s,k,8n,at,0n,0n,F.one()),H.placed(s,k,8n,at,d,0n,A.nat(256n)))
      H.plus(H.add(sl(ctx,8n,0n,2n,d),b,A.nat(A.size(28n))),bias(w,Nat.add(32768n,A.size(39n))))

def line(+ctx: Context, +seg: Nat, w: X.E3) -> H.Aff:
  Context{+s,+k,_,_,_} = ctx
  line_at(seg,ctx,s,k,w)

def belongs(g: G.Segment, q: Nat) -> Bool:
  G.Segment{i,_,_,_} = g
  Nat.is_eq(i,q)

def add_line(ctx: Context, j: Nat, +w: X.E3, pad: X.E3, acc: H.Aff) -> H.Aff:
  H.plus(acc,H.minus(line(ctx,j,w),H.constant(E.mul(w,pad))))

def lines(n: Nat, +ctx: Context, +q: Nat, +pad: X.E3, +acc: H.Aff) -> H.Aff:
  match n:
    case 0n: acc
    case 1n+k:
      Context{+s,keys,_,_,_} = ctx
      +j = k
      +seg = G.segment(s,j)
      next = Bool.pick(Unit -> H.Aff,belongs(seg,q),
        _ => add_line(ctx,j,V.mass(seg,keys,C.lt(s),A.size(24n)),pad,acc),
        _ => acc)
      lines(j,ctx,q,pad,next(Unit{}))

def call_forms(calls: List<&2,S.Call>, +ctx: Context, +zy: B.Elements, +theta: X.E3, i: Nat, +pad0: X.E3, acc: H.Aff) -> H.Aff:
  match calls:
    case []: acc
    case S.Call{_,_,start,+bits,pad,_} <> tail:
      Context{_,_,_,norm_slot,_} = ctx
      +j = i
      +v = A.nat(pad)
      e = T.entry(T.eq(List.drop(&2,X.E3,zy,bits)),Nat.div(start,A.size(bits)),F.one())
      +base = H.constant(E.add(F.sub(v,pad0),E.mul(A.nat(j),theta)))
      weight = Bool.pick(H.Aff,Nat.is_eq(j,0n),H.plus(base,H.slot(norm_slot)),base)
      row = H.add(acc,lines(9n,ctx,j,v,weight),E.negate(e))
      call_forms(tail,ctx,zy,theta,1n+j,pad0,row)

def first_call(cs: List<&2,S.Call>) -> IO(S.Call):
  match cs:
    case x <> _: IO.pure(S.Call,x)
    case _: IO.die(S.Call,1,"NO: head-lookup-calls")

def padding(s: S.Call) -> X.E3:
  S.Call{_,_,_,_,p,_} = s
  A.nat(p)

def join(s: G.Shape, +k: R.Keys, c: V.Covered, h: R.Heard, f: Forest.Claims, shape: S.Forest) -> IO(H.Aff):
  R.Keys{trees,_,_} = k
  R.Heard{_,_,_,_,_,_,_,n,l} = h
  Forest.Claims{L.Point{_,ms,v},alpha,theta,_} = f
  S.Forest{_,_,_,_,+cs} = shape
  context: Context = Context{s,k,c,A.at(P.prefix(n),0n),A.at(P.prefix(l),0n)}
  # All unused trees are padded with the first call's entry. Every call
  # replaces its own share of that padding with its actual shifted key.
  do IO<H.Aff>:
    first : S.Call <- first_call(cs)
    +pad : X.E3 = padding(first)
    return call_forms(cs,context,trees,theta,0n,pad,H.Aff{[],ms,F.sub(F.sub(alpha,v),pad)})
