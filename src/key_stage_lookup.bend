import Base
import ./key_stage_lookup_plan.bend as M
import ./key_stage_lookup_rows.bend as L
import ./key_stage_lookup_levels.bend as V
import ./key_stage_psc.bend as PSC
import ./key_stage_openings.bend as K
import ./base_check.bend as B
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F
import ./row_tensor.bend as Tensor
import ./hash_bytes.bend as H
import ./header.bend as Header

def small(+n: Nat) -> X.E3:
  X.E3{U32.from_nat(Nat.div(n,Nat.pow(2n,32n))),U32.from_nat(n),0,0,0,0}

def power(k: Nat, n: Nat, +x: X.E3, +acc: X.E3) -> X.E3:
  match k n:
    case _ 0n: acc
    case 1n+left +e:
      next = Bool.pick(X.E3,Nat.is_eq(Nat.mod(e,2n),0n),acc,E.mul(acc,x))
      power(left,Nat.div(e,2n),E.mul(x,x),next)
    case _ _: acc

def real(runs: List<&2,M.Run>, acc: Nat) -> Nat:
  match runs:
    case []: acc
    case M.Run{_,_,count,_} <> more: real(more,Nat.add(acc,U32.to_nat(count)))

def counts(parts: List<&2,M.Part>, +unit: Nat, pad: Nat, covered: Nat) -> Nat & Nat:
  match parts:
    case []: (pad,covered)
    case M.Part{lp,rows} <> tail:
      +length = real(rows,0n)
      missing = Nat.sub(Nat.pow(2n,U32.to_nat(lp)),length)
      counts(tail,unit,Nat.add(pad,Nat.mul(unit,missing)),Nat.add(covered,Nat.mul(unit,length)))

# Position j's public table value is its index; at a non-Boolean point this is sum 2^i z[i].
def index(xs: B.Elements, +bit: X.E3, acc: X.E3) -> X.E3:
  match xs:
    case []: acc
    case h <> tail: index(tail,E.add(bit,bit),E.add(acc,E.mul(bit,h)))

def vars(z: B.Elements, i: Nat, mu: Nat) -> List<&2,PSC.Variable>:
  match z:
    case []: []
    case +g <> tail:
      +p = i
      +m = mu
      v: PSC.Variable = PSC.Variable{PSC.Equal{g},Bool.pick(Nat,Nat.is_le(p,m),1n,2n)}
      v <> vars(tail,Nat.sub(p,1n),m)

def finish_leaves(out: PSC.Obligation, lookup: Nat, point: B.Elements, previous: L.Masks,
  events: L.Events, +m: Nat, i: Nat, rows: List<&2,L.Row>) -> IO(L.Tape):
  match out:
    case PSC.Obligation{target,+fresh,carry,[w]}:
      masked = L.sum(L.next(fresh,L.Multiplicities{},m),L.scale(previous,carry))
      term: L.Plane = L.Plane{lookup,F.Term{w,Tensor.eq(point)}}
      IO.pure(L.Tape,L.Tape{events,Nat.add(m,List.length(&2,X.E3,fresh)),i,L.Row{[term],masked,target} <> rows})
    case _: IO.die(L.Tape,1,"NO: key-lookup-leaves")


def add_leaves(state: L.State, lookup: Nat, mu: Nat, alpha: X.E3, previous: L.Masks) -> IO(L.Tape):
  L.State{claim,+rev,tape} = state
  L.Tape{events,+m,i,rows} = tape
  # The highest variable is bound first; rev is already in logical coordinate order.
  coeff = F.sub(F.sub(alpha,F.one()),index(List.drop(&2,X.E3,rev,mu),F.one(),F.zero()))
  saved = PSC.obligation(claim,F.one(),[coeff])
  finish_leaves(saved,lookup,rev,previous,events,m,i,rows)

