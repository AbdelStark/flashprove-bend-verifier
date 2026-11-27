import Base
import ./extension.bend as X
import ./sumcheck.bend as E
import ./fold.bend as F
import ./row_tensor.bend as Tensor
import ./base_check.bend as B
import ./policy_tables.bend as T
import ./segment_tables.bend as S
import ./key_stage_openings.bend as K
import ./key_stage_lookup.bend as KL
import ./key_stage_lookup_rows.bend as L
import ./key_stage_lookup_levels.bend as V
import ./key_stage_psc.bend as PSC
import ./hash_bytes.bend as H
import ./header.bend as Header
import ./pow2.bend as P2

# A forest leaves an evaluation on its key vector (R11.1 step 8). Each
# segment owns the linear map from its component calls to committed cells.
type Claims is Data:
  Claims{key: L.Point, alpha: X.E3, shift: X.E3, rows: List<&2,L.Row>}

def padding(calls: List<&2,S.Call>, +a: X.E3, +theta: X.E3, shift: X.E3, product: X.E3) -> X.E3:
  match calls:
    case []: product
    case S.Call{_,_,_,_,p,n} <> tail:
      +s = shift
      factor = KL.power(32n,n,F.sub(F.sub(a,s),KL.small(p)),F.one())
      padding(tail,a,theta,E.add(s,theta),E.mul(product,factor))

def padded(calls: List<&2,S.Call>, n: Nat) -> Nat:
  match calls:
    case []: n
    case S.Call{_,_,_,_,_,k} <> tail: padded(tail,Nat.add(n,k))

def last_order(+r: Nat) -> H.Bytes:
  +s = U32.from_nat(r)
  [U32.add(s,2),U32.add(s,1),s,U32.add(s,5),U32.add(s,4),U32.add(s,3),U32.add(s,8),U32.add(s,7),U32.add(s,6)]

# A non-power-of-two table repeats the last call through the unused padded
# selectors. The public plane matrix itself only has the actual calls.
def sum_last(+v: X.E3, n: Nat, at: Nat, +factors: F.Factors, sum: X.E3) -> X.E3:
  match n:
    case 0n: sum
    case 1n+left:
      +i = at
      sum_last(v,left,1n+i,factors,E.add(sum,E.mul(v,Tensor.entry(factors,i,F.one()))))

def cells(calls: List<&2,S.Call>, +table_point: B.Elements, +selectors: F.Factors, +tables: T.Tables,
  +theta: X.E3, shift: X.E3, index: Nat, remaining: Nat, sum: X.E3, last: X.E3) -> X.E3:
  match calls:
    case []: sum_last(last,remaining,index,selectors,sum)
    case S.Call{k,bits,_,_,_,_} <> tail:
      +i = index
      +s = shift
      +v = E.add(s,S.value(k,List.take(&2,X.E3,table_point,bits),tables))
      cells(tail,table_point,selectors,tables,theta,E.add(s,theta),1n+i,Nat.sub(remaining,1n),
        E.add(sum,E.mul(Tensor.entry(selectors,i,F.one()),v)),v)

def leaf_row(s: L.State, top: L.Point, +shape: S.Forest, a: X.E3, theta: X.E3, id: Nat, tables: T.Tables) -> IO(L.Tape):
  L.State{state,+point,tape} = s
  L.Tape{events,m,i,rows} = tape
  L.Point{_,ms,_} = top
  S.Forest{_,_,_,+c,calls} = shape
  +cp = List.drop(&2,X.E3,point,5n)
  v = cells(calls,List.drop(&2,X.E3,cp,c),Tensor.eq(List.take(&2,X.E3,cp,c)),tables,
    theta,F.zero(),0n,P2.pow2(c),F.zero(),F.zero())
  KL.finish_leaves(PSC.obligation(state,F.one(),[F.sub(F.sub(a,F.one()),v)]),id,point,ms,events,m,i,rows)

def leaves(pair: V.Pairing, +shape: S.Forest, a: X.E3, theta: X.E3, id: Nat, tables: T.Tables) -> IO(L.Tape):
  V.Pairing{+top,t} = pair
  L.Point{+at,_,target} = top
  do IO<L.Tape>:
    s : L.State <- L.begin(t,target)
    q : L.State <- L.rounds(KL.vars(List.reverse(&2,X.E3,at),List.length(&2,X.E3,at),5n),s)
    leaf_row(q,top,shape,a,theta,id,tables)

