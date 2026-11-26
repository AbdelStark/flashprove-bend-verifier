import Base
import ./header.bend as Header
import ./policy.bend as P
import ./policy_frame.bend as Fr
import ./hash_bytes.bend as H

type Forms is Data:
  Forms{q: U32, v: U32, o: U32, g: U32, u: U32, d: U32, r: U32}

def shift(k: U32, +form: U32) -> Bool:
  U32.is_le(form,2) && Fr.within(k,1,U32.add(16,U32.shln(form,3n)))

def norm(+m: U32, +k: U32) -> Bool:
  Fr.within(m,24,47) && Fr.within(k,17,32) && U32.is_ge(U32.add(k,14),m)

def rows(left: Nat, xs: Fr.Words, +forms: Forms, +layer: U32, +mask: U32, group_sh: U32, +soft_size: U32) -> IO(Fr.Words):
  match left xs:
    case 0n tail: IO.pure(Fr.Words,tail)
    case 1n+p +q <> +k <> v <> o <> g <> u <> d <> +m1 <> +k1 <> +m2 <> +k2 <> +sh <> rp <> tail:
      Forms{+fq,fv,fo,fg,fu,fd,_} = forms
      +first = U32.is_zero(U32.and(layer,mask))
      do IO<Fr.Words>:
        ok : Unit <- Header.require(shift(q,fq) && shift(k,fq) && shift(v,fv) && shift(o,fo) &&
          shift(g,fg) && shift(u,fu) && shift(d,fd), "NO: KL-shift-range")
        ok : Unit <- Header.require(U32.is_eq(q,k) || (U32.is_ge(q,16) && U32.is_ge(k,16)), "NO: KL-kq-kk")
        ok : Unit <- Header.require(norm(m1,k1) && norm(m2,k2), "NO: KL-norm")
        ok : Unit <- Header.require(U32.is_le(rp,1), "NO: KL-rp")
        ok : Unit <- Header.require(Fr.within(sh,4,12), "NO: af-policy-sh")
        ok : Unit <- Header.require(U32.is_le(soft_size,U32.shrn(16711680,U32.to_nat(U32.min(sh,12)))), "NO: af-policy-C")
        ok : Unit <- Header.require(first || U32.is_eq(sh,group_sh), "NO: unsupported parameter form: attention-shifts")
        ok : Unit <- Header.require(U32.is_le(k1,m1) && U32.is_le(k2,m2), "NO: unsupported parameter form: norm-shifts")
        rows(p,tail,forms,U32.add(layer,1),mask,sh,soft_size)
    case _ _: IO.die(Fr.Words,1,"NO: KL-length")

def moe(left: Nat, xs: Fr.Words, +forms: Forms) -> IO(Unit):
  match left xs:
    case 0n Nil{}: IO.pure(Unit,Unit{})
    case 1n+p r <> g <> u <> tail:
      Forms{_,_,_,fg,fu,_,fr} = forms
      do IO<Unit>:
        ok : Unit <- Header.require(shift(r,fr) && shift(g,fg) && shift(u,fu), "NO: KL-shift-range")
        moe(p,tail,forms)
    case _ _: IO.die(Unit,1,"NO: KL-length")

def load(+lines: P.Lines, config: String, soft_size: U32) -> IO(Fr.Words):
  do IO<Fr.Words>:
    +layers : U32 <- P.field(lines,"L")
    +ll : U32 <- P.field(lines,"ll")
    ok : Unit <- Header.require(Fr.within(ll,1,6), "NO: shape-words")
    +group : U32 = U32.shln(1,U32.to_nat(ll))
    ok : Unit <- Header.require(U32.is_ne(layers,0) && U32.is_zero(U32.and(layers,U32.sub(group,1))), "NO: shape-L")
    ok : Unit <- Header.require(U32.is_le(layers,U32.mul(28,group)), "NO: plan-groups-base")
    ne : U32 <- P.field(lines,"NE")
    +experts : U32 = Bool.pick(U32,U32.is_zero(ne),0,U32.shrn(layers,1n))
    +length : U32 = U32.add(U32.mul(13,layers),U32.mul(3,experts))
    +raw : H.Bytes <- Header.bytes(config ++ "/KL.bin",U32.add(U32.shln(length,2n),1))
    ok : Unit <- Header.require(Nat.is_eq(List.length(&2,U32,raw),Nat.mul(4n,U32.to_nat(length))), "NO: KL-length")
    q : U32 <- P.field(lines,"hq")
    v : U32 <- P.field(lines,"hv")
    o : U32 <- P.field(lines,"ho")
    g : U32 <- P.field(lines,"hgD")
    u : U32 <- P.field(lines,"huD")
    d : U32 <- P.field(lines,"hdD")
    r : U32 <- P.field(lines,"hr")
    +fm : Forms = Forms{q,v,o,g,u,d,r}
    +words : Fr.Words = H.u32s(raw)
    tail : Fr.Words <- rows(U32.to_nat(layers), words, fm, 0,U32.sub(group,1),0,soft_size)
    ok : Unit <- moe(U32.to_nat(experts),tail,fm)
    +mF : U32 <- P.field(lines,"MF")
    +kF : U32 <- P.field(lines,"KF")
    ok : Unit <- Header.require(norm(mF,kF), "NO: policy-norm-F")
    ok : Unit <- Header.require(U32.is_le(kF,mF), "NO: unsupported parameter form: norm-shifts")
    return words