def leaves(pair: V.Pairing, lookup: Nat, +mu: Nat, alpha: X.E3) -> IO(L.Tape):
  V.Pairing{L.Point{+point,masks,target},t} = pair
  do IO<L.Tape>:
    s : L.State <- L.begin(t,target)
    x : L.State <- L.rounds(vars(List.reverse(&2,X.E3,point),List.length(&2,X.E3,point),mu),s)
    add_leaves(x,lookup,mu,alpha,masks)

def powers(bits: Nat, +val: X.E3) -> F.Factors:
  match bits:
    case 0n: []
    case 1n+k: F.Factor{F.one(),val} <> powers(k,E.mul(val,val))

def multiplicity(mu: Nat, d: Nat, id: Nat, count: Nat) -> L.Row:
  all = List.append(&2,F.Factor,powers(mu,small(2n)),List.replicate(F.Factor,d,F.Factor{F.one(),F.one()}))
  L.Row{[L.Plane{id,F.Term{F.one(),all}}],[],small(count)}

def complete_bits(out: L.RowsOut, +id: Nat, mu: Nat, d: Nat, real_count: Nat) -> IO(L.Tape):
  match out:
    case L.RowsOut{row,[L.Point{_,ms,target}],z,t}:
      point = Tensor.eq(List.reverse(&2,X.E3,z))
      term: L.Plane = L.Plane{id,F.Term{F.one(),point}}
      t2 = L.keep(L.keep(t,row),L.Row{[term],ms,target})
      IO.pure(L.Tape,L.keep(t2,multiplicity(mu,d,id,real_count)))
    case _: IO.die(L.Tape,1,"NO: key-lookup-bit")

def bits(zero: L.Read, id: Nat, +mu: Nat, +d: Nat, count: Nat) -> IO(L.Tape):
  match zero:
    case L.Read{[],+z,t}:
      do IO<L.Tape>:
        ok : Unit <- Header.require(Nat.is_eq(List.length(&2,X.E3,z),Nat.add(mu,d)),"NO: key-lookup-zero")
        xs : List<&2,PSC.Variable> <- V.equals(V.descending(Nat.add(mu,d),[]),z,2n)
        out : L.RowsOut <- L.shown(t,L.Point{[],[],F.zero()},xs,L.Bits{},False{})
        complete_bits(out,id,mu,d,count)
    case _: IO.die(L.Tape,1,"NO: key-lookup-zero")

def table(t: L.Tape, top: L.Point, +mu: Nat, +d: Nat, alpha: X.E3, +id: Nat, count: Nat) -> IO(L.Tape):
  do IO<L.Tape>:
    tree : V.Pairing <- V.chain(d,mu,[],False{},V.Pairing{top,t})
    leaf : L.Tape <- leaves(tree,id,mu,alpha)
    zero : L.Read <- L.take(leaf,"ZERO")
    bits(zero,id,mu,d,count)

# One pending claim for each lookup part on the matrix, before offset and padding are moved.
type Pending is Data:
  Pending{point: L.Point, part: M.Part, alpha: X.E3, lookup: Nat}
type Output is Data:
  Output{pending: List<&2,Pending>, tape: L.Tape}

def append(pair: V.Pairing, part: M.Part, alpha: X.E3, id: Nat, acc: List<&2,Pending>) -> Output:
  V.Pairing{p,t} = pair
  Output{Pending{p,part,alpha,id} <> acc,t}

def part_bits(part: M.Part) -> Nat:
  M.Part{size,_} = part
  U32.to_nat(size)


def parts(ps: List<&2,M.Part>, tops: List<&2,L.Point>, +kcol: Nat, +first: H.Bytes, +alpha: X.E3,
  +id: Nat, out: Output) -> IO(Output):
  match ps tops out:
    case Nil{} Nil{} ended: IO.pure(Output,ended)
    case Con{+part,rest} Con{top,more} Output{acc,t}:
      n = Nat.add(part_bits(part),kcol)
      do IO<Output>:
        tree : V.Pairing <- V.chain(n,0n,first,True{},V.Pairing{top,t})
        parts(rest,more,kcol,first,alpha,id,append(tree,part,alpha,id,acc))
    case _ _ _: IO.die(Output,1,"NO: key-lookup-part-count")