def complete(t: L.Tape, key: L.Point, a: X.E3, theta: X.E3, stop: Nat) -> IO(Claims):
  match t:
    # R11.1 lists the mask-only bits row before the three plane rows.
    case L.Tape{[],m,0n,count <> shown <> bits <> leaves <> earlier}:
      do IO<Claims>:
        ok : Unit <- Header.require(Nat.is_eq(m,stop),"NO: segment-forest-slots")
        return Claims{key,a,theta,List.reverse(&2,L.Row,count <> shown <> leaves <> bits <> earlier)}
    case _: IO.die(Claims,1,"NO: segment-forest-end")

def table(key: V.Pairing, plane: L.Point, +shape: S.Forest, +a: X.E3, +theta: X.E3,
  +id: Nat, tables: T.Tables, stop: Nat) -> IO(Claims):
  V.Pairing{end,t} = key
  S.Forest{n,k,r,c,calls} = shape
  +d = Nat.add(k,c)
  real = Nat.sub(P2.pow2(Nat.add(n,r)),padded(calls,0n))
  do IO<Claims>:
    below : V.Pairing <- V.chain(d,5n,[],False{},V.Pairing{plane,t})
    l : L.Tape <- leaves(below,shape,a,theta,id,tables)
    z : L.Read <- L.take(l,"ZERO")
    done : L.Tape <- KL.bits(z,id,5n,d,real)
    complete(done,end,a,theta,stop)

def keys(j: L.Read, top: L.Point, planes: List<&2,L.Point>, +shape: S.Forest,
  a: X.E3, theta: X.E3, id: Nat, tables: T.Tables, stop: Nat) -> IO(Claims):
  match j:
    case L.Read{[],+zs,t}:
      S.Forest{n,_,+r,_,_} = shape
      plane = V.join(List.reverse(&2,L.Point,planes),Tensor.eq(zs),0n,[],F.one(),zs)
      do IO<Claims>:
        ok : Unit <- Header.require(Nat.is_eq(List.length(&2,X.E3,zs),5n),"NO: segment-forest-planes")
        key : V.Pairing <- V.chain(Nat.add(n,r),0n,last_order(r),False{},V.Pairing{top,t})
        table(key,plane,shape,a,theta,id,tables,stop)
    case _: IO.die(Claims,1,"NO: segment-forest-join")

def roots(r: V.Roots, shape: S.Forest, a: X.E3, theta: X.E3, id: Nat, tables: T.Tables, stop: Nat) -> IO(Claims):
  V.Roots{root,planes,t} = r
  do IO<Claims>:
    j : L.Read <- L.take(t,"JOIN")
    keys(j,root,planes,shape,a,theta,id,tables,stop)

def alpha(draw: L.Read, +shape: S.Forest, +theta: X.E3, id: Nat, tables: T.Tables, stop: Nat) -> IO(Claims):
  match draw:
    case L.Read{[],[+a],t}:
      S.Forest{_,_,_,_,calls} = shape
      factor = padding(calls,a,theta,F.zero(),F.one())
      do IO<Claims>:
        out : L.RowsOut <- L.shown(t,L.Point{[],[],F.zero()},[],L.FirstTie{factor},False{})
        top : V.Roots <- V.first(out,32n)
        roots(top,shape,a,theta,id,tables,stop)
    case _: IO.die(Claims,1,"NO: segment-forest-alpha")

def shifted(r: L.Read, shape: S.Forest, id: Nat, tables: T.Tables, stop: Nat) -> IO(Claims):
  match r:
    case L.Read{[],[theta],t}:
      do IO<Claims>:
        a : L.Read <- L.take(t,"LKP")
        alpha(a,shape,theta,id,tables,stop)
    case _: IO.die(Claims,1,"NO: segment-forest-shift")

def compute(t: L.Tape, shape: S.Forest, id: Nat, tables: T.Tables, stop: Nat) -> IO(Claims):
  do IO<Claims>:
    r : L.Read <- L.take(t,"LKP shift")
    shifted(r,shape,id,tables,stop)