def after_parts(out: Output, top: L.Point, mu: Nat, d: Nat, alpha: X.E3, id: Nat, count: Nat) -> IO(Output):
  Output{pending,t} = out
  do IO<Output>:
    end : L.Tape <- table(t,top,mu,d,alpha,id,count)
    return Output{pending,end}

def joined(r: L.Read, planes: List<&2,L.Point>, roots: List<&2,L.Point>, ps: List<&2,M.Part>, kcol: Nat,
  first: H.Bytes, +alpha: X.E3, +id: Nat, +mu: Nat, d: Nat, count: Nat, previous: List<&2,Pending>) -> IO(Output):
  match r:
    case L.Read{[],+coords,t}:
      top = V.join(List.reverse(&2,L.Point,planes),Tensor.eq(coords),0n,[],F.one(),coords)
      do IO<Output>:
        ok : Unit <- Header.require(Nat.is_eq(mu,List.length(&2,X.E3,coords)),"NO: key-lookup-join")
        key : Output <- parts(ps,roots,kcol,first,alpha,id,Output{previous,t})
        after_parts(key,top,mu,d,alpha,id,count)
    case _: IO.die(Output,1,"NO: key-lookup-join")

def at_split(roots: V.Split, planes: List<&2,L.Point>, ps: List<&2,M.Part>, kcol: Nat,
  first: H.Bytes, alpha: X.E3, id: Nat, mu: Nat, d: Nat, count: Nat, prev: List<&2,Pending>) -> IO(Output):
  V.Split{tops,t} = roots
  do IO<Output>:
    j : L.Read <- L.take(t,"JOIN")
    joined(j,planes,tops,ps,kcol,first,alpha,id,mu,d,count,prev)

def at_ties(top: V.Roots, +ps: List<&2,M.Part>, kcol: Nat, first: H.Bytes, alpha: X.E3, id: Nat,
  mu: Nat, d: Nat, count: Nat, prev: List<&2,Pending>) -> IO(Output):
  V.Roots{r,planes,t} = top
  do IO<Output>:
    split : V.Split <- V.split(Nat.sub(List.length(&2,M.Part,ps),1n),V.Split{[r],t})
    at_split(split,planes,ps,kcol,first,alpha,id,mu,d,count,prev)

def lookup(r: L.Read, spec: M.Lookup, n: Nat & Nat, id: Nat, kcol: Nat, prev: List<&2,Pending>) -> IO(Output):
  match r spec n:
    case L.Read{[],[+alpha],t} M.Lookup{d,mu,live,_,_,pad,ps,first} Tuple{padding,real_count}:
      factor = power(48n,padding,F.sub(alpha,small(U32.to_nat(pad))),F.one())
      do IO<Output>:
        out : L.RowsOut <- L.shown(t,L.Point{[],[],F.zero()},[],L.FirstTie{factor},False{})
        top : V.Roots <- V.first(out,U32.to_nat(live))
        at_ties(top,ps,kcol,first,alpha,id,U32.to_nat(mu),U32.to_nat(d),real_count,prev)
    case _ _ _: IO.die(Output,1,"NO: key-lookup-alpha")

def lookup_parts(spec: M.Lookup) -> List<&2,M.Part>:
  M.Lookup{_,_,_,_,_,_,ps,_} = spec
  ps

def run(specs: List<&2,M.Lookup>, +kcol: Nat, id: Nat, out: Output) -> IO(Output):
  match specs out:
    case [] done: IO.pure(Output,done)
    case +l <> tail Output{prev,t}:
      +j = id
      do IO<Output>:
        r : L.Read <- L.take(t,"LKP")
        n : Output <- lookup(r,l,counts(lookup_parts(l),Nat.pow(2n,kcol),0n,0n),j,kcol,prev)
        run(tail,kcol,1n+j,n)
