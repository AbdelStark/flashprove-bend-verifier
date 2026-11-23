# 05 - Segment sub-proofs: feed-forward (11.2), attention (11.3), output head (11.4), and the integer model

> Status: frozen
> Recovered working notes, 2026-11-23. Upstream excerpts from FlashProve, Copyright 2026 Anthropic PBC, Apache-2.0.

Research digest for the Bend 2 re-implementation of the FlashProve verifier.
Upstream: FlashProve 0.16.0-rc.26, commit 9e2bdd8, read-only at
`<scratchpad>/upstream/FlashProve`.

## 0. Sources, citation tags, status of the text

All paths are relative to the upstream root. A citation is `tag:LINE` or `tag:FROM-TO`.

| tag | file | read |
|---|---|---|
| `model` | `docs/model.md` | whole (580 lines) |
| `11.2` | `docs/format/11-2-feed-forward-segment.md` | whole (1186 lines) |
| `11.3` | `docs/format/11-3-attention-segment.md` | whole (1051 lines) |
| `11.4` | `docs/format/11-4-output-head.md` | whole (948 lines) |
| `11` | `docs/format/11-sub-proofs.md` | whole |
| `README` | `docs/format/README.md` | whole |
| `11.1` | `docs/format/11-1-machinery.md` | only for terms (lines 1-376, 378-1000, 1231-1300, 1359-1433) |
| `FORMAT` | `docs/format/FORMAT.md` | only 12.2, 12.4, 12.5, 13.4 steps 5-7, 13.9 |
| `10` | `docs/format/10-proof-file.md` | only R14.3, R14.4, R14.5, R14.8 |
| `08` | `docs/format/08-parameters.md` | only 8.6 |
| `pol-full` | `examples/full-size/config/policy.txt` | whole |
| `pol-small` | `examples/accepted-proof/config/policy.txt` | whole |

Facts about the text itself that the spec must carry:

- Precedence: on bytes, hashed strings, order and tests, `FORMAT.md` with the files of its sections 8 to 11 "takes precedence over every other page of the repository" [README:7-9]. So where `model` and `11.x` differ, `11.x` decides.
- 11.2-11.4 are "written from the programs' source" [11:8; 11.2:6; 11.3:6; 11.4:6]. They give no argument that the claims imply the integer function, and none that an equation in the field holds over the integers [11:26-29; 11.2:254-256, 1185-1186; 11.3:239-241; 11.4:197-199]. Every "what this enforces" sentence below that is not followed by a citation is MY READING and is marked `(reading)`.
- **No numbered R-rule is defined in 11.2-11.4** (checked by search: zero `**Rn.m**` definitions in the three files). They only reference rules defined elsewhere (list in section 8). Their own identifiers are: step numbers, claim-group numbers, computation-line numbers, condition names and rejection names. The spec needs its own rule IDs for them.
- `examples/full-size/config/policy.txt` is byte-identical to `prover/examples/target_full_f2/policy.txt` (checked with `diff`), which is the configuration of all three worked examples [11.2:226-227; 11.3:205-206; 11.4:175-176]. `examples/accepted-proof/config/policy.txt` differs from `prover/examples/target_small_f2/policy.txt` in one line only: `MF 43` instead of `MF 44` (checked with `diff`); its `KL.bin` differs too.
- Counts in section 7 come from a script of mine, `<scratchpad>/scripts/seg_counts.py`, which implements the docs' formulas. Its self-check reproduces every number of the three full-size worked examples and the three per-segment column counts of FORMAT 13.9. Small-example numbers have no worked example upstream; they are derived, and validated only against the file's own `iota_*`, `iotaA_0`, `iotaH_*` lines.

Name clashes that will bite (all are literal names upstream):

| name | meanings |
|---|---|
| group | (1) group of Lam layers, "group g"; (2) a segment's group of oracle messages [11.3:11-14]; (3) a numbered group of claims; (4) in `layout.txt` one oracle message [FORMAT:1754-1757]; (5) an index group of a weight unit (11.5) |
| `sh` | scale-file word of a layer = attention's softmax shift, 4..12 [11.3:56, 962]; ALSO the policy line `sh` (7 or 8) = the head's margin digit shift [11.4:165, 226]. Small example: scale-file sh = 12 in all layers (read from `KL.bin`), policy line `sh 8` [pol-small:127] |
| EX | in `model` the softmax table [model:136]; in 11.4 the head's table of exponentials, a different table made by an integer recurrence [11.4:146-148]. 11.3 calls the softmax table Tt [11.3:275] |
| `S`, `s`, S, S0, s0 | line `S` = softmax scale exponent [model:67]; line `s` = exponent of the logits, in no equation [11.4:856-857]; S = size sum of the panels [11.2:111]; S0 = a sumcheck's public summand; s0 = lowest bit of sig [11.4:247] |
| `C`, `theta`, `F`, `G`, `V`, `D`, `H` | policy/shape lines, and also letters of formulas and names of calls' segments [11.2:280-283; 11.4:226] |
| `KF`, KF_c | line of the final norm; key form of call c [11.4:225] |
| XL | number of limbs of a stream value [11.2:23-24]; also the reading XL(p; Tn; ..) of 11.3 [11.3:611] |
| lam | a layer's number inside its group [11.2:287]; lam_t[v] the logits [11.4:243] |
| a call's segment | a named group of a call's key columns, NOT a segment of a request [11.2:165-167] |

## 1. The integer model in brief (only what the verifier's checks depend on)

### 1.1 Notation and number formats

- Every quantity is an unbounded integer; floor rounds to minus infinity; a mod b is in 0..b-1 [model:32-33].
- `rq(a, k) = floor((a + 2^(k-1)) / 2^k)`, k >= 1: divide by 2^k, round to nearest, ties up [model:35]. 11.2 writes it `rsh(A, k)` [11.2:297].
- `clamp(a; b) = min(max(a, -b), b)`; `isqrt(a)` = largest r with r^2 <= a; `argmax` = the least index of the maximum; `low8(a) = ((a + 128) mod 256) - 128` [model:36-39].
- Clamp width: activations a, m, v, aF and queries and keys are clamped to 12 bits with sign, `clamp(x; 2047)` (cw = 12, "a constant of the format") [model:46-47]; source constant `CLAMP` = 2047 [11.2:1011].
- Weight matrix convention: W[k][j], input index first; (x W)[j] = sum_k x[k] W[k][j] [model:42-44]. In a vector of heads, entry c of head h is entry h dh + c [model:93-94].
- Committed weights: every entry outside Emb is in -4096..4095; an entry of Emb is a number of four signed bytes in base 256 [model:96-98]. No bias vectors, no norm gains [model:81-82].
- Limbs: the provers write values in signed bytes ("limbs"); two limbs end at 32,639, five at 547,599,908,735 [model:309-310]. In the proof a tensor value is `sum over lb of 256^lb * cell` with cells of either sign [11.2:403-404].

### 1.2 Shape parameters and where each comes from

All are lines of the parameter file `policy.txt`, one "name value" per line; a two-line value `x_lo`, `x_hi` is x_lo + 2^32 x_hi [model:53-56]. Order of the model's lines: [08:871-883].

| symbol | line | meaning | full-size [pol-full] | small [pol-small] |
|---|---|---|---|---|
| T = 2^lt | `lt` | token positions (the window) [model:60] | lt 10, T 1024 [:34] | lt 6, T 64 [:34] |
| L | `L` | layers [model:61] | 48 [:35] | 8 [:35] |
| Lam = 2^ll | `ll` | layers per group [11.2:11] | ll 2, Lam 4 [:36] | ll 2, Lam 4 [:36] |
| d | `d` | residual width [model:61] | 5120 [:37] | 512 [:37] |
| n_h | `H` | query heads [model:62] | 40 [:38] | 4 [:38] |
| n_g | `G` | key-value heads, divides n_h [model:62] | 8 [:39] | 2 [:39] |
| dh | `dh` | head dimension; dq = n_h dh, dkv = n_g dh [model:63] | 128 [:40] | 128 [:40] |
| f, fe | `f`, `fe` | hidden units of a dense layer / of one expert, f = 2 fe if NE > 0 [model:64] | 16384, 8192 [:41-42] | 1024, 512 [:41-42] |
| NE | `NE` | routed experts [model:65] | 128 [:43] | 4 [:43] |
| V | `V` | vocabulary [model:65] | 202048 [:44] | 512 [:44] |
| cs | `cs` | scale exponent of the rotary tables; only 12 admitted [model:66; 11.2:1038] | 12 [:49] | 12 [:49] |
| theta0 | `theta0_lo/hi` | rotary base [model:66] | 500000 [:50-51] | 10000 [:50-51] |
| expS, rx | `S`, `rx` | softmax table scale and step exponents [model:67] | 12, 8 [:95-96] | 12, 8 [:95-96] |
| eg, smax | `eg`, `smax` | SiLU key step and bound; omitted means 8 and 4095 [model:68] | omitted | omitted |
| eps1, eps2, epsF | `eps1_lo/hi` .. | norm regularizers [model:116-118] | 53687 each [:45-48, 107-108] | 1 each [:45-48, 107-108] |
| MF, KF | `MF`, `KF` | final norm exponents [model:116] | 44, 30 [:105-106] | 43, 30 [:105-106] |
| XL | `xl 5` | 5 limbs per stream value (absent: 4) [11.2:23-24] | 5 [:134] | 5 [:133] |
| rcl, gcl | `rcl 1`, `gcl 1` | router's clamp, gate's clamp [model:73-74] | 1, 1 [:132-133] | 1, 1 [:131-132] |
| lkW | last number of line `table` [11.1:204] | column bits of the stored table | 18 [:32] | 11 [:32] |

- If NE > 0 the odd layers are mixture-of-experts layers and the even layers dense; if NE = 0 all are dense [model:70-71].
- `ut 1` is the only admitted value [model:75-77; 11.2:1038 `policy-ut`]. `wb_emb 21` is compared with 21 and used in no test [model:100-101].
- Scale file `KL.bin`: unsigned little-endian 32-bit words; 13 per layer in the order kq, kk, kv, ko, kg, ku, kd, M1, K1, M2, K2, sh, rp (word 13 l + n); then for each mixture-of-experts layer kr, kgR, kuR (word 13 L + 3 floor(l/2) + n) [model:103-114; 11.2:1005]. rp = 1 if the layer applies the rotary encoding; in Maverick rp = 0 where l mod 4 = 3 [model:110-111]. Read from the two example `KL.bin` files with my script: full-size has sh = 8 in all 48 layers and rp = 1,1,1,0 repeating; small has sh = 12 in all 8 layers, same rp pattern; both have only 2 distinct layer records.

### 1.3 The exact sequence of operations

Per position t, layer l (scales are layer l's) [model:186-214, 225-264]:

1. **Norm 1.** a_t = N(x_t; M1, K1, eps1), with N(x; M, K, eps): Vx = sum_k x[k]^2; sigma = isqrt(Vx + eps); Rc = floor((2^M + floor(sigma/2)) / sigma); w[k] = rq(x[k] Rc, K); nr[k] = clamp(w[k]; 2047) [model:170-177]. sigma is the root of the SUM of squares, not the mean (sqrt(d) is folded into weights and scales) [model:181-182].
2. **Queries and keys with the rotary scheme.** A[j] = (a_t Wq)[j] for j < dq, A[dq + j] = (a_t Wk)[j] for j < dkv. In each head, for pair i < dh/2 with entries A0 = entry 2i, A1 = entry 2i+1: p0 = C A0 - S A1, p1 = S A0 + C A1, where C = C(t, i), S = S(t, i) if rp = 1, and C = 2^cs, S = 0 if rp = 0. qw = rq(p, kq), kw = rq(p, kk); q = clamp(qw; 2047), k = clamp(kw; 2047) [model:189-198]. kq and kk also remove the factor 2^cs [model:106-107].
3. **Values.** vw[j] = rq((a_t Wv)[j], kv); v = clamp(vw; 2047) [model:199-200].
4. **Causal attention** (query head h reads key-value head g = floor(h / (n_h/n_g)); j <= i) [model:201-210]:
   s_ij = sum_c q_i[h][c] k_j[g][c]; m_i = max_j s_ij; u_ij = floor((m_i - s_ij) / 2^sh); e_ij = EX[u_ij] if u_ij < u0 else 0; Z_i = sum_j e_ij; acc_i[c] = sum_j e_ij v_j[g][c]; o_i[h][c] = floor((2 acc_i[c] + Z_i) / (2 Z_i)). Z_i >= EX[0] > 0 [model:212].
5. **Output projection, residual.** ad[k] = rq((o_t Wo)[k], ko); x'_t = x_t + ad. Neither o nor ad is clamped [model:213-214].
6. **Norm 2.** m = N(x'; M2, K2, eps2) [model:225-226].
7. **A block of hidden units** (z, G, U, k_g, k_u) [model:228-238]: gw = rq((z G)[j], k_g); g0 = low8(gw); gh = (gw - g0)/256; gc = clamp(gh; 127); key = 256 gc + g0; s = Ts[key]; u = rq((z U)[j], k_u).
8. **Dense layer.** one block of f units on (m, Wg, Wu, kg, ku); ad[k] = rq(sum_{j<f} s[j] u[j] Wd[j][k], kd); x'' = x' + ad [model:240-242].
9. **Mixture-of-experts layer** [model:244-264]: router lw = rq((m Wr)[e], kr); ly = floor(lw/8), l3 = lw mod 8, lr[e] = 8 clamp(ly; 2047) + l3; e* = argmax of lr (ties to the lowest index); sc = Sig[lr[e*]]; xr[k] = rq(sc m[k], 16) (the scale multiplies the routed expert's INPUT); shared expert = block of fe units on (m, Wg, Wu, kg, ku); routed expert = block of fe units on (xr, Wgr_e*, Wur_e*, kgR, kuR); ad[k] = rq(sum_{j<fe} (s[j] u[j] Wd[j][k] + s[fe+j] u[fe+j] Wdr_e*[j][k]), kd) (two sums added before the ONE shift); x'' = x' + ad.

Whole model [model:268-274]: x^0_t = Emb[tok_t]; x^(l+1) = layer l on x^l; aF_t = N(x^L_t; MF, KF, epsF) at every t; lam_t = aF_t Wh (V logits); Model(tok) = y = argmax of lam_(T-1), ties to the lowest token id.

Logit gap (not a value of Model, used by the statement) [model:276-281]: with tok_T = y, gap_t = max over v < V of (lam_t[v] - lam_t[tok_(t+1)] + [v < tok_(t+1)]); it is 0 exactly if tok_(t+1) is the argmax of lam_t.

Window and padding: Model takes exactly T tokens; padding counts like any other tokens; no padding token is fixed in the model (the vLLM integration uses id 0) [model:283-286]. Causality: every value at position t depends only on tok_0..tok_t [model:288-290].

### 1.4 Public tables (the only non-integer inputs)

Each entry is a fixed sequence of IEEE 754 float64 operations, each rounded once, with correctly rounded exp, cos, sin, pow [model:125-128]. rha = round half away from zero; rne = round half to even [model:130-132].

| table | definition | used by |
|---|---|---|
| rotary C, S | b = (-2i)/dh; w = pow(theta0, b); x = t*w; C(t,i) = rha(2^cs cos(x)), S(t,i) = rha(2^cs sin(x)), t < T, i < dh/2 [model:134-135] | 11.2 weight-claim factor `rot` |
| softmax EX (11.3: Tt) | EX[u] = rne(2^expS exp(-u / 2^rx)); u0 = least u with EX[u] = 0; table ends at u0 - 1 [model:136-137] | 11.3 table `KFD` |
| SiLU Ts | keys c = -32768..32767; c' = min(max(c, -64*2^eg), 64*2^eg - 1); z = c'/2^eg; g = 1 + exp(-z); s = z/g; Ts[c] = clamp(rha(64 s); smax) [model:138-139] | 11.2 table FL |
| sigmoid Sig | g = 1 + exp(-c/256); q = 4096/g; Sig[c] = 16 rha(q); read only at -16384..16383 [model:140-141] | 11.2 table FS |

- Ts is what the float64 steps give, NOT the rounded real function (1,744 entries differ by one unit at eg 8, smax 4095) [model:143-145].
- Digests `tsilu`, `tsig`, `trope`, `texp` (eight lines each): hash the 32-bit words as little-endian bytes with BLAKE2b (64-byte output) with the high half of the byte counter set to 72 + 2^32 n; first 32 bytes read as eight little-endian words [model:154-160]. Word lists: `tsilu` = Ts[c] + 4096 for all keys in increasing order; `tsig` = Sig[c] for c = -16384..16383 then clamp(r;127)+128 for r = -16384..16383 (with `gcl`); `trope` = all of C as C(t,i)+4096 at index t dh/2 + i, then all of S; `texp` = EX[0..u0-1] [model:162-166]. Either all 32 digest lines are present or none; if present a verifier rejects unless each digest matches [11.1:341-343]. Both examples have all 32 [pol-full:135-166; pol-small:134-165].
- "A second verifier computes the four tables to the bit as the programs do, or takes them as data" [11.1:339-340].

### 1.5 Which non-linearities the proof handles by table lookup

(Mapping model -> proof names; the lookups are detailed in sections 3-5.)

| model step | proof mechanism | where |
|---|---|---|
| every rq(.., k) | quotient + remainder committed, remainder digits in range tables R16/R8 ("rounding site") | [11.2:379-385] |
| clamp(.; 2047) of norm outputs, q, k, v, aF | table FC (the clamp), calls' segments CN1, CN2, CQK, CV, CNF | [11.2:191-193, 622-624; 11.4:543] |
| isqrt and the reciprocal Rc | a row of byte digits per norm (ROW, R8) + linear "lines" + two product sumchecks; no table of the function | [11.2:544-576, 903-922] |
| SiLU gate Ts | table FL, call's segment F | [11.2:197, 625] |
| gate clamp gc = clamp(gh;127) | second half of table FS, call's segment CG (`gcl 1`) | [11.2:196, 216-217, 627] |
| router clamp and split lw = 8 ly + l3 | FC via CLR, R8 via L3 (`rcl 1`) | [11.2:189, 194, 635-636] |
| router argmax e* | one-hot selector `sel` + range keys DD, SEL, LT | [11.2:367-369, 631-633] |
| sigmoid Sig | table FS, call's segment MR | [11.2:195, 634] |
| attention max m_i | committed Mx + committed index bits ibit + sumchecks SF, SD, HB + range key IX | [11.3:314-315, 436, 766-784] |
| softmax weight EX[u] and the floor by 2^sh | tables `KR` and `KFD` | [11.3:430-433, 452-455] |
| attention's rounded division | two remainders in three bytes each: range table R16 (WL) and table `WH` | [11.3:434-435, 456] |
| final argmax / logit gap / cost | margins in three digits (HD0, HD1 R16; HD2 R8) + table FE (HE0, HE1) + four policy equations | [11.4:270-289, 539-545, 661-668] |

### 1.6 Range conditions and parameter limits the verifier relies on

- Model is a partial function, defined where conditions 1-8 hold at all T positions, all layers, all 2L + 1 norms [model:294-296]; table of conditions [model:298-307]. The provers accept narrower ranges; between the two the request gets the response `failed` [model:309-312].
- The verifier refuses a parameter file unless every norm has 24 <= M <= 47, 17 <= K <= 32, K >= M - 14 [model:324-325; 11.2:1057 `KL-norm`; 11.4:731 `policy-norm-F`]. K > M is admitted by the tests but is outside the standard parameter form and no call under it ends with `YES` [model:325-327].
- A parameter file with lt + expS + 1 > 24 is rejected (attention's division remainder is written in three bytes) [model:312-314; 11.3:959].
- Lines that change the function: `xl 5`, `gcl 1`, `rcl 1`, `eg`, `smax` [model:335-340].
- Naming map model -> 11.x: a_t = `an`, m = `mn`, w[k] = `aw`/`mw`, sigma = sig, Rc = R, qw/kw = `qkw`, k = `kx`, gw = `gi` (or `g0` + 256 `gh`), s = `sl`, u = `up`, m_i = Mx(i), u_ij = t, e_ij = ew(i,j), Z_i = Zd(i), aF = act, gap as in 12.5 [11.2:322-377; 11.3:312-323; 11.4:257-274].

## 2. Segment kinds and how a run is cut into segments

- A proof's first chain "walks the model segment by segment" (R14.4); the sub-proof of a segment is what is placed between the frame's rounds of that segment [11:5-8].
- **Order:** G_0, A_0, G_1, A_1, .., H. G_g = feed-forward segment of the layers of group g, A_g = attention segment of that group, H = output head [11:17-19; FORMAT:1735-1737]. Outside the segments a model's sub-proofs send nothing (R14.4 (e)) [11:19-20].
- **Groups of layers:** the L layers are cut into groups of Lam = 2^ll neighbouring layers [11.2:10-12]; NG = L / Lam [11.3:20-21]. Number of segments = 2 NG + 1: 25 at full size (FORMAT 13.9 states "25 segments" [FORMAT:2497-2498]), 5 for the small example (derived).
- **Identifiers** in the item `links' identifiers` (R14.3): 1 + g for G_g [11.2:12-13]; 2 + NG + g for A_g [11.3:19-21]; 1 + NG for H [11.4:21-22]; all three in [FORMAT:1737-1738].
- **What each kind is about.**
  - G_g: everything in the group's layers EXCEPT the attention function: the two norms of each layer; the projections to queries, keys and values with the rotary tables; the projection of attention's output; the router; the gated feed-forward block with shared and routed experts; the residual stream from the group's input to its output. G_0 also: the first residual stream is the embedding of the request's tokens [11.2:13-20].
  - A_g: that o is the integer attention function of q, kx, v with the causal mask [11.3:25-28]. It "reads no weights of the model, and it leaves no row on the stored table" [11.3:38]. It is never the first and never the last segment of a chain [11.3:17-19].
  - H: the final norm at every position, the product of the normalized stream with the head's weights, and the relation between the logits and the request's tokens that the acceptance policy states [11.4:11-14].
- **Hand-over between consecutive segments is by committed arrays, never by a scalar claim:**
  - qa (tensors q, kx, v, o of all Lam layers) is committed by G_g at moment 0 and read by A_g [11.2:57]; it is "kept up to this segment and is sent again in this segment's first prover's message (R14.4)" [11.3:110-111].
  - xbO of G_g (the stream leaving the group) is the xbI of G_(g+1): "From group 1 on, xbI is not committed by this segment" [11.2:61-63]; and it is the xbL of H for the last group [11.4:48-49].
  - So G_g fixes q, kx, v AND o before A_g runs; A_g proves the relation among them afterwards. The feed-forward no-overflow condition for site `o` relies on a bound on o that only the attention sub-proof is "meant to show" [11.2:1068-1070; 11.3:1003-1010].
  - In both example `layout.txt` files a feed-forward segment has five oracle-message lines: moment 1 class `N`, moment 1 class `B` life 1, moment 1 class `B` life 2, moment 2 class `W`, moment 3 class `N`; attention and head have three (`N`, `W`, `N`) (my count of the group's lines; grammar at [FORMAT:1754-1764]). Reading: `B` life 1 = qa (read one segment later), `B` life 2 = xbO (read two segments later) `(reading)`.
- **Every segment has the same skeleton:** three moments (moment 0: packed matrices `M<mu>`; moment 1: `U3`; moment 2: `ZZ`, `BZ`) [FORMAT:1744-1750; 11.2:55-59; 11.3:94-102; 11.4:42-46]; two lookups (its own call list, and the smallness test's lookup on the digits) [11.1:126-127]; one smallness test; a last `BAT-sigma` that samples chi, with n = NCm + Q [11.1:312-314]; then the frame closes it with `BAT`, `FOLD epsilon`, `FOLD round` [10:191-196].
- **Where claims go:** every check on content becomes a claim (an affine form that must be 0); claim number i gets chi^i; the sum is ONE equation per segment, which the frame tests with the segment's group of oracle messages [11.1:42-50, 502-532]. Claims on the committed weights (G_g and H only) are first merged into one row on the stored table; `pending rows` = NG + 1 [11.2:20-21; 11.4:19-21; FORMAT:1742-1743].
- The positions of a segment's own group are sampled in the `LOC` of the NEXT segment [11.3:176-178; 10:183-187].

## 3. Feed-forward segment G_g (11.2)

### 3.1 Sizes

From the parameter file: lt, L, ll, d, H, G, dh, f, fe, NE, la, `xl`, lkW; nmin; tau; matrix sizes lmaf, NAf, lmad, NAd, lmar, lmb, lmq, lmx; digit forms hq, hv, ho, hgD, huD, hdD, hr [11.2:23-27].
Derived [11.2:27-32]: T = 2^lt; Lam = 2^ll; LamM = Lam/2 with routed experts else 0; NI = 2 Lam (norms of the group); lNI = ll + 1; lPd, lPf, lfe = clog2 of d, f, fe; ls = la - lt; with five limbs NS = 2 XL - 1 = 9, NPr = 7, NO = 4, NR = 99 (four limbs: 7, 3, 3, 74); E0 = 1 in group 0 else 0.
Also [11.2:294-296]: dq = H dh (must equal d), dkv = G dh, nqk = dq + dkv, 2^ldh = dh, Pd = 2^lPd, Pf = 2^lPf, le = clog2(NE), lift(k) = 16 - k if k < 16 else 0.

### 3.2 Oracle messages: matrices, tensors, cells

Matrices of cells, committed in packed form (three cell rows per element of F, radix 2^20 [11.1:220-223, 263-264]) as arrays `M<mu>` [11.2:34-46]:

| mu | matrix | holds | cell rows | columns per part (n cells per token) |
|---|---|---|---|---|
| 0..NAf-1 | af (NAf parts) | most intermediate values | 2^lmaf each | n = 6 Lam f + (hgD+huD) Lam f + XL (2 Lam - 1) d + (8+ho+hdD) Lam d + (2+hq) Lam (H+G) dh + (2+hv) Lam G dh, + 2 Lam f with `gcl 1` |
| then NAd | ad (NAd parts) | norms' clamped outputs, routed experts' input | 2^lmad | n = 4 Lam d + 2 LamM d |
| then 1 | ar | router's values, norms' rows of digits | 2^lmar | n = 2 Lam NR + (3+hr) LamM NE + 3 LamM, + 3 LamM NE with `rcl 1` |
| then 1 | b | planes of the lookup's multiplicities | 2^lmb | NC 2^(kT + 5 - lmb) |
| then 1 | qa | q, kx, v, o | 2^lmq | n = 4 Lam (H+G) dh |
| then 1 | xbO | stream leaving the group | 2^lmx | n = XL d |
| last | xbI | stream entering the group | 2^lmx | n = XL d |

A matrix in P parts of 2^lm rows holding n cells per token has ceil(n / (P 2^(lm - lt))) columns per part [11.2:48-52].

Moments [11.2:55-59]: moment 0 = af, ad, ar, b, and in group 0 xbI (not read by another segment), then qa, xbO (read by another segment); moment 1 = `U3`; moment 2 = `ZZ`, `BZ`.

Features and tensors [11.2:389-405]: a feature is a run of T cells, one per token. With fr = 2^(lm - lt) and k columns per part, feature ft is in part floor(ft / (k fr)), column floor(ft / fr) mod k, cell row (ft mod fr) T + t. A tensor X has nl limbs, cnt instances, J features per instance, first feature OFF_X = sum of nl cnt J over the tensors before it in the same matrix; `feat(X, lb, ix, j) = OFF_X + (lb cnt_X + ix) J_X + j`; value X(ix, j, t) = sum_lb 256^lb cell.

Tensor list, in matrix order [11.2:407-440]:

| matrix | tensors in order (nl, cnt, J) |
|---|---|
| af | with `gcl 1`: `g0` (1, Lam, f), `gc` (1, Lam, f); without: `gi` (2, Lam, f). Then `sl` (2, Lam, f); `up` (2, Lam, f); `rg` (hgD, Lam, f); `ru` (huD, Lam, f); `xs` (XL, 2 Lam - 1, d), instance ix = stream str_(ix+1); `ro` (ho, Lam, d); `rd` (hdD, Lam, d); `aw` (2, Lam, d); `ra` (2, Lam, d); `mw` (2, Lam, d); `rm` (2, Lam, d); `qkw` (2, Lam, nqk); `rqk` (hq, Lam, nqk); `vw` (2, Lam, dkv); `rv` (hv, Lam, dkv); with `gcl 1`: `gh` (2, Lam, f) |
| ad | `an` (2, Lam, d); `mn` (2, Lam, d); with routed experts `xr` (2, LamM, d) |
| ar | with routed experts: `lr` (2, LamM, NE); `rl` (hr, LamM, NE); `sel` (1, LamM, NE); `sc` (3, LamM, 1). Then `row` (1, 2 Lam, NR). With `rcl 1`: `ly` (2, LamM, NE), `l3` (1, LamM, NE) |
| qa | `q` (2, Lam, dq); `kx` (2, Lam, dkv); `v` (2, Lam, dkv); `o` (2, Lam, dq) |
| xbI; xbO | str_0; str_(2 Lam): (XL, 1, d), OFF = 0 |

A tensor with nl = 0 is absent [11.2:398]. Features after the last tensor belong to no tensor and get coefficient 0 in every claim [11.2:404-405]. A verifier rejects unless 2^ls divides d, f, dkv, nqk (and fe), and unless lmaf, lmq, lmx >= la [11.2:444-446].

### 3.3 The integer relations ("What the segment computes", lines 1-21)

Streams: 2 Lam + 1 streams str_sg of d integers per token; str_(2 lam) enters layer lam, str_(2 lam + 1) is after its attention block, str_(2 lam + 2) after its feed-forward block; if g = 0, str_0(j, t) = Wm_12(tok_t, j) [11.2:316-320]. Wm_X = committed weight of the unit of kind X (11.5) [11.2:305].

| line | relation | cite |
|---|---|---|
| 1 | Vsq_i(t) = sum_{j<d} str_i(j,t)^2 | [11.2:324] |
| 2 | sig_i(t) = floor(sqrt(Vsq_i(t) + eps(i))) | [11.2:325] |
| 3 | R_i(t) = floor((2^M(i) + floor(sig_i/2)) / sig_i) | [11.2:326] |
| 4 | wide output rsh(str_i(j,t) R_i(t), K(i)): `aw` (n = 0), `mw` (n = 1) | [11.2:327-328] |
| 5 | `an` = clamp(`aw`, 2047), `mn` = clamp(`mw`, 2047) | [11.2:329] |
| 6 | pr(hd, ch, t) = sum_{k2<d} Wm_0(hd, ch, k2) `an`(lam, k2, t); H query heads first, then G key heads | [11.2:331-334] |
| 7 | Aqk(hd, 2pa, t) = Co pr(hd, 2pa, t) - Si pr(hd, 2pa+1, t); Aqk(hd, 2pa+1, t) = Si pr(hd, 2pa, t) + Co pr(hd, 2pa+1, t) | [11.2:335-337] |
| 8 | `qkw`(lam, x, t) = rsh(Aqk, kq) for x < dq; rsh(Aqk, kk) for dq <= x < nqk | [11.2:338-339] |
| 9 | `q` = clamp(`qkw`, 2047) for x < dq; `kx`(lam, x - dq, t) = clamp(`qkw`, 2047) for x >= dq | [11.2:340-341] |
| 10 | `vw` = rsh(sum_{k2<d} Wm_1(k2, x) `an`, kv), x < dkv; `v` = clamp(`vw`, 2047) | [11.2:342-343] |
| 11 | str_(2lam+1)(j,t) = str_(2lam)(j,t) + rsh(sum_{k2<dq} Wm_2(k2, j) `o`(lam, k2, t), ko) | [11.2:347-348] |
| 12 | gw = rsh(sum Wm_3(k2,x) `mn`, kg); `up` = rsh(sum Wm_4(k2,x) `mn`, ku), with -2^15 <= `up` < 2^15 | [11.2:352-353] |
| 13 | `sl` = gate table at gw. Without `gcl 1` cells hold `gi` = gw. With it: gw = `g0` + 256 `gh`, -128 <= `g0` <= 127, `gc` = clamp(`gh`, 127), table read at `g0` + 256 `gc` | [11.2:354-356] |
| 14 | hh = `sl` * `up` (NOT committed) | [11.2:357] |
| 15 | str_(2lam+2) = str_(2lam+1) + rsh(sum_{k2<f} Wm_9(k2, j) hh(lam, k2, t), kd) | [11.2:358-359] |
| 16 | lw(e,t) = rsh(sum Wm_11(k2, e) `mn`, kr); with `rcl 1`: lw = 8 `ly` + `l3`, 0 <= `l3` <= 7, `lr` = 8 clamp(`ly`, 2047) + `l3`; in both cases -2^14 <= `lr` < 2^14 | [11.2:364-366] |
| 17 | `sel`(e,t) in {0,1}, sum_e `sel` = 1; mr(t) = sum_e `sel` `lr`; for every e: mr - `lr`(e) - sum_{e'>e} `sel`(e') >= 0 (first expert with the largest lr) | [11.2:367-369] |
| 18 | `sc`(t) = 16 round(4096 sigmoid(mr/256)) by the sigmoid's table | [11.2:370] |
| 19 | `xr`(lamM, j, t) = rsh(`sc` `mn`(lam, j, t), 16) | [11.2:371] |
| 20 | x < fe: line 12 with Wm_5, Wm_6. fe <= x < f: gw = rsh(sum_e sum_{k2<d} `sel`(e,t) Wm_7(k2, e, x - fe) `xr`, kgR); `up` same with Wm_8, kuR | [11.2:372-374] |
| 21 | str_(2lam+2) = str_(2lam+1) + rsh(A, kd), A = sum_{k2<fe} Wm_9(k2,j) hh(lam,k2,t) + sum_e sum_{k2<fe} `sel`(e,t) Wm_10(k2, e, j) hh(lam, fe + k2, t) | [11.2:375-377] |

Rounding site [11.2:379-385]: every rsh(A, k) is committed as quotient Q and remainder rem = A + 2^(k-1) - 2^k Q, 0 <= rem < 2^k. Digit form h (hq for line 8, hv for 10, ho for 11, hgD and huD for 12 and 20, hdD for 15 and 21, hr for 16; the sites of line 4 have h = 2; the site of line 19 has none). h = 0: nothing of the remainder is committed, k <= 16. h = 1 or 2: cells hold rh with rem = low + 2^16 (rh + ofs_h), 0 <= low < 2^16, ofs_1 = 128, ofs_2 = 32896; rh has h limbs; k <= 24 for h = 1, k <= 32 for h = 2.

### 3.4 Rounds, in order

Rows in italics upstream are the frame's. Table [11.2:67-91]:

| step | what | rounds | scalars sent | sampled |
|---|---|---|---|---|
| - | moment 0 | `SEND seed`; then `SEND answer` in the chain's first segment, `LOC` in a later one (frame) | | |
| 1 | lookup of the segment's call list | 11.1 steps 1-9 | 187 + (v'^2 + 4v') + (d'^2 + 14d') + (1 + 2d' + 5) + (2(5 + d') + 4) | 11.1 |
| 2 | the norms' token point PV | `ZERO` | 0 | lt |
| 3 | group 0 only: the embedding's point, two rounds | `ZERO`, `ZERO` | 0 | ls + lt; then lPd - ls |
| 4 | sums of limb products W_(i,s), sent alone; batching n = NS | `BAT-sigma` | NS NI | 1 (gam) |
| 5 | point on the norms' numbers rhoI | `JOIN` | 0 | lNI |
| 6 | sums of squares: product level, lNI + lPd + lt variables, default order | `PSC epsilon`, `PSC round`.., `PSC Y`, `PSC values`, `LINE` | 2(lNI + lPd + lt) + 5 | as a product level |
| 7 | row products P_(i,r), sent alone; batching n = NPr NI | `BAT-sigma` | NPr NI | 1 (omV) |
| 8 | first token sumcheck at PV: d_Y = 2, NO NI end values | `PSC epsilon`, lt x `PSC round`, `PSC Y`, `PSC values` | 1 + (1 + 2lt + 2 + NO NI) | eps, lt, beta |
| 9 | second token sumcheck at zt (last lt coordinates of the lookup's key point): d_Y = 1, 2 Lam + LamM(1 + NE) end values | as step 8 | 1 + (1 + 2lt + 1 + 2 Lam + LamM(1 + NE)) | eps, lt, beta |
| 10 | batching, n = 2 | `BAT-sigma` | 0 | 1 (om_1) |
| 11 | batched inner products: lamS plain rounds of degree 2, d_Y = 2, 3 + LamM + NCL - E0 end values | `PSC epsilon`, lamS x `PSC round`, `PSC Y`, `PSC values` | 1 + 2 lamS + 2 + (3 + LamM + NCL - E0) | eps, lamS, beta |
| 12 | gated products: product level, ll + lPf + lt variables, RANGE order | as step 6 | 2(ll + lPf + lt) + 5 | as a product level |
| 13 | routed experts, only if ll > 1: point rhoM on the layers that have them | `JOIN` | 0 | ll - 1 |
| 14 | routed experts' gated products: product level, ll - 1 + lfe + lt variables, RANGE order | as step 6 | 2(ll - 1 + lfe + lt) + 5 | as a product level |
| 15 | group 0 only: the embedding's value v_E, sent alone | none of its own: in the message of step 16's `BAT-sigma` | 1 | |
| 16 | the merge, n = NCL | `BAT-sigma`, `PSC epsilon`, lkW x `PSC round`, `PSC Y`, `PSC values` | 2 lkW + 3 | 1; eps, lkW, beta |
| - | moment 1: `U3` | `SEND seed`, `SEND answer` (frame) | | |
| 17 | the smallness test's matrix | `RNG` | 0 | (columns of all matrices of the list, xbI among them in EVERY group) x tau |
| - | moment 2: `ZZ`, `BZ` | `SEND seed`, `SEND answer` (frame) | | |
| 18 | the smallness test's lookup on the digits, NC = 2, (v'', d'') = (v_Z, 11) | 11.1 steps 1-9 | as a lookup | as a lookup |
| 19 | batching of all claims and equations, n = NCm + Q | `BAT-sigma` | 0 | 1 (chi) |
| - | closing | `BAT`, `FOLD epsilon`, `FOLD round`.. (frame) | | |

- Steps 9 and 10 are always run [11.2:93-95].
- Message placement [11.2:97-101]: the NS NI scalars of step 4 are the message of that `BAT-sigma`; likewise the NPr NI of step 7; the claimed sum of steps 8 and 9 is in the step's `PSC epsilon`, before the hiding polynomial's sum; steps 2, 3, 5, 10, 13, 17, 19 have an empty prover's message, and so has step 16's `BAT-sigma` outside group 0.
- End values in the order sent [11.2:103-108]: step 8: per norm its NO row values. Step 9: Rt_i for the 2 Lam norms; then sct_lamM per routed layer; then, layer by layer, the NE selector entries selt_(lamM,e). Step 11: A0; H1 (gated products); H2_lamM per routed layer; B0; then the weight-claim values v_a in list order, without the embedding's.
- lamS = clog2(S), S = Lam (4 P(d) + P(H dh) + P(f) + 2), plus with routed experts LamM (P(d) + 1 + 2 NE) + LamM NE (2 P(d) + fe); P(x) = x rounded up to a power of two. NCL = 6 Lam + 4 LamM + E0 weight claims [11.2:110-113].
- The merge (step 16) comes BEFORE the root of `U3`; in the head it comes after the smallness test [11.2:231-232].
- Product level of step 6 uses the default order; steps 12 and 14 the range order (bits 2,1,0,5,4,3,8,7,6 then from the highest down to bit 9 [11.1:115-117]); the first round of step 11 binds the highest bit [11.2:235-236].

### 3.5 The lookup of step 1: call list, tables, keys

Call lines: `call NAME KIND SEGMENT ..`; kinds R8, R16 (ranges of 8 and 16 bits), FC (the clamp), FL (the gate function), FS (the sigmoid) [11.2:165-168]. k_c = 8 for R8, else 16 [11.2:199]. Both examples use the same eight lines [pol-full:167-174; pol-small:166-173]:

```
call R16a R16 G U
call R16b R16 N1 N1H N2 N2H O D V
call R16c R16 QK QKH XR LR LT DD
call R8 R8 GH UH OH DH VH ROW LH SEL L3 G0
call FC FC CN1 CN2 CQK CV CLR
call FS FS MR CG
call FL FL F
call R16d R16 UT
```

Tables (rows are numbers below p) [11.1:323-328; 11.2:216-217]:

| kind | row t | padding row [11.1:152-154] |
|---|---|---|
| R8, R16 | t | 0 |
| FC | t + 2^28 (clamp(t - 32768, -2047..2047) + 2048) | 32768 |
| FL | t + 2^28 (s(t) + 4096), s(t) = round(64 silu(c / 2^eg)) clamped to -smax..smax, c = t - 32768 clamped to -64*2^eg .. 64*2^eg - 1 | 32768 |
| FS without `gcl` | t + 2^17 * 16 round(4096 sigmoid((t - 32768)/256)) | 32768 |
| FS with `gcl 1` | t < 32768: t + 2^17 * 16 round(4096 sigmoid((t - 16384)/256)); t >= 32768: t + 2^28 (clamp(t - 49152, -127..127) + 128) + 2^40 | 32768 |

Calls' segments, kind, length, presence [11.2:174-198] (h = digit form: absent if 0, R8 if 1, R16 if 2; (R) = keys only in layers with routed experts, padding in the other layers):

| segments | kind | length | present |
|---|---|---|---|
| G, U, UT | R16 | f | always |
| QK | R16 | (H+G) dh | always |
| QKH | by hq | (H+G) dh | hq > 0 |
| N1, N1H, N2, N2H, O, D | R16 | d | always |
| V | R16 | G dh | always |
| XR (R) | R16 | d | routed experts |
| LR, LT, DD (R) | R16 | NE | routed experts |
| GH; UH | by hgD; by huD | f | form > 0 |
| OH; DH | by ho; by hdD | d | form > 0 |
| VH | by hv | G dh | hv > 0 |
| ROW | R8 | 2 NR | always |
| LH (R) | by hr | NE | routed experts, hr > 0 |
| SEL (R) | R8 | NE | routed experts |
| L3 (R) | R8 | NE | `rcl 1` |
| G0 | R8 | f | `gcl 1` |
| CN1, CN2 | FC | d | always |
| CQK | FC | (H+G) dh | always |
| CV | FC | G dh | always |
| CLR (R) | FC | NE | `rcl 1` |
| MR (R) | FS | 1 | routed experts |
| CG | FS | f | `gcl 1` |
| F | FL | f | always |

Key bits and columns [11.2:202-214, 580-590]: call c has n_c = ll + lJ + lt key bits. The length of each of the call's segments is written in binary; each 1 bit, from the highest down, gives a piece covering consecutive indices from 0. The pieces of all the call's segments (listed in the order of the call's line) are sorted by decreasing size, pieces of equal size keeping their order (a STABLE sort), and take consecutive columns from column 0. lJ = least number with 2^lJ columns enough, and at least nmin - ll - lt. pos_SEG(x) = column of index x of SEG. The key of layer lam, column jc, token t has index (lam 2^lJ_c + jc) T + t. A column no piece takes is padding in every layer; a column of an (R) segment is padding in the layers with even lam.

Key of index x of each call's segment at (lam, x, t) [11.2:599-636]. Shapes: `SK(A, Q, k, h, rh) = 2^lift(k) (A + 2^(k-1) - 2^k Q) - 2^16 (rh + ofs_h)` (last term only if h > 0); `HK(rh, k, h) = 2^(top_h - max(k, 16)) (rh + ofs_h)`, top_1 = 24, top_2 = 32.

| segment | key | enforces `(reading)` |
|---|---|---|
| G | SK(A, gw, k, hgD, `rg`), A, k of line 12 or 20; gw = `gi` or `g0` + 256 `gh` | low 16 bits of the site's remainder are in range |
| U | SK(A, `up`, k, huD, `ru`) | same for `up` |
| GH; UH | HK(`rg`, k, hgD); HK(`ru`, k, huD) | high part of the remainder is below 2^(k-16) |
| UT | `up` + 2^15 | -2^15 <= `up` < 2^15 (line 12) |
| QK | SK(Aqk, `qkw`, k, hq, `rqk`), k = kq for x < dq, kk for x >= dq | site of line 8 |
| QKH | HK(`rqk`, k, hq) | |
| N1; N2 | SK(str_(2lam) R_(2lam), `aw`, K1, 2, `ra`); SK(str_(2lam+1) R_(2lam+1), `mw`, K2, 2, `rm`) | site of line 4 |
| N1H; N2H | HK(`ra`, K1, 2); HK(`rm`, K2, 2) | |
| O | SK(A, str_(2lam+1) - str_(2lam), ko, ho, `ro`), A of line 11 | residual after attention |
| D | SK(A, str_(2lam+2) - str_(2lam+1), kd, hdD, `rd`), A of line 15 or 21 | residual after feed-forward |
| V | SK(A, `vw`, kv, hv, `rv`), A of line 10 | |
| OH; DH; VH | HK(`ro`, ko, ho); HK(`rd`, kd, hdD); HK(`rv`, kv, hv) | |
| ROW | for x = n NR + j, n < 2, j < NR: mul_j D_j of norm 2 lam + n | D_j < 256 / mul_j [11.2:553-555] |
| CN1; CN2 | (`aw` + 2^15) + 2^28 (`an` + 2^11); same with `mw`, `mn` | `an` = clamp(`aw`, 2047), `aw` in -2^15..2^15-1 |
| CQK | (`qkw` + 2^15) + 2^28 (y + 2^11), y = `q` for x < dq, `kx`(lam, x - dq, t) for x >= dq | clamp of q and kx |
| CV | (`vw` + 2^15) + 2^28 (`v` + 2^11) | clamp of v |
| F | (y + 2^15) + 2^28 (`sl` + 2^12), y = `gi` or `g0` + 256 `gc` | `sl` = gate table at y |
| G0 | `g0` + 128 | -128 <= `g0` <= 127 |
| CG | (`gh` + 49152) + 2^28 (`gc` + 128) + 2^40 | `gc` = clamp(`gh`, 127) (second half of FS) |
| XR | `sc` `mn` + 2^15 - 2^16 `xr` | `xr` = rsh(`sc` `mn`, 16) |
| LR | SK(A, lw, kr, hr, `rl`), A of line 16; lw = `lr` or 8 `ly` + `l3` | site of line 16 |
| LH | HK(`rl`, kr, hr) | |
| LT | 2 (`lr` + 2^14) | -2^14 <= `lr` < 2^14 |
| DD | mr - `lr`(lamM, x, t) - sum_{x' > x} `sel`(lamM, x', t) | the argmax condition of line 17 |
| SEL | 128 `sel` | `sel` in {0, 1} |
| MR | (mr + 2^15) + 2^17 `sc`; with `gcl 1`: (mr + 2^14) + 2^17 `sc` | `sc` = sigmoid table at mr |
| L3 | 32 `l3` | 0 <= `l3` <= 7 |
| CLR | (`ly` + 2^15) + 2^25 (`lr` - `l3`) + 2^39 | `lr` - `l3` = 8 clamp(`ly`, 2047) |

Three pieces of a key [11.2:638-645]: the **line piece** (affine in committed cells); the **inner products** (weight times ONE vector over the tokens: 2^lift(k) A in G and U for all x in a dense layer and x < fe in a routed layer; in V, O, LR; in D the sum with Wm_9); the **terms** (products of TWO vectors over the tokens: str_i R_i in N1, N2; 2^lift(kq) Aqk in QK; `sc` `mn` in XR; mr in DD and MR; with routed experts 2^lift(k) A for fe <= x < f in G and U, and the Wm_10 sum in D). A verifier rejects the scale file unless kq = kk or both >= 16, so lift(kq) = lift(kk) [11.2:644-645].

The lookup's host duties here [11.2:743-750]: jLK = 0 (the lookup sends the segment's first scalars); claim LK0 has number 0; LP0 has the number = sum of the counts of groups 1 to 10; the join LJ is NOT a claim (C_11 holds it); padding positions of call c = the T keys of every column jc that is padding in layer lam; column jc of layer lam is in tree y = tree0(c) + floor((lam 2^lJ_c + jc) / 2^(dT - lt)), so npad(y) = T times the number of such (lam, jc) of the call of tree y.

### 3.6 Points and sampled values

A point is written highest bit first; the elements of steps 2, 3, 5, 13 are their points' coordinates in the order sampled [11.2:450-453]. Table [11.2:455-475]:

| name | what | coordinates |
|---|---|---|
| zk_c | key point of call c (11.1) | n_c = ll + lJ_c + lt |
| zl_c, zj_c | first ll of zk_c; next lJ_c | |
| zt | the lookup's token point: last lt of zx = last lt of every zk_c | lt |
| Zk | last la of zx = (last ls of zj_c, zt) for every c | la |
| PV | step 2 | lt |
| ZE = (zsE, ztE); tkh | g = 0, step 3: first round ls then lt elements; second round's elements | ls + lt; lPd - ls |
| gam | step 4 | |
| rhoI | step 5 | lNI |
| r6; ZV | step 6's challenges, each as the coordinate of the variable its round binds; ZV = last la of r6 | lNI + lPd + lt |
| omV | step 7 | |
| rtV | step 8's challenges | lt |
| rt; eps_9 | step 9's challenges; the element of its `PSC epsilon` | lt |
| Zr | (first ls of Zk, rt) | la |
| om_1 | step 10 | |
| rs_n, n < lamS | step 11: rs_n is the coordinate of bit n; the first round samples rs_(lamS-1) | |
| r12; Za | step 12's challenges; last la of r12 | ll + lPf + lt |
| rhoM | step 13 (no coordinates if ll = 1) | ll - 1 |
| r14; Zb | step 14's challenges; last la of r14 | ll - 1 + lfe + lt |

eqlow(lo, hi, n) = eq((rs_(hi-1), .., rs_lo), n) on step 11's challenges; the element xi of the `LINE` rounds of steps 6, 12, 14 enters no formula [11.2:477-479].

### 3.7 The parts of `U3` and the reads

Part entry: number col nb + bk = sum over r < len of phi[r] times the cell in cell row bk len + r, column col [11.2:483-486]. Names "matrix@point" in this order [11.2:490-500]:

| no. | name | weight vector | entries |
|---|---|---|---|
| 1-5 | af@Zk, af@ZV, af@Zr, af@Za, and with routed experts af@Zb | long | NAf k_af 2^(lmaf - la) each |
| 6 | qa@Zk | long | k_qa 2^(lmq - la) |
| 7-9 | xbI@Zk, xbI@ZV, xbI@Zr | long | k_x 2^(lmx - la) each |
| 10 | xbI@ZE (g = 0 only) | long | k_x 2^(lmx - la) |
| 11 | xbO@Zk | long | k_x 2^(lmx - la) |
| 12, 13 | ad@zt, ad@rt | short | NAd k_ad 2^(lmad - lt) each |
| 14-17 | ar@zt, ar@PV, ar@rtV, ar@rt | short | k_ar 2^(lmar - lt) each |
| 18 | qa@zt | short | k_qa 2^(lmq - lt) |
| 19-21 | b@0, b@1, b@pin | 2^lmb entries each (the two planes' points, then weights 2^(r mod 32)) | k_b = NC 2^(kT + 5 - lmb) each |

Short weight vector at z (lt coords): phi[t] = eq(z, t). Long at z (la coords): phi[c2 T + t] = eq(first ls of z, c2) eq(last lt of z, t), c2 < 2^ls [11.2:504-506].

Reads (the only way claims name `U3`) [11.2:511-523]:

```
RS(X, z, ix, j)  = sum_{lb < nl_X} 256^lb U3[ at(mat(X)@z) + feat(X, lb, ix, j) ]                 (short)
RL(X, z, ix, jh) = sum_{lb < nl_X} 256^lb U3[ at(mat(X)@z) + feat(X, lb, ix, 0) / 2^ls + jh ]      (long)
RX(sg, z, jh)    = sum_{lb < XL} 256^lb U3[ at(xbI@z) + lb d / 2^ls + jh ]   for sg = 0
                 = the same with xbO@z                                        for sg = 2 Lam
                 = RL(xs, z, sg - 1, jh)                                      otherwise
```

Tensors of af, qa (q, kx, v), xbI, xbO are read through long parts at Zk; those of ad and ar through short parts at zt; `o` of qa is read at zt through the short part [11.2:695-696, 1160-1163].

### 3.8 A norm's row of digits (five limbs, NR = 99)

Cell j of instance i of `row` holds digit - 128: D_j(i, z) = U3[at(ar@z) + OFF_row + i NR + j] + 128, z one of PV, rtV, rt, zt; dig(n0, n) = sum_{j<n} 256^j D_(n0+j) [11.2:546-553]. Fields [11.2:557-571]:

| number | definition (five limbs) | meaning |
|---|---|---|
| Vlo, Vhi | dig(0, 6), dig(6, 4) (Vsq = Vlo + 2^48 Vhi is not formed) | line 1 |
| c_s | c_0 = 0; c_s = dig(10 + 6(s-1), 6) - 2^47 for s = 1..8; c_9 = D_9 | carry into byte s of Vsq |
| s0 | D_59 | lowest bit of sig |
| a, b | a = 2 D_58 + D_59 + 2^8 D_60 + 2^16 D_61; b = D_62 + 2^8 D_63 | two pieces of sig |
| sig | a + 2^24 b | line 2 |
| l1; h1 | dig(64, 5); dig(69, 5) | Vsq + eps(i) - sig^2; 2 sig - l1 |
| Blo; Bhi | dig(74, 3); dig(77, 2) | (a b) mod 2^23; floor(a b / 2^23) |
| kap | D_79 - 4 | carry from the low 48 bits of LE1 into LE2 |
| Rlo; Rhi; R | dig(80, 3); dig(83, 3); Rlo + 2^24 Rhi | line 3 |
| q1 | dig(86, 3) | Rlo b + Rhi a |
| rr; rq | dig(89, 5); dig(94, 5) | 2^M(i) + floor(sig/2) - R sig; sig - 1 - rr |
| mul_j != 1 | mul_9 = 4, mul_58 = 2, mul_59 = 128, mul_63 = 2, mul_76 = 2, mul_79 = 32 | |

Seven products per norm: P0 = a^2, P1 = a b, P2 = b^2, P3 = Rlo a, P4 = Rlo b, P5 = Rhi a, P6 = Rhi b [11.2:573-576]. (Four limbs: NR = 74, three products; the standard parameter form needs five limbs, so no call ends with an acceptance under four [11.2:1021-1026].)

### 3.9 Sumchecks: statement, degree, start form

| step | kind (11.1) | variables | round form, degree | d_Y | end values | start form C_n | equality point | S0 |
|---|---|---|---|---|---|---|---|---|
| 6 | product level, default order | lNI + lPd + lt | equality, 2 | 2 | vL_6, vR_6 | 2^(-lPd) sum_{i<NI, s<NS} eq(rhoI, i) gam^s W_(i,s) | (rhoI, lPd times the constant 1/2, PV) | vL'_6 vR'_6 |
| 8 | token sumcheck | lt | equality, 2 | 2 | rv_(i,k), NO NI of them | Cl_8 | PV | below |
| 9 | token sumcheck | lt | equality, 2 | 1 | Rt_i, sct_lamM, selt_(lamM,e) | Cl_9 | zt | the constant 0 |
| 11 | plain rounds, first binds the highest bit | lamS | plain, 2 | 2 | A0, H1, H2_lamM, B0, v_a | C_11 | none | As Bs |
| 12 | product level, range order | ll + lPf + lt | equality, 2 | 2 | vL_12, vR_12 | H1 | (rs_(ll+lPf-1), .., rs_0, zt) | vL'_12 vR'_12 |
| 14 | product level, range order | ll - 1 + lfe + lt | equality, 2 | 2 | vL_14, vR_14 | sum_{lamM} eq(rhoM, lamM) H2_lamM | (rhoM, rs_(lfe-1), .., rs_0, rt) | vL'_14 vR'_14 |
| 16 | merge | lkW | plain, 2 | 1 | fv' | merge's start form on the NCL values v_a | none | fv' |

Sources: [11.2:67-91, 700-711, 882-965; 11.1:105-108 (every round of a feed-forward segment has degree 2 except five degree-1 rounds in each lookup)]. In steps 6, 12, 14 the variable of bit n has coordinate number (variables - 1 - n) of the point, whatever the order of the rounds; 1/2 and 2^(-lPd) are inverses in F [11.2:710-711]. In step 6 the lPd feature coordinates are the constant 1/2: equality rounds like the others [11.2:237-238].

What each one states (hidden values per [11.2:531-542]):

- Step 6: vL_6 = vR_6 = sum over i, j, t of eq(r6, (i Pd + j) T + t) sum_lb gam^lb (limb lb of str_i(j,t)); the level squares this map. `(reading)` Since (sum_lb gam^lb x_lb)^2 = sum_s gam^s sum_{lb+lb'=s} x_lb x_lb', this ties the W_(i,s) to the limbs.
- Step 8: Cl_8 = sum_{i,r} omV^(NPr i + r) P_(i,r), i.e. all row products of all norms at PV. S0 with five limbs, a', b', lo', hi' = rv'_(i,0..3): sum_i omV^(7i) a'a' + omV^(7i+1) a'b' + omV^(7i+2) b'b' + omV^(7i+3) lo'a' + omV^(7i+4) lo'b' + omV^(7i+5) hi'a' + omV^(7i+6) hi'b' [11.2:891-895].
- Step 9: Cl_9 = the sum of all TERMS of all keys at zt (sum over t of eq(zt,t), c of e_c, lam of el_c[lam], segments and x of ew_SEG[x] times the term) [11.2:735-737]. Its claim is not added: KT = -(1/eps_9) Left(C_9; 0; 0) goes into C_11 [11.2:721-725].
- Step 11: C_11 = sum over n < 2^lamS of SA[n] SB[n] [11.2:754]; C_11 = (inner products of all keys at zt) + om_1 (terms at rt) [11.2:740-741].
- Steps 12, 14: end values are MINUS `sl` and MINUS `up` at r12 (index (lam Pf + x) T + t), resp. of the routed features fe + x at r14 (index (lamM fe + x) T + t) [11.2:539-540]; H1, H2_lamM are the extensions of hh = `sl` `up` that the D panels need [11.2:820-822].

The start form of step 11 [11.2:716-721]:

```
C_11   = sum_{c<NC} e_c JP_c + sum_{NT <= y < 2^rK} eq(zy, y) (alpha - padkey_0) - Cl_9 - C_end + om_1 KT
JP_c   = alpha - c theta - tab_c(t0_c) PADW_c - sum_{lam<Lam} el_c[lam] (sum over the call's segments SEG of LINE_SEG(lam))
PADW_c = sum_{lam<Lam} el_c[lam] (sum over the columns jc < 2^lJ_c that are padding in layer lam of eq(zj_c, jc))
KT     = -(1 / eps_9) Left(C_9; 0; 0)
```

In JP_c an (R) segment is left out for even lam [11.2:723]. The running claim of step 11 starts from the PUBLIC part of C_11: its constant plus each coefficient of a hidden value times its shown value; entries of `U3` count as 0 and so do the mask entries of step 9's hiding polynomial [11.2:728-731]. C_11 names entries of `U3`, which is committed LATER (moment 1) [11.2:233-234].

Weights used by the forms [11.2:592-597]: el_c[lam] = eq(zl_c, lam); ew_SEG[x] = eq(zj_c, pos_SEG(x)); ewh_SEG[xh] = eq(first lJ_c - ls of zj_c, floor(pos_SEG(2^ls xh) / 2^ls)); sw_SEG(a, b) = sum_{a <= x < b} ew_SEG[x].

LINE_SEG(lam) = sum_x ew_SEG[x] times the line piece of the key at zt, built from [11.2:651-659]:

```
SL(X; a, b; x0) = sum_{a/2^ls <= xh < b/2^ls} ewh_SEG[xh] RL(X, Zk, lam, xh - x0/2^ls)     SL(X) = SL(X; 0, n; 0)
SX(sg)          = sum_{xh < d/2^ls} ewh_SEG[xh] RX(sg, Zk, xh)
SS(X)           = sum_{x < n} ew_SEG[x] RS(X, zt, ix, x)
SITE(sw, Q, k, h, rh) = 2^lift(k) (2^(k-1) sw - 2^k Q) - 2^16 (ofs_h sw + rh)      (last term only if h > 0)
HIGH(sw, rh, k, h)    = 2^(top_h - max(k, 16)) (ofs_h sw + rh)
Qg(a, b) = SL(gi; a, b), or SL(g0; a, b) + 256 SL(gh; a, b) with gcl 1
```

The 31 LINE forms, one per call's segment, are the table at [11.2:661-693]; copy it verbatim into the spec (examples: `UT: SL(up) + 2^15 sw`; `CN1: SL(aw) + 2^28 SS(an) + (2^15 + 2^39) sw`; `F: SL(gi) + 2^28 SL(sl) + (2^15 + 2^40) sw` with SL(g0) + 256 SL(gc) for SL(gi) under `gcl 1`; `CG: SL(gh) + 2^28 SL(gc) + (49152 + 2^35 + 2^40) sw`; `MR: ew[0] (2^15 + 2^17 RS(sc, zt, lamM, 0))` with 2^14 under `gcl 1`; `DD: - sum_{x<NE} ew[x] (RS(lr, zt, lamM, x) + sum_{x<x'<NE} RS(sel, zt, lamM, x'))`). The forms of an (R) segment are formed for odd lam only [11.2:696].

### 3.10 The panels of step 11

A panel has a pass (1: inner products at zt; 2: terms at rt), the weight e_c of its call, ni rows, ny columns, a coefficient wt_ri per row [11.2:754-758]. List order: first pass = the calls holding G, U, V, O, D, LR in call-list order, segments in the order of the call's line; second pass = the calls holding N1, N2, QK, and with routed experts G, U, XR, D, DD, MR [11.2:760-768]. Table [11.2:770-782]:

| pass | segment | kind | ni | ny | first factor FA(ri, yv) | second factor FB | wt_ri |
|---|---|---|---|---|---|---|---|
| 1 | G; U | weights | Lam | d | RS(`mn`, zt, lam, yv) | weights | el[lam] 2^lift(kg); el[lam] 2^lift(ku) |
| 1 | V | weights | Lam | d | RS(`an`, zt, lam, yv) | weights | el[lam] 2^lift(kv) |
| 1 | O | weights | Lam | dq | RS(`o`, zt, lam, yv) | weights | el[lam] 2^lift(ko) |
| 1 | D | weights, first factor not sent | Lam | f | sum_t eq(zt,t) hh(lam, yv, t), known through H1 alone | weights | el[lam] 2^lift(kd) |
| 1 | LR | weights | LamM | d | RS(`mn`, zt, lam, yv) | weights | el[lam] 2^lift(kr) |
| 2 | N1; N2 | pair | Lam | 1 | the number Rt'_(2lam); Rt'_(2lam+1) | sum_{xh<d/2^ls} ewh_SEG[xh] RX(2lam + n, Zr, xh) | el[lam] |
| 2 | QK | weights | Lam | d | RS(`an`, rt, lam, yv) | weights | el[lam] 2^lift(kq) |
| 2 | XR | pair | LamM | 1 | the number sct'_lamM | sum_{x<d} ew_XR[x] RS(`mn`, rt, lam, x) | el[lam] |
| 2 | DD; MR | pair | LamM | NE | the number selt'_(lamM,yv) | RS(`lr`, rt, lamM, yv) | el[lam] sw_DD; el[lam] ew_MR[0] |
| 2 | G; U routed: one panel per lamM | selector | NE | d | selt'_(lamM,ri) RS(`xr`, rt, lamM, yv) | weights | one per panel: el[2lamM+1] 2^lift(kgR); .. 2^lift(kuR) |
| 2 | D routed: one panel per lamM | selector, column factor not sent | NE | fe | selt'_(lamM,ri) sum_t eq(rt,t) hh(2lamM+1, fe + yv, t), known through H2_lamM alone | weights | one per panel: el[2lamM+1] 2^lift(kd) |

- Row ri means lam = ri if ni is Lam, lam = 2 ri + 1 (lamM = ri) if LamM, an expert if the kind is selector [11.2:763-765].
- Placement [11.2:787-790]: wy = clog2(ny), w = clog2(ni) + wy; panels sorted by decreasing w (stable); off = sum of 2^w over the panels before it in the sorted order; entry (ri, yv) has index off + ri 2^wy + yv.
- SA/SB [11.2:792-799]: in the first-pass D panel SA[n] = FA, SB[n] = e_c wt_ri FB; in every other panel SA[n] = om e_c wt_ri FA, SB[n] = FB (om = 1 first pass, om_1 second).
- At the challenges [11.2:801-822]: sb = eqlow(w, lamS, off / 2^w); EY[yv] = eqlow(0, wy, yv); EI[ri] = eqlow(wy, w, ri); co = sb om e_c; s1 = sum_{ri<NE} selt'_(lamM,ri) EI[ri] for a selector panel; v0 = number of the panel's first weight claim. The verifier computes two NUMBERS As, Bs and two FORMS Alin, Blin:

| kind | adds to As | adds to Alin | adds to Bs | adds to Blin |
|---|---|---|---|---|
| weights | | sum_{ri,yv} co wt_ri EI[ri] EY[yv] FA(ri,yv) | sum_ri sb EI[ri] v'_(v0+ri) | |
| weights, first factor not sent (D, pass 1) | sb H1' | | sum_ri sb EI[ri] e_c wt_ri v'_(v0+ri) | |
| pair | | the constant sum_{ri,yv} co wt_ri EI[ri] EY[yv] FA(ri,yv) | | sum_{ri,yv} sb EI[ri] EY[yv] FB(ri,yv) |
| selector | | sum_yv co wt s1 EY[yv] RS(`xr`, rt, lamM, yv) | sb v'_v0 | |
| selector, column factor not sent (D, pass 2) | co wt s1 H2'_lamM | | sb v'_v0 | |

As also adds A0', Bs adds B0'; the summand of step 11 at the challenges is As Bs [11.2:819-822].

### 3.11 The weight claims (handed to the merge)

Order = the panels' list BEFORE sorting [11.2:826-828, 1168-1169]: first pass, each of G, U, V, O, D gives one claim per layer, LR one per routed layer; second pass, QK one per layer and with routed experts each of G, U, D one per routed layer; in group 0 the embedding's claim is last [11.2:115-119]. Factors per index group (11.5 classes) [11.2:830-836]:

```
FR(lo0, nbit): pt[n] = rs_(lo0 + z - 1 - n) for n < z;            HV[hi] = eqlow(lo0 + z, lo0 + nbit, hi) for hi < o
FE(SEG, x0)  : pt[n] = coordinate lJ_c - z + n of zj_c;            HV[hi] = eq(first lJ_c - z of zj_c, floor(pos_SEG(x0 + 2^z hi) / 2^z))
```
(extent of the index group = o 2^z, o odd.)

| from | unit kind X, layer | factors |
|---|---|---|
| pass 1, G; U | 3; 4 (dense layer), 5; 6 (routed layer); layer l | `kk`: FR(0, lPd). `x`: FE(SEG, 0) |
| pass 1, V | 1, l | `kk`: FR(0, lPd). `x`: FE(V, 0) |
| pass 1, O | 2, l | `kk`: FR(0, clog2(dq)). `x`: FE(O, 0) |
| pass 1, D | 9, l | `kk`: FR(0, lPf). `x`: FE(D, 0) |
| pass 1, LR | 11, l (odd lam) | `kk`: FR(0, lPd). `x`: FE(LR, 0) |
| pass 2, QK | 0, l | `hd`: AV = AH. `cd`: AV = rot. `kk`: FR(0, lPd) |
| pass 2, G; U | 7; 8, layer g Lam + 2 lamM + 1 | `kk`: FR(0, lPd). `e`: FR(lPd, le). `x`: FE(SEG, fe) |
| pass 2, D | 10, layer g Lam + 2 lamM + 1 | `kk`: FR(0, lfe). `e`: FR(lfe, le). `x`: FE(D, 0) |
| g = 0: the embedding | 12, layer L | `v`: AV = tokw. `x`: pt and HV from pnt |

[11.2:838-848]. In a routed layer the group `kk` of unit 9 has extent fe: FR(0, lPf) then has z = lfe and HV[0] = 1 - rs_lfe [11.2:850-852].

**Positional (rotary) factors of the QK claim** (c = the call holding QK) [11.2:854-863]:

```
AH[hd]  = eq(first lJ_c - ldh of zj_c, pos_QK(hd dh) / dh)  for hd < H + G;   AH[hd] = 0 for H + G <= hd < 64
lf[ch]  = eq(last ldh of zj_c, ch)                           for ch < dh
Ct[pa]  = sum_{t<T} eq(rt, t) Co(l, t, pa);   St[pa] = sum_{t<T} eq(rt, t) Si(l, t, pa)
rot[2 pa]     = Ct[pa] lf[2 pa] + St[pa] lf[2 pa + 1]
rot[2 pa + 1] = Ct[pa] lf[2 pa + 1] - St[pa] lf[2 pa]
```
Co, Si are the rotary tables' integers; in a layer with rp = 0, Ct[pa] = 2^12 and St[pa] = 0. So the rotary encoding never appears as a committed table or a lookup: the verifier evaluates the multilinear extension of the public tables at rt itself and folds it into a factor of the Wq/Wk weight claim. 64 is the extent of the index group `hd` [11.2:1013-1014].

**Token factors of the embedding claim** [11.2:865-868]: tokw[vv] = sum of eq(ztE, t) over the positions t < T with tok_t = vv, for vv below `V`; pnt = (tkh, zsE), lPd coordinates; for the group `x` of extent d = o 2^z: pt[n] = coordinate lPd - z + n of pnt, HV[hi] = eq(first lPd - z of pnt, hi). This is the only place the request's tokens enter a feed-forward sub-proof [11.2:1009].

### 3.12 The claims, in order (NCm = sum of the counts)

Claim number c gets chi^c (with 11.1's exception for the smallness test's matrix and read claims) [11.2:121-122]. Counts [11.2:124-140], equations [11.2:876-965]:

| group | count | claims |
|---|---|---|
| 1 | 31 + v' + d' + 1 | the lookup's claims on mask entries alone, 11.1 order: 31 tie, v' key levels, d' table levels, 1 bits |
| 2 | 3 | (1) Left(C_6; vL'_6 vR'_6; 0) = 0. (2) vL_6 - vR_6 = 0. (3) vL_6 - sum_{i<NI, kh<d/2^ls, lb<XL} eq(first lNI + lPd - ls of r6, i Pd/2^ls + kh) gam^lb ent(i, lb, kh) = 0, ent(0, lb, kh) = U3[at(xbI@ZV) + lb d/2^ls + kh], ent(i >= 1, lb, kh) = U3[at(af@ZV) + feat(`xs`, lb, i-1, 0)/2^ls + kh] |
| 3 | 2 | (1) Cl_8 - sum_{i,r} omV^(NPr i + r) P_(i,r) = 0. (2) Left(C_8; S0; 0) = 0 |
| 4 | NO NI | by i then k: rv_(i,k) - y_k(i, rtV) = 0, (y_0..y_3) = (a, b, Rlo, Rhi) |
| 5 | NS NI | by i then s: W_(i,s) + c_s(i, PV) - D_s(i, PV) - 256 c_(s+1)(i, PV) = 0 |
| 6 | 8 NI | by i, all at (i, PV): LE0 P_(i,1) - Blo - 2^23 Bhi = 0; LE1 Vlo + eps(i) - P_(i,0) - 2^25 Blo - l1 + 2^48 kap = 0; LE2 Vhi - Bhi - P_(i,2) - kap = 0; LE3 l1 + h1 - 2 sig = 0; LR1 P_(i,4) + P_(i,5) - q1 = 0; LR2 P_(i,6) = 0; LR3 2^(M(i)+1) + sig - s0 - 2 P_(i,3) - 2^25 q1 - 2 rr = 0; LR4 rr + rq - sig + 1 = 0 |
| 7 | 2 Lam + LamM (1 + NE) | Rt_i - R(i, rt) = 0; sct_lamM - RS(`sc`, rt, lamM, 0) = 0; selt_(lamM,e) - RS(`sel`, rt, lamM, e) = 0 |
| 8 | 3 | (1) Left(C_12; vL'_12 vR'_12; 0) = 0. (2) vL_12 + sum_{lam<Lam, kh<f/2^ls} eq(first ll + lPf - ls of r12, lam Pf/2^ls + kh) RL(`sl`, Za, lam, kh) = 0. (3) vR_12 + the same with RL(`up`, ..) = 0. NOTE THE PLUS SIGNS |
| 9 (routed) | 3 | (1) Left(C_14; vL'_14 vR'_14; 0) = 0. (2) vL_14 + sum_{lamM, kh<fe/2^ls} eq(first ll - 1 + lfe - ls of r14, lamM fe/2^ls + kh) RL(`sl`, Zb, 2lamM+1, fe/2^ls + kh) = 0. (3) vR_14 + same with `up` = 0 |
| 10 (routed) | LamM | by lamM: sum_{e<NE} RS(`sel`, zt, lamM, e) - 1 = 0 (tested at the one point zt; no round of its own in the error accounting) |
| 11 | 3 | the lookup's three claims on its planes: TB_0(col) = U3[at(b@0) + col], TB_1(col) = U3[at(b@1) + col], TP(col) = U3[at(b@pin) + col] |
| 12 (g = 0) | 1 | sum_{kh<d/2^ls} eq(tkh, kh) RX(0, ZE, kh) - v_E = 0 |
| 13 | 36 + v'' + d'' + NM + NX | the smallness test's, 11.1 order; its parts of `U3` are those of 3.7 in that order |
| 14 | 3 | (1) Left(C_11; As Bs; 0) = 0. (2) A0 - Alin = 0. (3) B0 - Blin = 0 |
| 15 | 1 | Left(C_16; fv'; 0) = 0 (the merge) |

`(reading)` of group 6: with sig = a + 2^24 b, LE0-LE2 say Vsq + eps - sig^2 = l1, LE3 says 0 <= l1 <= 2 sig, so sig = isqrt(Vsq + eps); LR1-LR2 make R sig = P3 + 2^24 q1; LR3 says rr = 2^M + floor(sig/2) - R sig and LR4 says 0 <= rr <= sig - 1, so R is line 3's quotient. Group 5 writes sum_s 256^s W_(i,s) = Vsq byte by byte with carries.

NM = number of matrices of the list; NX = number of reads = sum over the parts of `U3` of (matrix cell rows / length of the part's weight vector); Q = sum over the matrices of tauP times (packed rows rounded up to a power of two), plus NX tauP [11.2:142-147].

### 3.13 What the verifier computes itself (feed-forward)

Everything public: "the three public files, the request's tokens, every sampled value and every scalar as it was sent. From these a verifier computes every coefficient and every constant" [11.2:267-271]. Concretely: sizes and layouts (3.1-3.2); the column maps pos_SEG and padding counts npad(y) (3.5); the points (3.6); the weights el, ew, ewh, sw, PADW (3.9); every LINE form's coefficients on `U3`; pub(C_11) and the running claims of all sumchecks (unsent coefficients); As, Bs, Alin, Blin (3.10); the weight-claim factors FR, FE, AH, lf, Ct, St, rot, tokw, pnt (3.11); the digit-row forms (3.8); all Left(..) forms; KT (one inversion of eps_9 in E); the accumulation of all claims under powers of chi; the two tests of 3.14. Costs: section 9.

### 3.14 Rejection conditions (feed-forward)

During the rounds a verifier rejects only for form (coordinate not below p, missing bytes, failed proof-of-work) with two exceptions, one of which is here [11.1:42-44]:

1. **`coin-zero`:** no acceptance if eps of step 9 is 0 (the claim is divided by eps_9); the programs reject [11.2:243-245, 969-970; FORMAT:2467].
2. **Free scalar (`internal-g-free-slot`, prefix `G<g>:`):** after all claims are added up with their powers of chi, no acceptance if the coefficient under a scalar's number other than that of fv' is 0; the programs also end the call if the coefficient under fv' is not 0 ("which no proof can cause"); such a call ends `NOT CHECKED` [11.2:970-974]. This IS a test on content of every verifier [11.2:967-968; FORMAT:2458-2463, 2475].
3. The smallness test's own sampled-value events (FORMAT 13.9 events 2-8) apply [11.2:967-968; 11.1:1406-1433].
4. The segment's one equation is tested by the frame, not by the sub-proof [11.1:49-50].
5. Before reading a proof: tests on the public files (names in section 8.3). Call-list tests `policy-call-list` / `policy-call-line`: at most 8 calls; no line without a call's segment; no two calls of one name; no call named V, a, b or E; every segment the parameters call for present exactly once and in a call of its kind; no unknown or uncalled-for segment; a call's name has at most 8 characters [11.2:202-210]. `iota_c` must equal n_c - dT, or 0 for an absent call [11.2:159-161].
6. Not needed by a second verifier: the `internal-` self-checks, `plan-tensor-layout` at the three places named, `hid-profile-segment-<SEG>` [11.2:980-999].

Optional lines and what they change: table at [11.2:1127-1134]. Indices beyond the true width: [11.2:1138-1153]. Upstream's own list of traps: [11.2:229-247, 1155-1178]; the ones most likely to break an implementation: groups 8 and 9 have plus signs while group 2 claim 3 has a minus [11.2:1157]; group 2 reads single limbs under powers of gam, every other read joins limbs with powers of 256 [11.2:1158-1159]; the first-pass D panel has its weights on the Bs side [11.2:1166-1167]; weight-claim numbers follow the unsorted panel list, offsets the sorted one [11.2:1168-1169]; the QK panel takes lift(kq) for queries and keys alike while LINE_QK takes kq for x < dq and kk for x >= dq [11.2:1170-1171]; KT is a form, and C_11 also has the term - Cl_9 of its own [11.2:1175-1176].

## 4. Attention segment A_g (11.3)

### 4.1 Numbers

[11.3:45-60] lt, T; lB, lnT = lt - lB; H, G = 2^lgk, HA = H / G; dh = 2^ldh; ll, Lam; NP = Lam HA; la, nmin, kFD, lmS, NAs, lmh, lmo, lmbA, tau; `kFM` is hashed like every line "and no test and no formula of a verifier reads it"; lidb (22 if absent); sh(lam) = the layer's scale-file shift, nsh = number of different shifts in the group (standard parameter form `one-shift`: nsh = 1); m_qa = 2^lmq, k_qa from 11.2; s = line `answers` (held at 1); nM = lgk + 2 lt - 1; nD = lgk + lt + lB.
[11.3:269-283] Bt = 2^lB (side of a tile), nT = 2^lnT = T / Bt (tile rows), hP = nT / 2; ls = la - lt, S2 = 2^ls; dq = H dh, dkv = G dh; wcH = 2^(lmh - lt), wcO = 2^(lmo - lt), wcQ = m_qa / T; fillQ = k_qa wcQ; Sx, rx = lines `S`, `rx`; Tt[u], u0 = the exponential table and its length; Smax = dh * 2047^2; for a shift sh: C_sh = u0 2^sh, rho = 65536 - 2^sh, nHD = ceil((4 Smax + 1) / rho), Om_sh = 2 Smax + C_sh; hk < G a key-value head, a < HA, h = hk HA + a the query head; b = lam HA + a < NP.

### 4.2 The integer function, per layer lam and query head h = hk HA + a

[11.3:304-325]

1. q, kx, v come from the feed-forward segment (projections, rotary tables, clamp to -2047..2047: calls' segments CQK, CV). The attention segment does not test it. kx is the key AFTER the rotary tables and the clamp.
2. Scores: sc(i, j) = sum_ch q[lam, h, i, ch] kx[lam, hk, j, ch], j <= i; |sc| <= Smax.
3. Maximum: Mx(i) = sc(i, ib(i)) for a position ib(i) <= i, and Mx(i) >= sc(i, j) for all j <= i.
4. Weights: Df(i, j) = Mx(i) - sc(i, j), t = floor(Df / 2^sh); ew(i, j) = Tt[t] if t < u0, else 0. For j > i in a tile above the diagonal there is no weight; in a tile on the diagonal the weight is 0.
5. Denominator: Zd(i) = sum_{j<=i} ew(i, j).
6. Weighted sum: acc(i, ch) = sum_{j<=i} ew(i, j) v[lam, hk, j, ch].
7. Rounding: o[lam, h, i, ch] is the integer with rem = 2 acc + Zd - 2 Zd o and 0 <= rem <= 2 Zd - 1 (acc / Zd to nearest, half up).

"No floating-point number enters but through the public table Tt" [11.3:325].

### 4.3 Tiles: the piece that is quadratic in T

The T x T pairs (i, j) of one head are cut into nT x nT tiles of Bt x Bt pairs [11.3:329-349]:

- **Region D:** the nT tiles on the diagonal (J = I). ALL Bt^2 pairs of such a tile have cells, those with jl > il too. Pair index n = ((hk nT + I) Bt + il) Bt + jl, nD bits.
- **Region M:** the tiles below the diagonal (J < I), addressed (P, sg), P < hP, sg <= nT - 2: the address is the tile (I, J) = (P, sg) if sg < P, and (nT - 1 - P, sg - P) otherwise. Inverse: tile (I, J) with J < I has address (I, J) if I < hP, else (nT - 1 - I, J + nT - 1 - I). The address (P, nT - 1) is **empty**: it has cells but no tile. Pair index n = (((hk hP + P) nT + sg) Bt + il) Bt + jl, nM bits.
- Tiles with J > I have no cells.
- Public vectors of nT entries for a point (yP, ys) of lnT - 1 and lnT coordinates: WI(yP, ys)[I'] = sum of eq(yP, P) eq(ys, sg) over the addresses with sg <= nT - 2 and I(P, sg) = I'; WJ likewise with J(P, sg) = J'.

Size: 2^nM = G hP nT Bt^2 = G T^2 / 2 pairs per (layer, a) in region M and 2^nD = G T Bt in region D; as holds five cells per pair, so 5 NP (2^nM + 2^nD) cells in use [11.3:104, 373-378]. That is 471,859,200 cells at full size and 245,760 for the small example (my arithmetic). This quadratic object is committed and looked up (keys of `RM`, `FM`), so it is the PROVER's cost and the commitment's size. The verifier never iterates over pairs: it sees as only through `U3` entries (kAs = 7,200 columns at full size) and through sumchecks whose number of variables grows by 2 lt (nM bits). So for the verifier the T^2 shows up as about 2 lt more rounds, not as a T^2 loop `(reading)`.

### 4.4 Oracle messages

[11.3:87-111] A matrix of m cell rows and k columns is committed as an array of ceil(m/3) rows over F.

| moment | name | holds | cell rows m | columns k |
|---|---|---|---|---|
| 0 | `M0`..`M(NAs-1)` | the parts of as: five cells per score | 2^lmS each | kAs / NAs each |
| 0 | `M(NAs)` | ah: each row's maximum and denominator (four cells each) and the lt bits of its index | 2^lmh | fillH / 2^(lmh - lt) |
| 0 | `M(NAs+1)` | ao: the two remainders of each division | 2^lmo | fillO / 2^(lmo - lt) |
| 0 | `M(NAs+2)` | bA: multiplicities of the segment's lookup as 32 planes of bits | 2^lmbA | kbA |
| 1 | `U3` | partial evaluations of as, ah, ao, bA and qa | one row of nW elements of E | |
| 2 | `ZZ` | two digits of every combination of the smallness test | tau rows of 2 mz elements of F | |
| 2 | `BZ` | multiplicities of the lookup on the digits | 32 rows of 2^11 elements of F | |

kAs = NAs ceil(5 NP (2^nM + 2^nD) / (NAs 2^lmS)); fillH = 8 Lam H + Lam lt H rounded up to a multiple of 2^(lmh - lt); fillO = 2 Lam H dh rounded up to a multiple of 2^(lmo - lt); kbA = NC 2^(kT + 5 - lmbA); mz = NAs 2^lmS + 2^lmh + 2^lmo + 2^lmbA + m_qa; nW = 3 kAs + (nKF + 6) fillH + fillO / 2^(la - lt) + (2 nKF + 5) k_qa m_qa / 2^la + 3 kbA [11.3:104-108].

Cells [11.3:359-403]:

- as, five planes per pair: plane 0 = (rm mod 256) - 128; plane 1 = floor(rm / 256) - 128; plane 2 = fl (1 if rm >= 2^sh); planes 3, 4 = c3, c4 with ew = (c3 + 128) + 256 c4. Cell number: region M: N = ((x Lam + lam) HA + a) 2^nM + n; region D: N = 5 NP 2^nM + ((x Lam + lam) HA + a) 2^nD + n; cell N is in cell row N mod 2^lmS of column floor(N / 2^lmS).
- ah, ao, qa hold features: cell of feature f, position pos is in column floor(f / wc), cell row (f mod wc) T + pos. Tensor (off, nl, cnt = Lam, nf): limb l of entry f' of layer lam is feature off + (l cnt + lam) nf + f'.

| matrix | tensor | off | nl | nf | entry f' | value |
|---|---|---|---|---|---|---|
| ah | Mx | 0 | 4 | H | h | Mx(i) |
| ah | Zd | 4 Lam H | 4 | H | h | Zd(i) |
| ah | ibit | 8 Lam H | 1 | lt H | k H + h | bit k of ib(i), bit 0 lowest |
| ao | rh | 0 | 1 | dq | h dh + ch | floor(rem / 65536) - 128 |
| ao | rhp | Lam dq | 1 | dq | h dh + ch | floor((2 Zd(i) - 1 - rem) / 65536) - 128 |
| qa | q | 0 | 2 | dq | h dh + ch | q[lam, h, i, ch] |
| qa | kx | 2 Lam dq | 2 | dkv | hk dh + ch | kx[lam, hk, j, ch] |
| qa | v | 2 Lam dq + 2 Lam dkv | 2 | dkv | hk dh + ch | v[lam, hk, j, ch] |
| qa | o | 2 Lam dq + 4 Lam dkv | 2 | dq | h dh + ch | o[lam, h, i, ch] |

A verifier rejects the public files (`internal-qa-layout`, `plan-tensor-layout`) unless these qa numbers are those of the feed-forward segment [11.3:406-408]. A block of ao or qa = the 2^la = S2 T cell rows of S2 neighbouring features in one column [11.3:410-413].

### 4.5 The lookup calls

Lines `callA NAME KIND SEG..`, kinds `KR`, `KFD`, `R16`, `WH`; each of the seven calls' segments `RM`, `RD`, `FM`, `FD`, `WL`, `WH`, `IX` is in exactly one line of its kind (`RM`, `RD` in `KR`; `FM`, `FD` in `KFD`; `WL`, `IX` in `R16`; `WH` in `WH`). Expanded list: a `KR` or `KFD` line gives one call per different shift of the group, in increasing order; NC >= 4, at most 12 [11.3:64-70]. Both examples: `callA KR KR RM RD`, `callA KFD KFD FM FD`, `callA R16 R16 WL IX`, `callA WH WH WH` [pol-full:175-178; pol-small:174-177].

Pieces [11.3:72-77]: per call's segment (line order), per layer lam (for `KR`/`KFD` only the layers with the call's shift), per a < HA: one piece of 2^nb keys. n_c = max(nmin, clog2(tot_c)); k_c = kFD for `KFD`, 16 otherwise. Units (a call paired with one of its segments) are taken call by call, `RM` before `RD`, `FM` before `FD`, whatever the line's order; nKR = nKF = 2 nsh [11.3:79-83].

Tables [11.1:331-334]: `KR` for shift sh: (t mod 256) + 2^20 floor(t / 256), and 2^40 more if t >= 2^sh; 65,536 rows. `WH`: (t mod 256) + 2^20 floor(t / 256); 65,536 rows. `KFD` for shift sh, 2^kFD rows: t 2^sh + 2^33 Tt[t] for t < u0; C_sh - 2^sh + rho (t - u0) + 2^32 for u0 <= t < u0 + nHD; C_sh - 2^sh + rho (t - u0 - nHD) + rho/2 + 2^32 from there on.

Keys [11.3:428-446]:

| segment | table | index inside the piece (highest bits first) | nb | key |
|---|---|---|---|---|
| `RM` | `KR` for sh(lam) | (hk, P, sg, il, jl) | nM | (c0 + 128) + 2^20 (c1 + 128) + 2^40 c2, pair in region M |
| `RD` | `KR` | (hk, I, il, jl) | nD | the same, region D |
| `FM` | `KFD` for sh(lam) | (hk, P, sg, il, jl) | nM | Df - (c0 + 128) - 256 (c1 + 128) + 2^32 c2 + 2^33 ((c3 + 128) + 256 c4) |
| `FD` | `KFD` | (hk, I, il, jl) | nD | the same |
| `WL` | `R16` | (sl, hk, i, ch), sl one bit | 1 + lgk + lt + ldh | sl = 0: rem - 65536 (rh + 128); sl = 1: 2 Zd(i) - 1 - rem - 65536 (rhp + 128) |
| `WH` | `WH` | (hk, i, ch) | lgk + lt + ldh | (rh + 128) + 2^20 (rhp + 128) |
| `IX` | `R16` | (hk, i) | lgk + lt | 2^(16 - lt) (i - ib(i)), ib(i) = sum_k 2^k ibit_k |

with rem = 2 acc(i, ch) + Zd(i) - 2 Zd(i) o[lam, h, i, ch], and

```
region M, sg <= nT - 2:  Df = Mx(I Bt + il) - sc(I Bt + il, J Bt + jl), (I, J) the tile of the address (P, sg)
region M, sg  = nT - 1:  Df = C_sh                                         (the empty address)
region D, jl <= il:      Df = Mx(I Bt + il) - sc(I Bt + il, I Bt + jl)
region D, jl  > il:      Df = Mx(I Bt + il) - sc(I Bt + il, I Bt + jl) + Om_sh      (the causal mask)
```

What the tables say of a key (upstream's reading of the table rows, "not an argument") [11.3:448-457]: a `KR` row fixes c0 + 128 and c1 + 128 as the two bytes of rm < 65536 and c2 as the flag rm >= 2^sh. A `KFD` row t < u0 fits a key with flag 0, Df - rm = t 2^sh, ew = Tt[t]; a row t >= u0 fits flag 1, ew = 0. A `WL` key in 0..65535 with `WH` bytes in 0..255 puts rem and 2 Zd - 1 - rem in 0..2^24 - 1. An `IX` key in 0..65535 gives 0 <= i - ib(i) < T.

Ordering of a call's keys [11.3:459-465]: list the pieces by segment (line order), then lam, then a; stable-sort by decreasing nb; place from key index 0; off = a piece's first key index (a multiple of 2^nb). Keys from tot_c on are padding: row 0 (the number 0) for `KR`, `R16`, `WH`; row u0 of `KFD`, which is C_sh - 2^sh + 2^32. npad(y) = min(2^dT, max(0, (m + 1) 2^dT - tot_c)) for tree m of call c [11.3:807-809].

Piece weight wp = eq(zk_c[0 .. n_c - nb), off / 2^nb); a unit's inner point = the last nb coordinates of zk_c; LW = sum of a unit's piece weights [11.3:467-474].

Extra parameter tests for these calls: dT >= lmS and dT >= lt + ldh, and `iotaA_0` = 32 + dT [11.3:139-141].

### 4.6 Rounds, in order

Sumcheck notation [k_1..k_n / d_Y / N]: n plain rounds of degrees k_i, degree d_Y in Y, N end values [11.3:120-122]. In rows 4-15 every `PSC round` is a PLAIN round (the linear coefficient is not sent); in a product level and in a lookup's sumchecks every round is an equality round [11.3:134-136]. Table [11.3:148-174]:

| # | rounds | prover's message | sampled |
|---|---|---|---|
| 1 | `SEND seed` | roots of the trees of the segment's first prover's message | the s seeds of an out-of-domain sample |
| 2 | `LOC` | s answers per oracle message that gets one | the positions of the group of the feed-forward segment of group g; then the openings |
| 3 | the lookup (v_A, d_A) | | |
| 4 | for each unit of `KFD`, in order: sumcheck [3..3 / 2 / 2 np] with lgk + 2 lnT - 1 + ldh variables for `FM`, lgk + lnT + ldh for `FD` | before the sumcheck's own scalar, in its `PSC epsilon`: 7 scalars. In the first unit's, before these 7: 3 scalars per unit of `KR` (3 nKR) | |
| 5 | sumcheck SE [3..3 / 2 / 2 NP], lgk + lt variables | before its own scalar: 5 + lt + 2 scalars | |
| 6 | `BAT-sigma`, 2 rows | empty | 1 (gam) |
| 7 | sumcheck VM [3..3 / 2 / 2 NP], lgk + 2 lnT - 1 + lB variables | before its own scalar: 2 scalars (CL0, CL1) | |
| 8 | sumcheck VD [3..3 / 2 / 2 NP], lgk + lnT + lB variables | | |
| 9 | `ZERO` | empty | 2 lgk + 2 lt + 4 |
| 10 | `BAT-sigma`, NP rows | NP scalars (M6_b) | 1 |
| 11 | sumcheck SF [3..3 / 2 / 2 NP], lt + lgk + ldh variables | | |
| 12 | `BAT-sigma`, NP rows | empty | 1 |
| 13 | sumcheck SD [2..2, lt+2..lt+2, lt+1..lt+1 / lt + 1 / Lam + NP lt]: lt rounds of degree 2, then lgk of degree lt + 2, then lt of degree lt + 1 | | |
| 14 | `BAT-sigma`, NP rows | empty | 1 |
| 15 | sumcheck HB [3..3 / 2 / 2 NP], lt + lgk + 4 variables | | |
| 16, 17 | `SEND seed`, `SEND answer` | moment 1: `U3` | seeds; nothing |
| 18 | `RNG` | empty | K tau matrix entries, K = kAs + fillH / 2^(lmh - lt) + fillO / 2^(lmo - lt) + kbA + k_qa |
| 19, 20 | `SEND seed`, `SEND answer` | moment 2: `ZZ`, `BZ` | seeds; nothing |
| 21 | the lookup (v_Z, 11) | | |
| 22 | `BAT-sigma`, NCm + Q rows | empty | 1 (chi) |
| 23 | `BAT` | empty | 1 |
| 24 | `FOLD epsilon` | 1 scalar | 1 |
| 25 | `FOLD round`, once per row variable of the segment's group | 2 scalars | 1 |

Rows 1, 2, 16, 17, 19, 20, 23-25 are the frame's [11.3:176]. Row 18's entries are sampled matrix by matrix in the order as (its parts), ah, ao, bA, qa; the columns of qa are among them although another segment committed qa [11.3:181-183]. A scalar sent outside a sumcheck has no round of its own: it is at the start of the message of the next round [11.3:115-118].

Counts [11.3:185-193], with LL(v, dL) = 32 + v + dL:

```
NX  = 3 NAs + (nKF + 6) 2^(lmh - lt) + 2^(lmo - la) + (2 nKF + 5) m_qa / 2^la + 3
NCm = LL(v_A, d_A) + 3 nKR + 6 nKF + 4 NP + (5 + lt + 2 NP) + 1 + (1 + 4 NP) + (4 NP + Lam + NP lt) + 3 + (nKF + 6)
      + LL(v_Z, 11) + 4 + (NAs + 4) + NX
Q   = tauP (NX + sum over the NAs + 4 matrices of 2^clog2(ceil(m / 3))),   tauP = 2^clog2(tau)
```

### 4.7 Points, scalars, parts of `U3`, readings

Points [11.3:478-528]: coordinate 0 is the highest bit; a sumcheck's challenges are taken in the order of its rounds (first `PSC round` = coordinate 0), so every sumcheck of rows 4-15 binds the highest bit of its first index first; the `ZERO` elements of row 9 are used in the order sampled, without reversal.

- Inner points: `RM`/`RD`: Z_u [nM or nD]; `FM`: Z_u = (zg_u [lgk], zP_u [lnT - 1], zs_u [lnT], zi_u [lB], zj_u [lB]); `FD`: Z_u = (zg_u [lgk], zI_u [lnT], zi_u [lB], zj_u [lB]); `WL`: (zsl [1], zgW [lgk], ziW [lt], zcW [ldh]), ziW = (zihi [lnT], zilo [lB]); `IX`: (zgX [lgk], ziX [lt]); `WH`: (zgH [lgk], ziH [lt], zcH [ldh]). Because dT >= lmS and dT >= lt + ldh, the last lmS coordinates of every Z_u are the last lmS of zx, and (ziW, zcW) = (ziH, zcH) = the last lt + ldh coordinates of zx [11.3:490-502].
- Row 6: gam. Row 9 in the order sampled: tg [lgk], ti [lt], tk [4], tbg [lgk], tbi [lt]. Rows 10, 12, 14: om_b, om4_b, om5_b = b-th powers of the sampled element [11.3:506-512].
- Challenges: K_u `FM`: (rg_u, rP_u, rs_u, rc_u); K_u `FD`: (rg_u, rI_u, rc_u); SE: (rgE, riE); VM: (rgM, rPM, rsM, rjM); VD: (rgD, rID, rjD); SF: (riF, rgF, rcF); SD: (pj [lt], pg [lgk], pi [lt]); HB: (ri2, rg2, rk [4]). ptM = (rgM, rPM, rsM, zilo, rjM), nM coordinates; ptD = (rgD, rID, zilo, rjD), nD coordinates [11.3:516-528].

Scalars in the order sent [11.3:535-554]: row 3: the lookup's. Row 4: per unit u of `KR`: R_(u,0..2) (alone; plane x of as at the inner point); then per unit u of `KFD`: PV_(u,0..4), MV_u, SV_u (alone), directly followed by the scalars of K_u with end values AE_(u,0), BE_(u,0), AE_(u,1), .. . Row 5: ACC, ZO, ZC, RH, RHP; IB_0..IB_(lt-1); RH2, RHP2 (all alone); then SE. Row 7: CL0, CL1 (alone), then VM. Row 8: VD. Row 10: M6_0..M6_(NP-1). Row 11: SF. Row 13: SD, end values KC_0..KC_(Lam-1), then IBP_(b,k) as number Lam + b lt + k. Row 15: HB. In every sumcheck but SD, AE_b is end value 2b and BE_b is 2b + 1.

Parts of `U3`, in order [11.3:577-598]. Weight-vector constructors [11.3:572-575]: EQ(z)[n] = eq(z, n); tok(Wv, z)[I Bt + il] = Wv[I] eq(z, il); lng(zc, tv)[lo T + pos] = eq(zc[ldh - ls .. ldh), lo) tv[pos].

| no. | part | matrix | entries | weight vector |
|---|---|---|---|---|
| 1 | tA | as | kAs | EQ(last lmS coordinates of zx) |
| 2 | tVM | as | kAs | EQ(last lmS of ptM) |
| 3 | tVD | as | kAs | EQ(last lmS of ptD) |
| 4 | tM_u, per unit u of `KFD` | ah | fillH | `FM`: tok(WI(zP_u, zs_u), zi_u); `FD`: tok(EQ(zI_u), zi_u) |
| 5 | hW | ah | fillH | EQ(ziW) |
| 6 | hX | ah | fillH | EQ(ziX) |
| 7 | hE | ah | fillH | EQ(riE) |
| 8 | hT | ah | fillH | EQ(ti) |
| 9 | hPi | ah | fillH | EQ(pi) |
| 10 | hR2 | ah | fillH | EQ(ri2) |
| 11 | tO | ao | fillO / S2 | lng(zcW, EQ(ziW)) |
| 12 | per unit u of `KFD`: tQ_u then tK_u | qa | fillQ / S2 each | `FM`: tQ_u = lng(rc_u, tok(WI(rP_u, rs_u), zi_u)), tK_u = lng(rc_u, tok(WJ(rP_u, rs_u), zj_u)); `FD`: tQ_u = lng(rc_u, tok(EQ(rI_u), zi_u)), tK_u = lng(rc_u, tok(EQ(rI_u), zj_u)) |
| 13 | qO | qa | fillQ / S2 | lng(zcW, EQ(riE)) |
| 14 | qVM | qa | fillQ / S2 | lng(zcW, tok(WJ(rPM, rsM), rjM)) |
| 15 | qVD | qa | fillQ / S2 | lng(zcW, tok(EQ(rID), rjD)) |
| 16 | qF | qa | fillQ / S2 | lng(rcF, EQ(riF)) |
| 17 | qKx | qa | fillQ / S2 | lng(rcF, EQ(pj)) |
| 18-20 | tB_0, tB_1, tP | bA | kbA each | phiB_0, phiB_1 (the lookup's at zb_0, zb_1); phiP[r] = 2^(r mod 32) |

All weight vectors are fixed before the root of `U3` is sent (row 16) [11.3:600-602].

The four readings [11.3:608-617]:

```
PL(p; x, lam, a; Z, M) = sum_{n < 2^(nM - lmS)} eq(Z[0 .. nM - lmS), n) U(p; ((x Lam + lam) HA + a) 2^(nM - lmS) + n)
PL(p; x, lam, a; Z, D) = sum_{n < 2^(nD - lmS)} eq(Z[0 .. nD - lmS), n) U(p; 5 NP 2^(nM - lmS) + ((x Lam + lam) HA + a) 2^(nD - lmS) + n)
LV(p; Tn; lam, f')     = sum_{l < nl} 256^l U(p; off + (l Lam + lam) nf + f')
XL(p; Tn; lam, hd; zc) = sum_{n < 2^(ldh - ls)} eq(zc[0 .. ldh - ls), n) sum_{l < nl} 256^l U(p; (off + (l Lam + lam) nf + hd dh) / S2 + n)
OG(z; F)               = sum_{hk < G} eq(z, hk) F(hk)
```

### 4.8 The eight kinds of sumcheck of rows 4-15

Each is a sumcheck with a hiding sum whose rounds are all plain. All but SD: the sum over b and over a cube of W_b A_b B_b, W_b public multilinear, A_b, B_b hidden multilinear: degree 3 per variable; S0 = sum_b W_b shown(AE_b) shown(BE_b) [11.3:621-631]. Table [11.3:633-641]:

| sumcheck | start form | cube (highest bits first) | W_b at the challenge point | A_b | B_b |
|---|---|---|---|---|---|
| K_u, `FM` | [SV_u] | (hk, P, sg, ch) | wp_b eqp(zg_u, rg_u) eqp(zP_u, rP_u) (eqp(zs_u, rs_u) - ones(zs_u) ones(rs_u)) | sum_il eq(zi_u, il) q[lam, h, I(P,sg) Bt + il, ch] | sum_jl eq(zj_u, jl) kx[lam, hk, J(P,sg) Bt + jl, ch] |
| K_u, `FD` | [SV_u] | (hk, I, ch) | wp_b eqp(zg_u, rg_u) eqp(zI_u, rI_u) | sum_il eq(zi_u, il) q[lam, h, I Bt + il, ch] | sum_jl eq(zj_u, jl) kx[lam, hk, I Bt + jl, ch] |
| SE | [ZO] | (hk, i) | wpW_b eqp(zgW, rgE) eqp(ziW, riE) | Zd(i) of (lam, h) | sum_ch eq(zcW, ch) o[lam, h, i, ch] |
| VM | [CL0] | (hk, P, sg, jl) | wpW_b eqp(zgW, rgM) sum_{I'<nT} eq(zihi, I') WI(rPM, rsM)[I'] | sum_il eq(zilo, il) ew of the pair (hk, P, sg, il, jl) of region M | gam + sum_ch eq(zcW, ch) v[lam, hk, J(P,sg) Bt + jl, ch] |
| VD | [CL1] | (hk, I, jl) | wpW_b eqp(zgW, rgD) eqp(zihi, rID) | sum_il eq(zilo, il) ew of the pair (hk, I, il, jl) of region D | gam + sum_ch eq(zcW, ch) v[lam, hk, I Bt + jl, ch] |
| SF | sum_b om_b [M6_b] | (i, hk, ch) | om_b eqp(tg, rgF) eqp(ti, riF) | q[lam, h, i, ch] | kx[lam, hk, ib(i), ch] |
| HB | 0 | (i, hk, k), k of 4 bits | om5_b eqp(tbi, ri2) eqp(tbg, rg2) eqp(tk, rk) | ibit_k at token i of (lam, h) for k < lt, 0 for k >= lt | A_b - 1 |

eqp(y, z) = product over s of y_s z_s + (1 - y_s)(1 - z_s); ones(z) = product of all coordinates; id(z) = sum_s 2^(n-1-s) z_s; LE(y, z): LE_n = 1, LE_s = (1 - y_s) z_s + (y_s z_s + (1 - y_s)(1 - z_s)) LE_(s+1), LE = LE_0 (on bits: 1 if y <= z) [11.3:292-295]. In K_u, b runs over the unit's np pieces; elsewhere b = lam HA + a < NP. The term ones(zs_u) ones(rs_u) takes the empty address out of the sum [11.3:643-647].

SD [11.3:649-659]: starts from sum_b om4_b [BE_(SF,b)]; it is the sum over (j, hk, i) of eq(riF, i) eq(rgF, hk) sum_b om4_b KC_lam(j, hk) prod_{k<lt} eq1(ibit_k(lam, h, i), bit k of j), lam = floor(b/HA), h = hk HA + (b mod HA), KC_lam(j, hk) = sum_ch eq(rcF, ch) kx[lam, hk, j, ch], eq1(s, y) = s y + (1 - s)(1 - y). Rounds bind the lt bits of j (degree 2), then the lgk bits of hk (degree lt + 2), then the lt bits of i (degree lt + 1). With y_k = pj[lt - 1 - k]:

```
S0 = eqp(riF, pi) eqp(rgF, pg) sum_b om4_b shown(KC_(floor(b/HA))) prod_{k<lt} (shown(IBP_(b,k)) (2 y_k - 1) + 1 - y_k)
```

The claim a sumcheck of this part leaves, LEFT(name) = Left(C; S0; 0) written out for n plain rounds of degrees k_0..k_(n-1) then Y [11.3:661-677]:

```
sum_{l<n, t=1..k_l} gamma_l^t (gamma_(l+1) .. gamma_(n-1)) mask(j0 + sk(l) + t - 1)
+ sum_{t=0..d_Y} beta^t mask(j0 + sk(n) + t)
+ eps (gamma_0 .. gamma_(n-1)) (pub(C) - C) + eps S0 - cur = 0
```
with sk(l) = k_0 + .. + k_(l-1); the first end value has number jE = j0 + 1 + sk(n) + d_Y.

### 4.9 The claims, in order (ten groups)

[11.3:681-798] ([X] = hidden value of scalar X; lam = floor(b / HA), a = b mod HA in groups 4, 6, 7, 8.)

| group | count | claims |
|---|---|---|
| 1 | 32 + v_A + d_A | the lookup's own LK0..: 31 tie, v_A key levels, d_A table levels, 1 bits |
| 2 | 3 nKR | per `KR` call (expanded order), unit `RM` then `RD`, x = 0, 1, 2: [R_(u,x)] - sum over the unit's pieces of wp PL(tA; x, lam, a; Z_u, reg) = 0 |
| 3 | 7 nKF + 4 NP | per `KFD` call, unit `FM` then `FD`: (1) x = 0..4: [PV_(u,x)] - sum_pieces wp PL(tA; x, lam, a; Z_u, reg) = 0; (2) [MV_u] - sum_pieces wp OG(zg_u; hk -> LV(tM_u; Mx; lam, hk HA + a)) = 0; (3) LEFT(K_u); (4) per piece b': [AE_(u,b')] - OG(rg_u; hk -> XL(tQ_u; q; lam, hk HA + a; rc_u)) = 0, then [BE_(u,b')] - OG(rg_u; hk -> XL(tK_u; kx; lam, hk; rc_u)) = 0 |
| 4 | 6 + lt + 2 NP | (1) [ZC] - sum_b wpW_b OG(zgW; hk -> LV(hW; Zd; lam, hk HA + a)) = 0; (2) [RH] - sum_b wpW_b OG(zgW; hk -> XL(tO; rh; lam, hk HA + a; zcW)) = 0; (3) same with RHP, rhp; (4) k = 0..lt-1: [IB_k] - sum_b wpX_b OG(zgX; hk -> LV(hX; ibit; lam, k H + hk HA + a)) = 0; (5) [RH2] - sum_b wpH_b OG(zgH; hk -> XL(tO; rh; lam, hk HA + a; zcH)) = 0; (6) same with RHP2, rhp; (7) LEFT(SE); (8) per b: [AE_(SE,b)] - OG(rgE; hk -> LV(hE; Zd; lam, hk HA + a)) = 0, then [BE_(SE,b)] - OG(rgE; hk -> XL(qO; o; lam, hk HA + a; zcW)) = 0 |
| 5 | 1 | the join LJ (below) |
| 6 | 3 + 4 NP | (1) [CL0] + [CL1] - [ACC] - gam [ZC] = 0; (2) LEFT(VM); (3) per b: [AE_(VM,b)] - PL(tVM; 3, lam, a; ptM, M) - 128 - 256 PL(tVM; 4, lam, a; ptM, M) = 0, then [BE_(VM,b)] - gam - OG(rgM; hk -> XL(qVM; v; lam, hk; zcW)) = 0; (4) LEFT(VD); (5) per b: the same two with tVD, ptD, D and qVD, rgD |
| 7 | 2 + 2 NP + Lam + NP lt | (1) per b: [M6_b] - OG(tg; hk -> LV(hT; Mx; lam, hk HA + a)) = 0; (2) LEFT(SF); (3) per b: [AE_(SF,b)] - OG(rgF; hk -> XL(qF; q; lam, hk HA + a; rcF)) = 0; (4) LEFT(SD); (5) per lam: [KC_lam] - OG(pg; hk -> XL(qKx; kx; lam, hk; rcF)) = 0; (6) per b, per k: [IBP_(b,k)] - OG(pg; hk -> LV(hPi; ibit; lam, k H + hk HA + a)) = 0 |
| 8 | 1 + 2 NP | (1) LEFT(HB); (2) per b: [BE_(HB,b)] - [AE_(HB,b)] + 1 = 0, then [AE_(HB,b)] - sum_{k<lt} eq(rk, k) OG(rg2; hk -> LV(hR2; ibit; lam, k H + hk HA + a)) = 0 |
| 9 | 3 | LP0, LP1, LP2 on the planes of bA: TB_0(col) = U(tB_0; col), TB_1(col) = U(tB_1; col), TP(col) = U(tP; col) |
| 10 | (32 + v_Z + 11) + 4 + (NAs + 4) + NX | the smallness test, 11.1 order, on the matrices as (its parts), ah, ao, bA, qa and the parts of `U3` in table order |

BE_(SF,b) has no claim on cells: it is the start form of SD [11.3:776].

The join (group 5) and the key forms [11.3:723-752]:

```
LJ = sum_c e_c (alpha - c theta - KF_c) + (alpha - padkey_0) sum_{y = NT .. 2^rK - 1} eq(zy, y) - C_end = 0

KR :  KF_c = sum over the call's units u of ([R_(u,0)] + 128 LW_u) + 2^20 ([R_(u,1)] + 128 LW_u) + 2^40 [R_(u,2)]
KFD:  KF_c = (1 - wall_c)(C_sh - 2^sh + 2^32) + sum over the call's units u of
             DP_u - ([PV_(u,0)] + 128 LW_u) - 256 ([PV_(u,1)] + 128 LW_u) + 2^32 [PV_(u,2)] + 2^33 ([PV_(u,3)] + 128 LW_u + 256 [PV_(u,4)])
      DP_u = [MV_u] - [SV_u] + C_sh LW_u ones(zs_u)                  for FM
      DP_u = [MV_u] - [SV_u] + Om_sh LW_u (1 - LE(zj_u, zi_u))       for FD
      wall_c = the sum of the weights wp of all pieces of the call
R16:  KF_c = tWL (if the call has WL) + tIX (if it has IX)
      REM = 2 [ACC] + [ZC] - 2 [ZO]
      tw0 = REM - 65536 ([RH] + 128 LWW)
      tw1 = 2 [ZC] - LWW - REM - 65536 ([RHP] + 128 LWW)
      tWL = (1 - zsl) tw0 + zsl tw1
      tIX = 2^(16 - lt) (LWX id(ziX) - sum_{k<lt} 2^k [IB_k])
WH :  KF_c = ([RH2] + 128 LWH) + 2^20 ([RHP2] + 128 LWH)
```

Claim numbers the machinery needs [11.3:805-813]: jLK = 0; LK0 has number 0; LJ has number nLJ = (32 + v_A + d_A) + 3 nKR + (7 nKF + 4 NP) + (6 + lt + 2 NP); LP0 has number nLJ + 1 + (3 + 4 NP) + (2 + 2 NP + Lam + NP lt) + (1 + 2 NP); the smallness test's first claim n0 = that + 3; the lookup on the digits has jLK = the number of the scalars of rows 3-15.

### 4.10 How softmax, normalization and the causal mask are handled in integers

- **Softmax weight:** no exponential is computed in the proof. The pair's key in `FM`/`FD` packs Df - rm, the flag and ew; membership in `KFD` gives, for flag 0, Df - rm = t 2^sh and ew = Tt[t] with rm < 2^sh from `KR`, i.e. t = floor(Df / 2^sh); for flag 1, ew = 0 and Df >= C_sh = u0 2^sh [11.3:452-455]. One fitting choice of cells: [11.3:916-923].
- **Scores:** never committed per pair. SV_u is the weighted sum of all scores of a unit; the sumcheck K_u proves SV_u = sum over (hk, tile, ch) of (q folded over il at zi_u) times (kx folded over jl at zj_u); the tile-to-address map enters through WI, WJ in the weight vectors of tM_u, tQ_u, tK_u [11.3:539, 635-636, 582, 590].
- **Normalization:** Zd is committed (four limbs); ACC and ZC are tied to the weights by VM + VD with the batching trick gam: claim [CL0] + [CL1] - [ACC] - gam [ZC] = 0, where B_b = gam + (v at the point) [11.3:638-639, 756]. The division o = round(acc / Zd) is the two-sided remainder test of `WL` + `WH` on REM = 2 ACC + ZC - 2 ZO, where ZO = (Zd o) comes from the product sumcheck SE [11.3:541, 637, 744-747].
- **Maximum:** group 7 ties Mx(i) to sc(i, ib(i)): SF proves sum_b om_b M6_b = sum q[i] kx[ib(i)], SD opens kx at the committed index bits (the product over k of eq1 is 1 exactly if j = ib(i)), HB proves the index cells are bits (A_b (A_b - 1) summed to 0) [11.3:640-641, 649-657, 766-784]. That Mx(i) >= every sc(i, j) follows from the tables only: a key with Df < 0 fits no row `(reading of [11.3:452-455])`.
- **Causal mask:** "No claim has the mask as its only subject. Four things together make it, and all four are needed" [11.3:885]: (1) tiles above the diagonal do not exist (no address); (2) inside a diagonal tile the key of `FD` adds Om_sh = 2 Smax + C_sh to Df where jl > il, in the key form the public term Om_sh LW_u (1 - LE(zj_u, zi_u)), which is meant to force the weight 0; (3) the sums VM and VD take every cell of both regions (VM all addresses but the empty one, VD all jl of a diagonal tile); (4) the key of `IX`, 2^(16 - lt) (i - ib(i)) in the 16-bit range, is meant to give ib(i) <= i [11.3:887-909]. The empty address is treated like a masked pair: Df = C_sh constant, public term C_sh LW_u ones(zs_u) [11.3:911-912, 738].
- **Positional encoding:** absent from this segment. kx is already "the key after the rotary tables and the clamp" [11.3:310-311]; the rotary scheme is verified in G_g (3.11).
- Per-head structure: q and o are per QUERY head h (H of them), kx and v per KEY-VALUE head hk (G of them); every sumcheck has hk as lgk cube variables and b = (lam, a) as the batched index, so all heads of all Lam layers are covered by one run of each sumcheck (NP = Lam HA end-value pairs) [11.3:280-281, 643].

### 4.11 What is public in a claim, and rejections

Public terms come from four sources [11.3:872-881]: (1) the 128 a cell leaves out (128 LW over a unit's pieces; - LWW for the -1 of the second `WL` key; LWX id(ziX) for the position i of `IX`; plain 128 in the AE_(VM/VD) claims); (2) the constants C_sh ones(zs_u) and Om_sh (1 - LE(zj_u, zi_u)); (3) the padding: (1 - wall_c) times the padding key in the `KFD` key form and the padkey_0 term of the join; (4) what a sumcheck leaves: eps S0 - cur.

Rejections:

- During rounds: form only [11.1:42-44].
- After the last claim: every scalar's number must have a coefficient other than 0 in the sum of all claims (`internal-a-free-slot`, prefix `A<g>:`); it is "a test on content of every verifier": where a coefficient is 0 a verifier gives no acceptance [11.3:829-833]. Note: unlike 11.2/11.4 there is no merge and so no exempt scalar.
- Smallness-test events 2-8 of FORMAT 13.9 apply [11.3:839-841].
- Tests on the public files before reading a proof: table at [11.3:949-979] (names in section 8.3). `forest-only-padding-<call>`: not all keys of a call are padding [11.3:974].
- Self-checks a second verifier does not need: [11.3:815-828, 843-859]. The programs end the call `NOT CHECKED` under `internal-a-table-index` if one of their own claims names an entry at or after the end of a part of `U3` [11.3:930-933].

Upstream's traps [11.3:210-230, 1029-1051]: two orders of pieces (placing order vs (lam, a) order of sums, end values and claims); units follow `RM` before `RD`, `FM` before `FD` regardless of the line; XL takes zc[0 .. ldh - ls) and lng takes zc[ldh - ls .. ldh); IB_k and IBP_(b,k) have weight 2^k with bit 0 lowest but y_k = pj[lt - 1 - k]; LE takes (zj_u, zi_u) in this order and the term is 1 - LE; the order (i, hk, ch) of SF and (i, hk, k) of HB differs from (hk, i) of SE and of the keys; [ZC] has no channel; in group 8 the claim [BE] - [AE] + 1 = 0 comes BEFORE the claim on [AE].

## 5. Output head H (11.4)

### 5.1 What it is about; the request's part in it

- The segment takes the residual stream that leaves the last group. It is about the final norm at every position, the product of the normalized stream with the head's weights, and the relation between the logits and the request's tokens that the acceptance policy states [11.4:11-14].
- The request is T tokens and two positions r, e with r < e <= T; the next token is one token y. Position t is a **checked position** if r <= t < e. It is about token t + 1 of the request (a checked token), or at position T - 1 about the next token y. A checked position with t + 1 < T has a **cost**; the lines `C`, `theta`, `cap` bound the costs. If position T - 1 is checked, y must be the index of the largest logit there, the lowest index on ties. If e < T no checked position is about y, and y is 0 [11.4:14-19; FORMAT:1154-1164].
- Public per-position numbers [11.4:230-233]: on_t = 1 if r <= t < e; co_t = 1 if on_t = 1 and t + 1 < T (the position has a cost); RC = min(e, T - 1) - r = the number of positions with a cost; win_t = token t + 1 of the request if t + 1 < T, and at t = T - 1 "the y that is sent in the round `REPLY`".
- A verifier rejects the call unless every token and y are below V, r < e <= T, and y = 0 where e < T [11.4:163-164]; names `statement-required`, `statement-range`, `token-range` [FORMAT:1166-1176].
- Sizes [11.4:24-26]: lt, d, la, ls, lPd, XL, NS, NPr, NO, NR, lkW as in 11.2; S2 = 2^ls; JV = V rounded up to a multiple of S2; JVa = 2^(w-1) with w the least number with 2^w >= JV. NRH = NR + 21 = 120 with five limbs [11.4:224]. BIG = 2^37 (source `BIGH`); offE = 128 (2^24 - 1)/255 + 1 = 8,421,505 [11.4:227-228].

### 5.2 Oracle messages and cells

[11.4:28-49]

| mu | matrix | cells | cell rows | n cells per position |
|---|---|---|---|---|
| 0..NHf-1 | hf (NHf parts) | final norm's wide output and remainder (2 limbs x d each); per vocabulary entry two digits of a margin (2 limbs and 1 limb x JV) and a table value (3 cells x JV) | 2^lmhf each | 4 d + 6 JV |
| then 1 | hd | final norm's clamped output (2 limbs x d) | 2^lmhd | 2 d |
| then 1 | hr | final norm's row of digits and 21 further digits per position | 2^lmhr | NR + 21 |
| then 1 | bH | planes of the lookup's multiplicities | 2^lmbH | NC 2^(kT + 5 - lmbH) columns |
| last | xbL | the residual stream that enters the head; NOT committed here: it is xbO of the last feed-forward segment | 2^lmx | XL d |

Moments: 0 = hf, hd, hr, bH (no other segment reads them); 1 = `U3`; 2 = `ZZ`, `BZ`.

Where a cell is [11.4:305-309]: with i = f T + t, the cell of feature f and position t is in matrix floor(i / (k_mu 2^lm)) of the np, column floor(i / 2^lm) mod k_mu, cell row i mod 2^lm.

| matrix | feature | the cell holds | so that |
|---|---|---|---|
| xbL | lb d + k, lb < XL | limb lb of str[t][k] | str = sum 256^lb limb |
| hf | lb d + k, lb < 2 (`oAw` = 0) | limb lb of aw[t][k] | aw = limb 0 + 256 limb 1 |
| hf | 2 d + lb d + k, lb < 2 (`oRa`) | limb lb of rh[t][k] - 32896 | rh = 32896 + limb 0 + 256 limb 1 |
| hf | 4 d + lb JV + v, lb < 2, v < JV (`oD1`) | limb lb of d1[t][v] | K_1 = 32896 + d1 at a real pair |
| hf | 4 d + 2 JV + v (`oD2`) | d2[t][v] | K_2 = 128 + d2 at a real pair |
| hf | 4 d + 3 JV + lb JV + v, lb < 3 (`oE`) | limb lb of ex[t][v] - offE | ex = offE + limb 0 + 256 limb 1 + 65536 limb 2, at EVERY pair |
| hd | lb d + k, lb < 2 | limb lb of act[t][k] | act = limb 0 + 256 limb 1 |
| hr | j < NRH | digit j of the position's row, minus 128 | D_j = 128 + the cell |

[11.4:313-327]. A real pair = (v, t) with v < V and on_t = 1 [11.4:234].

### 5.3 The integers the head computes

[11.4:254-296] (all hidden)

1. str[t][k] = sum_{lb<XL} 256^lb cell_xbL(lb d + k, t).
2. Final norm: Vsq_t = sum_{k<d} str[t][k]^2; sig_t = the largest integer with sig^2 <= Vsq_t + epsF; R_t = floor((2^`MF` + floor(sig_t/2)) / sig_t).
3. Wide output: aw[t][k] = floor((str[t][k] R_t + 2^(`KF`-1)) / 2^`KF`); the remainder is 2^16 rh + rl, 0 <= rl < 2^16, 0 <= rh < 2^(`KF`-16).
4. Activations: act[t][k] = aw[t][k] clamped to -2047..2047 (the clamp's table has an argument only for -32768 <= aw <= 32767).
5. Logits: lam_t[v] = sum_{k<d} act[t][k] Wh[k][v]; Wh[k][v] = committed weight of unit 13 with index v in the group `x` and k in the group `kk`.
6. Margins: at a real pair, Mg[t][v] = lam_t[win_t] + co_t (gc_t + BIG gb_t) - lam_t[v] - [v < win_t] - Pub[t][v]; Pub[t][v] is 0 in this format. The logit gap of a position = max over v < V of lam_t[v] - lam_t[win_t] + [v < win_t].
7. Three digits: Mg[t][v] = K_2 + 2^`sh` K_1 + 2^(`sh`+15) K_0, 0 <= K_2 < 2^8, 0 <= K_1 < 2^16, 0 <= K_0 < 2^16. The weights overlap, so the digits are not unique; the prover chooses them.
8. Table values: ex[t][v] = EX[K_1[t][v]].
9. Six hidden numbers of a position with a cost, all non-negative: gc_t, gb_t, gu_t, gk_t = `C` - gc_t, gz_t, gs_t = 2^`F` - sum_{v<V} ex[t][v]; gu_t and gz_t fill (B2) and (B3) up to their public values.

At a pair that is not real: no margin; the cells of the two lower digits hold 0 and the table value is EX[0] = 2^`F` [11.4:295-296]. Position T - 1 never has a cost; if e = T its margins are Mg[T-1][v] = lam_(T-1)[y] - lam_(T-1)[v] - [v < y] [11.4:298-299]. The embedding is not in this segment (it is in G_0) [11.4:291-292].

### 5.4 The `REPLY` round and the rounds of the head

**`REPLY`:** the frame receives the next token as ONE scalar that is NOT masked, in the round `REPLY`, directly before the segment's first `SEND seed` (R14.8). It has no number among the sub-proof's scalars. The sub-proof rejects the proof unless the scalar's second and third coordinates are 0 and its first is below V (`header-y` [11.4:300]). The first coordinate is y, used as the token of position T - 1 if that position is checked. The comparison with the next token that the client was given is the frame's [11.4:51-57]. R14.8: one element of E, a prover's message by itself, round of kind 7 in which the verifier says nothing; the first word of a segment is 1 for the last segment and 0 for every other [10:254-259]. R15.7: the token y is the element (y, 0, 0); in the statement item the next token's word (171) is 0 [FORMAT:1290-1294]. `cp_verify` compares after it has gone "through all segments of the first chain, to the end of their last proximity test", all three coordinates, rejection `reply-differs` [FORMAT:1296-1302].

Rounds [11.4:61-79]:

| step | what | rounds | scalars sent | sampled |
|---|---|---|---|---|
| - | the next token | `REPLY` (frame) | 1, not masked | nothing |
| - | moment 0 | `SEND seed`, `LOC` (frame) | | |
| 1 | lookup of the head's call list | 11.1 steps 1-9 | as a lookup (v', d') | 11.1 |
| 2 | the norm's token point pV | `ZERO` | 0 | lt |
| 3 | sums of limb products W_s, alone; batching n = NS | `BAT-sigma` | NS | 1 (gam) |
| 4 | the sum of squares: product level, lPd + lt variables, default order | `PSC epsilon`, `PSC round`.., `PSC Y`, `PSC values`, `LINE` | 2(lPd + lt) + 5 | as a product level |
| 5 | row products P_i, alone; batching n = NPr | `BAT-sigma` | NPr | 1 (om) |
| 6 | first token sumcheck at pV: d_Y = 2, NO end values | `PSC epsilon`, lt x `PSC round`, `PSC Y`, `PSC values` | 1 + (1 + 2 lt + 2 + NO) | eps, lt, beta |
| 7 | second token sumcheck (the stream times the reciprocal) at zt: d_Y = 2, 2 end values | as step 6 | 1 + (1 + 2 lt + 2 + 2) | eps, lt, beta |
| 8 | third token sumcheck (the activations times the head's weights) at zt, with lPd FURTHER equality rounds at the constant 1/2: d_Y = 2, 2 end values | `PSC epsilon`, (lt + lPd) x `PSC round`, `PSC Y`, `PSC values` | 1 + (1 + 2(lt + lPd) + 2 + 2) | eps, lt + lPd, beta |
| - | moment 1: `U3` | `SEND seed`, `SEND answer` (frame) | | |
| 9 | the smallness test's matrix | `RNG` | 0 | (columns of all matrices of the list, xbL among them) x tau |
| - | moment 2: `ZZ`, `BZ` | `SEND seed`, `SEND answer` (frame) | | |
| 10 | the smallness test's lookup on the digits, NC = 2, (v_Z, 11) | 11.1 steps 1-9 | as a lookup | as a lookup |
| 11 | the merge, n = 1 | `BAT-sigma`, `PSC epsilon`, lkW x `PSC round`, `PSC Y`, `PSC values` | 2 lkW + 3 | 1; eps, lkW, beta |
| 12 | batching of all claims and equations, n = NCm + Q | `BAT-sigma` | 0 | 1 (chi) |
| - | closing | `BAT`, `FOLD epsilon`, `FOLD round`.. (frame) | | |

- The NS scalars of step 3 and the NPr of step 5 are the message of the step's `BAT-sigma`; the claimed sum of steps 6, 7, 8 is in the step's `PSC epsilon` before the hiding polynomial's sum; steps 2, 9, 12 and step 11's `BAT-sigma` have an empty prover's message [11.4:81-84].
- Step 8: the first lt rounds bind the bits of the position, highest first; further round i (from 0) binds bit lPd - 1 - i of the feature's index; the claimed sum that is sent is 2^(-lPd) times the sum that the lookup's join needs [11.4:86-89]. It is ONE sumcheck of lt + lPd rounds, all equality rounds [11.4:186-187].
- End values in the order sent: step 6 the NO row values; step 7 the reciprocal, then the weighted stream; step 8 the activations' value, then the value of the one weight claim (which the merge starts from) [11.4:91-93].
- **Late in the head, different from 11.2:** the merge (step 11) comes AFTER the smallness test, directly before the last round; its `BAT-sigma` samples an element of which only the power 0 is used [11.4:180-183]. Here the lookup's join is a claim of its own (group 8) [11.4:188-189].

**What enters the chain late (summary).** (1) y enters the chain's hash only as the prover's `REPLY` message, i.e. after every G_g and A_g sub-proof has run; "every value that the verifier samples later depends on it" [FORMAT:1302-1303]; no first query binds it [FORMAT:1291-1292]. (2) win_(T-1) is the y of the PROOF, not of the call; the frame compares the two afterwards [11.4:932-933]. (3) The request's r and e are used by no earlier segment: they enter three weight vectors of the head (parts 2, 11, 12 of `U3`) and "change no length and no order" [11.4:133]. (4) The request's tokens are used twice: in G_0 (tokw, 3.11) and here (win_t).

### 5.5 The head's lookup: calls, table of exponentials, keys

Lines `callH NAME KIND SEGMENT ..`; kinds R8, R16, FC and FE (the table of exponentials); at most 6 calls; the other tests of 11.2 apply except the one on the names V, a, b, E. Without such lines the list is the six default lines (their text is hashed, R15.6). n_c = lJ + lt, lJ as in 11.2 and at least nminH - lt (nmin - lt without the line `nminH`). Each `iotaH_0..5` must equal n_c - dT, and 0 for an absent call [11.4:135-144; FORMAT:1275-1277]. Both examples [pol-full:179-184; pol-small:178-183]:

```
callH R16a R16 NF NFH HD0
callH R16b R16 HD1
callH R8 R8 ROW HD2
callH FEa FE HE0
callH FEb FE HE1
callH FC FC CNF
```

Table of exponentials, integers only [11.4:146-158]: row u, u = 0..65535, is u + 2^16 EX[u]; g_0 = 2^(F + 17); EX[u] = ceil(g_u / 2^17); g_(u+1) = ceil(g_u N / 2^32); F = 24. N = 484 if sT + 4 = sh; otherwise sh + 4 <= sT <= sh + 10 and N is entry sT - sh - 4 of 4034748383, 4162825045, 4228380000, 4261543596, 4278222806, 4286586875, 4290775040. Padding key of a FE call = row 0. With N = 484 the values are 2^F, 2, 1, 1, ..: the **step table**. "A whole call takes the step table alone": a parameter file with sT + 4 != sh is rejected with the name `policy` before the stages.

Keys [11.4:535-550] (k a feature, v a vocabulary entry, j a digit's number):

| segment | table | length | key at (x, t) |
|---|---|---|---|
| NF | R16 | d | rl[t][k] = str[t][k] R_t + 2^(`KF`-1) - 2^`KF` aw[t][k] - 2^16 rh[t][k] |
| NFH | R16 | d | 2^(32 - `KF`) rh[t][k] |
| HD0 | R16 | JV | K_0[t][v] = iw (Mg[t][v] - 2^`sh` K_1 - K_2) at a real pair; - iw (2^`sh` d1 + d2) at any other pair |
| HD1 | R16 | JV | K_1 = 32896 + d1 at a real pair; d1 at any other pair |
| ROW | R8 | NRH | mul_j D_j of position t |
| HD2 | R8 | JV | K_2 = 128 + d2 at a real pair; d2 at any other pair |
| CNF | FC | d | (aw + 32768) + 2^28 (act + 2048) |
| HE0 | FE | JVa | the key of HD1 at (v, t), plus 2^16 ex[t][v], for v = x |
| HE1 | FE | JV - JVa | the same for v = JVa + x |

K_0 has no cell: its key is formed in the field with iw = the inverse of 2^(`sh`+15) [11.4:474, 547]. Keys of HD0, HD1, HD2 in the columns of entries v >= V count as padding keys (0); those of HE0, HE1 too (2^(16 + `F`)); all are read from the cells all the same [11.4:547-550]. Padding per tree: npad = T for each column no call's segment takes and T for each column that HD0, HD1, HD2, HE0 or HE1 takes for a vocabulary entry from V on; a key at a position with on_t = 0 in the column of an entry below V is NOT padding, so npad does not depend on the request [11.4:476-481].

Public weights [11.4:460-474]: ew_sg[x] = eq(zj_c, pos_sg(x)); wsum_sg = sum over all x; wx_sg (for HD0, HD1, HD2, HE0, HE1) = sum of ew_sg[x] over the x whose vocabulary entry is below V (entry x stands for vocabulary entry x; in HE1 for JVa + x); ewh_sg[i] = eq(first lJ_c - ls of zj_c, pos_sg(S2 i)/S2); padW_c = sum of eq(zj_c, j) over the columns no call's segment takes; pad_c = 0 for R8 and R16, 32768 + 2^39 for FC, 2^(16 + `F`) for FE; ON = sum of eq(zt, t) over t with on_t = 1; phiC[t] = eq(zt, t) if co_t = 1 else 0; ERC = sum_t phiC[t]; rhoC[t] = co_t; place_HD0 = sum over t with on_t = 1 of eq(zt, t) times sum of ew_HD0[v] over v < win_t; pub_HD0 = 0.

### 5.6 The row of digits, points, scalars, parts of `U3`

Row [11.4:334-388]: NRH digits per position; the first NR are the final norm's with the same fields as a layer's norm (3.8) but with epsF and `MF`; the last 21 hold the six hidden numbers, all mul_j = 1: gc_t = dig(NR, 5); gb_t = D_(NR+5); gu_t = dig(NR + 6, 5); gk_t = dig(NR + 11, 5); gz_t = dig(NR + 16, 2); gs_t = dig(NR + 18, 3); (dg0_i, dgn_i) = (0,5), (5,1), (6,5), (11,5), (16,2), (18,3). Read through part n in 7..10: D_j(n) = part_n[j] + 128.

Points [11.4:437-450]: zk_c = (zj_c, zt), the key of column j and position t has index j T + t; zt = the lookup's token point; zl = the ls coordinates before the last lt of every key point, (zl, zt) = last la of zx; pV = step 2's elements in the order sampled; gam (step 3); rW = step 4's challenges (first lPd belong to the feature k, last lt to the position; its equality point is lPd times 1/2, then pV); om (step 5); rV, rN = challenges of steps 6, 7; rH = the first lt challenges of step 8; rs_i = the challenge of the round of step 8 that binds bit i of the feature (further round n gives rs_(lPd - 1 - n)); rsP = (rs_(lPd-1), .., rs_0). The element of step 4's `LINE` enters no formula.

Scalars [11.4:416-431] (j_3 = number of scalars of step 1; m_4 = lPd + lt):

| name | number | hidden value |
|---|---|---|
| W_s, s < NS | j_3 + s | sum_t eq(pV, t) W_s[t], W_s[t] = sum_{k<d} sum_{lb+lb'=s} cell_xbL(lb d + k, t) cell_xbL(lb' d + k, t) |
| vL_4, vR_4 | j_4 + 2 m_4 + 3, + 4; j_4 = j_3 + NS | both: the value at rW of the extension of XG[k T + t] = sum_lb gam^lb cell_xbL(lb d + k, t) (0 for d <= k < 2^lPd) |
| P_i, i < NPr | j_5 + i; j_5 = j_4 + 2 m_4 + 5 | sum_t eq(pV, t) times row product i |
| Cl_V | j_6 = j_5 + NPr | sum_i om^i P_i |
| EV_j, j < NO | j_6 + 2 lt + 4 + j | sum_t eq(rV, t) times a, b, Rlo, Rhi |
| Cl_N | j_7 = j_6 + 2 lt + 4 + NO | sum_t eq(zt, t) R_t SX[t], SX[t] = sum_{k<d} ew_NF[k] str[t][k] |
| EN_0, EN_1 | j_7 + 2 lt + 4, + 5 | sum_t eq(rN, t) R_t; sum_t eq(rN, t) SX[t] |
| Cl_H | j_8 = j_7 + 2 lt + 6 | 2^(-lPd) sum_t sum_{v<V} eq(zt, t) on_t ew_HD0[v] (lam_t[win_t] - lam_t[v]) = 2^(-lPd) sum_{t,k<d} eq(zt, t) act[t][k] UH[k][t] |
| EH_0, EH_1 | j_8 + 2(lt + lPd) + 4, + 5 | EH_0 = sum_{k<d,t} eq(rsP, k) eq(rH, t) act[t][k]; EH_1 = the same with UH[k][t] = on_t (wx_HD0 Wh[k][win_t] - sum_{v<V} ew_HD0[v] Wh[k][v]) |

The smallness test's lookup begins at number j_8 + 2(lt + lPd) + 6; the merge takes the last 2 lkW + 3 numbers [11.4:428-429].

Parts of `U3` [11.4:498-512]:

| n | matrix | entries | phi |
|---|---|---|---|
| 1 | hf | NHf k_hf 2^(lmhf - la) | phi[j T + t] = eq(zl, j) eq(zt, t) |
| 2 | hf | as part 1 | phi[j T + t] = phiC[t] |
| 3 | xbL | k_x 2^(lmx - la) | eq(rWl, j) eq(rWt, t); rWt = last lt of rW, rWl = the ls coordinates before them |
| 4 | xbL | as part 3 | eq(zl, j) eq(rN, t) |
| 5 | hd | k_hd 2^(lmhd - lt) | eq(zt, t) |
| 6 | hd | as part 5 | eq(rH, t) |
| 7, 8, 9, 10 | hr | k_hr 2^(lmhr - lt) each | eq(zt, t); eq(pV, t); eq(rV, t); eq(rN, t) |
| 11 | hr | as part 7 | phiC[t] |
| 12 | hr | as part 7 | rhoC[t] |
| 13, 14, 15 | bH | NC 2^(kT + 5 - lmbH) each | phiB_0, phiB_1, phiP = 2^(row mod 32) |

Three short forms [11.4:519-527]:

```
SL(sg, f0, nl, fs) = sum_{i < n_sg/S2, lb < nl} 256^lb ewh_sg[i] part_1[(f0 + lb fs)/S2 + i]
HN(n, i)           = sum_{lb < dgn_i} 256^lb (part_n[NR + dg0_i + lb] + 128 ws_n),   n = 11 or 12, ws_11 = ERC, ws_12 = RC
A2(n, k)           = part_n[k] + 256 part_n[d + k],   n = 5 or 6, k < d
```

### 5.7 Key forms

KF_c = pad_c padW_c + [NF is in call c] Cl_N + sum of KS_sg over the call's segments of call c [11.4:554-571]:

```
KS_NF  = wsum_NF (2^(KF-1) - 32896 2^16) - 2^KF SL(NF, 0, 2, d) - 2^16 SL(NF, 2d, 2, d)          (the term str R is in Cl_N)
KS_NFH = 2^(32-KF) (32896 wsum_NFH + SL(NFH, 2d, 2, d))
KS_HD1 = 32896 wx_HD1 ON + SL(HD1, 4d, 2, JV)
KS_HD2 = 128 wx_HD2 ON + SL(HD2, 4d + 2JV, 1, JV)
KS_HD0 = iw (2^lPd Cl_H + wx_HD0 (HN(11,0) + BIG HN(11,1)) - place_HD0 - pub_HD0
             - 2^sh (32896 wx_HD0 ON + SL(HD0, 4d, 2, JV)) - (128 wx_HD0 ON + SL(HD0, 4d + 2JV, 1, JV)))
KS_HE0 = 32896 wx_HE0 ON + SL(HE0, 4d, 2, JV) + 2^16 (offE wsum_HE0 + SL(HE0, 4d + 3JV, 3, JV))
KS_HE1 = 32896 wx_HE1 ON + SL(HE1, 4d + JVa, 2, JV) + 2^16 (offE wsum_HE1 + SL(HE1, 4d + 3JV + JVa, 3, JV))
KS_ROW = sum_{j<NRH} mul_j ew_ROW[j] (part_7[j] + 128)
KS_CNF = SL(CNF, 0, 2, d) + 2^28 (sum_{k<d} ew_CNF[k] A2(5, k)) + wsum_CNF (2^15 + 2^39)
```

An offset that exists only at the real pairs has the weight wx_sg ON; offE exists at every pair and has the weight wsum_sg; SL reads the cells at every pair [11.4:573-576].

### 5.8 Sumchecks of the head

| step | kind | variables | form, degree | d_Y | end values | start form | equality point | S0 |
|---|---|---|---|---|---|---|---|---|
| 4 | product level, default order | lPd + lt | equality, 2 | 2 | vL_4, vR_4 | C_4 = 2^(-lPd) sum_{s<NS} gam^s W_s | lPd times 1/2, then pV | vL'_4 vR'_4 |
| 6 | token sumcheck | lt | equality, 2 | 2 | EV_0..EV_(NO-1) | C_6 = Cl_V | pV | EV'_0^2 + om EV'_0 EV'_1 + om^2 EV'_1^2 + om^3 EV'_2 EV'_0 + om^4 EV'_2 EV'_1 + om^5 EV'_3 EV'_0 + om^6 EV'_3 EV'_1 |
| 7 | token sumcheck | lt | equality, 2 | 2 | EN_0, EN_1 | C_7 = Cl_N | zt | EN'_0 EN'_1 |
| 8 | token sumcheck + lPd appended rounds | lt + lPd | equality, 2 | 2 | EH_0, EH_1 | C_8 = Cl_H | zt, then lPd times 1/2 | EH'_0 EH'_1 |
| 11 | merge, one claim | lkW | plain, 2 | 1 | fv' | C = EH_1 | none | fv' |

[11.4:61-79, 611-612, 620-622, 650, 681, 686, 691-693]. `(reading)`: step 7 proves the "term" str R of the key of NF (the weighted stream times the reciprocal); step 8 proves the logit differences as act times the public-weighted combination UH of the head's weights, leaving EH_1 as the single weight claim.

### 5.9 Claims in order (items 1-27, groups 1-13)

First claim numbers [11.4:586-600]: group 1: 0; 2: cn_2 = 32 + v' + d'; 3: cn_2 + 3; 4: cn_2 + 5; 5: cn_2 + 5 + NO; 6: cn_2 + 5 + NO + NS; 7: cn_7 = cn_2 + 5 + NO + NS + NL (NL = 8 with five limbs); 8: cn_7 + 3; 9: cn_7 + 4; 10: cn_7 + 8; 11: cn_7 + 11; 12: cn_12 = cn_7 + 11 + 36 + v'' + d'' + NM + NX; 13: cn_12 + 2; NCm = cn_12 + 3. For the machinery: jLK = 0, LK0 = claim 0, LJ = cn_7 + 3, LP0 = cn_7 + 8; the smallness test's lookup has jLK = j_8 + 2(lt + lPd) + 6 and its first claim is cn_7 + 11 [11.4:602-605]. NM = NHf + 4; NX = 2 NHf 2^(lmhf - la) + 2 * 2^(lmhd - lt) + 6 * 2^(lmhr - lt) + 3 + 2 * 2^(lmx - la) [11.4:114-115].

| group | items | claims |
|---|---|---|
| 1 | - | the lookup's 31 + v' + d' + 1 claims on mask entries alone [11.4:607] |
| 2 | 1-3 | Left(C_4; vL'_4 vR'_4; 0) = 0; vL_4 - vR_4 = 0; vL_4 - sum_{i<d/S2, lb<XL} eq(first lPd - ls of rW, i) gam^lb part_3[lb d/S2 + i] = 0 [11.4:611-615] |
| 3 | 4-5 | Cl_V - sum_{i<NPr} om^i P_i = 0; Left(C_6; S0; 0) = 0 [11.4:619-622] |
| 4 | 6 | EV_0 - a(9) = 0; EV_1 - b(9) = 0; EV_2 - Rlo(9) = 0; EV_3 - Rhi(9) = 0 (row read through part 9) [11.4:626-627] |
| 5 | 7 | s = 0..NS-1: W_s + c_s(8) - D_s(8) - 256 c_(s+1)(8) = 0 [11.4:631] |
| 6 | 8-15 | through part 8: LE0 P_1 - Blo - 2^23 Bhi = 0; LE1 Vlo + epsF - P_0 - 2^25 Blo - l1 + 2^48 kap = 0; LE2 Vhi - Bhi - P_2 - kap = 0; LE3 l1 + h1 - 2 sig = 0; LR1 P_4 + P_5 - q1 = 0; LR2 P_6 = 0; LR3 2^(`MF`+1) + sig - s0 - 2 P_3 - 2^25 q1 - 2 rr = 0; LR4 rr + rq - sig + 1 = 0 [11.4:636-643] |
| 7 | 16-18 | Left(C_7; EN'_0 EN'_1; 0) = 0; EN_0 - R(10) = 0; EN_1 - sum_{i<d/S2, lb<XL} 256^lb ewh_NF[i] part_4[lb d/S2 + i] = 0 [11.4:650-652] |
| 8 | 19 | LJ = 0: the join on the key forms KF_c, c = 0..NC-1 in call-list order [11.4:656-657] |
| 9 | 20-23 | the four policy equations (5.10) [11.4:661-668] |
| 10 | 24 | the lookup's three claims on the planes with TB_0(i) = part_13[i], TB_1(i) = part_14[i], TP(i) = part_15[i] [11.4:672-674] |
| 11 | - | the smallness test: 36 + v'' + d'' + NM + NX claims; its parts are 2 NHf + 13 in 11.1's count [11.4:676-677] |
| 12 | 25-26 | Left(C_8; EH'_0 EH'_1; 0) = 0; EH_0 - sum_{k<d} eq(rsP, k) A2(6, k) = 0 [11.4:681-682] |
| 13 | 27 | the merge's claim Left(C; fv'; 0) = 0 with C = EH_1 [11.4:686] |

"No claim says what EH_1 is: it is the value of the weight claim, and the pending row on the stored table is about it (11.5)" [11.4:688-689].

The weight claim (unit 13, the last unit; index groups (x, V, A) and (kk, d, low), d = o 2^z) [11.4:708-720]:

```
group x :  AV[v] = wx_HD0 psiH[v] - sR ew_HD0[v]   for v < V
           psiH[v] = sum of eq(rH, t) over the positions t with on_t = 1 and win_t = v;   sR = sum of eq(rH, t) over all t with on_t = 1
group kk:  pt = (rs_(z-1), .., rs_0);   HV[hi] = eq((rs_(lPd-1), .., rs_z), hi) for hi < o
claim   :  sum_{v<V, k<d} AV[v] eq(rsP, k) Wh[k][v] = EH_1
```

### 5.10 How the next token, the argmax, the gap and the clipped cost are bound

The policy touches the proof in exactly four claims plus the lookups on the margins' digits. With HN(12, i) = sum over the positions with a cost of hidden number i (weights rhoC) and HN(11, i) = the same under the lookup's token weights phiC:

| eq. | claim | in integers | cite |
|---|---|---|---|
| (B2) | HN(12,0) + `C` HN(12,1) + HN(12,2) - `theta` RC = 0 | sum over the positions with a cost of gc_t + `C` gb_t + gu_t = `theta` RC | [11.4:661-662] |
| (B3) | HN(12,1) + HN(12,4) - capR = 0, capR = `cap` if RC > 0, 0 if RC = 0 | sum of gb_t + gz_t = capR | [11.4:663-664] |
| (B4) | HN(11,0) + HN(11,3) - `C` ERC = 0 | sum_t phiC[t] (gc_t + gk_t - `C`) = 0 | [11.4:665] |
| (Z) | HN(11,5) + offE JV ERC - (JV - V + 1) 2^`F` ERC + sum_{lb<3, i<JV/S2} 256^lb part_2[(4d + 3JV + lb JV)/S2 + i] = 0 | sum_t phiC[t] (gs_t + sum_{v<JV} ex[t][v] - (JV - V) 2^`F` - 2^`F`) = 0 | [11.4:666-668] |

The argument, as the source's comments give it (upstream "states no property of the protocol") [11.4:868-911]:

- The bracket [v < win_t] "makes the first of equal logits the largest" [11.4:881].
- At a pair that is not real the three keys are d1, d2 and -(2^`sh` d1 + d2)/2^(`sh`+15), "which are in their lookup tables only if all three are 0"; with d1 = 0 the key of HE0/HE1 is a row only if ex is EX[0] [11.4:882-884].
- All six hidden numbers are at least 0 only by the lookup on their digits (ROW) [11.4:885].
- (B4), tested at the one point zt (sampled after the cells were committed), says gc_t + gk_t = `C` at each position with a cost, so gc_t <= `C` [11.4:886-888].
- (Z) says gs_t plus the position's V table values equals 2^`F`; gs_t >= 0, EX[0] = 2^`F` and every row is at least 1, so NO middle digit K_1 of the position is 0: gc_t + BIG gb_t is at least the logit gap plus 2^`sh` [11.4:889-892].
- A position with gb_t = 0 has a cost of at most gc_t; a position with gb_t above 0 is charged at least `C`. Hence the costs, each clipped at `C`, add up to at most `theta` RC, and at most `cap` positions have a cost above `C` [11.4:900-902].
- **The next token:** position T - 1 has no cost, so its margins have no hidden number: y must be the index of the largest logit, the lowest index on ties [11.4:903-904]. `(reading)`: all V margins lam[y] - lam[v] - [v < y] must be sums of three non-negative digits, i.e. >= 0.
- Statement side: cost = gap + 2^sh under the step table; "the costs, each counted as at most C, add up to at most theta R; at most cap of them are above C; and, if e = T, y is the top choice of position T - 1" [FORMAT:1324-1338].
- (B4) and (Z) are statements on every position with a cost, each tested at one point zt with no round of its own [11.4:909-911].

Kind of a policy (enters no claim; printed in `covered:`; used for the rejection `policy`) [11.4:847-857; FORMAT:1364-1371]: `exact-match` if `C` = `theta` = 2^`sh`, `cap` = 0 and `sT` + 4 = `sh`; otherwise `clipped-gap` if `sT` + 4 = `sh`; otherwise `log-probability` if `sT` = `s`; otherwise `another-table`. A whole call takes the first two alone. Both examples are `exact-match`: `C 256`, `theta 256`, `cap 0`, `sh 8`, `sT 4`, `F 24` [pol-full:123-129; pol-small:123-129] (`s` is 15 full, 16 small). `(reading)` under `exact-match`: (B3) with capR = 0 forces every gb_t = 0; (B4) gives gc_t <= 2^sh; (Z) gives gc_t >= gap_t + 2^sh; so every gap is 0, i.e. every checked token is the top choice - which is what upstream says the kind means [FORMAT:1368].

"The number above the clip" for n = RC tokens [11.4:859-866]: least = 2^`sh`, most = min(`cap`, n); if `C` <= least the number is most; otherwise room = floor(n (`theta` - least) / (`C` - least)) if `theta` > least, else 0; the number is min(room, most).

### 5.11 What the verifier computes itself, tests and rejections

Verifier's own work: sizes and layouts; the EX table; pos_sg and the column weights ew, ewh, wsum, wx, padW; ON, phiC, ERC, rhoC, RC, capR; place_HD0; iw; the key forms; S0 of steps 4, 6, 7, 8; the digit-row forms through parts 7-12; the four policy equations' constants; psiH, sR, AV, pt, HV of the weight claim; all Left forms; the accumulation under chi. Costs in section 9.

Rejections:

- `header-y`: the `REPLY` element is not (y, 0, 0) with y < V [11.4:53-54, 300; FORMAT:1300-1302].
- `reply-differs` (frame): the proof's next token is not the caller's [FORMAT:1296-1300].
- After the last claim (`internal-h-free-slot`, prefix `H:`): the coefficient of hidden(j) in the sum of all claims must be 0 for the number of the merge's end value fv' and different from 0 for each other number j of the segment; "not a self-check but a test on content of every verifier" [11.4:695-704].
- Smallness-test events as in every segment (FORMAT 13.9, events 2-8).
- Public-file tests before reading a proof: ranges [11.4:729-742], no-overflow conditions 1-13 [11.4:790-804], names in section 8.3. The formulas also assume S2 divides d (`shape-la`), 2 <= V <= 2^24 (`shape-V`), `wb_head` = 13 (`policy-weight-kind`) [11.4:758-760].
- Parameter-file policy tests [11.4:164-166, 733]: `theta` <= `C`; `cap` <= T; `cap` < 2^16; `F` = 24; `s` <= 63; `sh` is 7 or 8; `sT` + 4 = `sh` or `sh` + 4 <= `sT` <= `sh` + 10; S2 divides JVa; 2 V <= 2^`F`; `toksrc` = 1.
- Standard parameter form on the head's numbers: `five-limbs`, `norm-shifts` (`KF` <= `MF`), `exact-match`, `policy-named`; `next-token` is a condition of the command `cp_verify` alone [11.4:768-773].

Upstream's traps [11.4:178-191, 913-940]: offsets 32896 and 128 of a margin's lower digits have weight wx_sg ON while offE has weight wsum_sg; three weights of one call's segment (wsum over all entries, wx over entries below V, padW over untaken columns: the columns of entries from V on are in wsum, not in wx, not in padW); HE1 is shifted by JVa in the features read and in wx_HE1; Cl_H holds 2^(-lPd) times the sum and KS_HD0 multiplies it by 2^lPd, while step 4's 2^(-lPd) is never taken back; a digit read through parts 7-10 gets 128, through part 11 128 ERC, through part 12 128 RC; capR is 0 if no position has a cost; groups 3 and 4 come before group 5 although the W_s were sent first; pV is used as sampled while the two lookup points sampled in one round are reversed.

## 6. Consolidated table of verifier-side check kinds (11.2-11.4)

"Machinery" names refer to 11.1 (another researcher's scope).

| # | check kind | where used | machinery it calls | inputs it needs from this scope | outputs |
|---|---|---|---|---|---|
| 1 | scalar form (canonical element, bytes present, proof of work) | every round | frame / 11.1 [11.1:42-44] | - | reject on form |
| 2 | `REPLY` element form (`header-y`) | H only | none | the element, V | y; reject |
| 3 | sampled point (`ZERO`, `JOIN`) | G: steps 2, 3, 5, 13. A: row 9. H: step 2 | "steps of one round" [11.1:56-61] | number of coordinates; G/H points are used as sampled, highest bit first [11.2:452-453; 11.4:937-940] | a point |
| 4 | batching element (`BAT-sigma`) | G: 4, 7, 10, 16, 19. A: 6, 10, 12, 14, 22. H: 3, 5, 11, 12 | [11.1:61-64] | n; waiting scalars | powers x^i |
| 5 | hidden value sent alone | G: W, P, Cl_8, Cl_9, v_E. A: R, PV, MV, SV, ACC, ZO, ZC, RH, RHP, IB, RH2, RHP2, CL0, CL1, M6. H: W_s, P_i, Cl_V, Cl_N, Cl_H | mask row [11.1:447-455] | its place in the order | (shown, factor 1) |
| 6 | product level (equality rounds, degree 2, d_Y 2, 2 end values, `LINE`) | G: step 6 (default order), 12, 14 (range order). H: step 4 (default) | product level [11.1:110-118, 660-681] | start form, equality point, order | Left claim; challenge point; 2 follow-up claims on vL, vR |
| 7 | token sumcheck (lt equality rounds of degree 2 after a claimed sum) | G: steps 8, 9. H: steps 6, 7, 8 (8 with lPd appended rounds at 1/2) | token sumcheck [11.1:120-124, 653] | point, d_Y, end values, S0 | Left claim (G step 9: the form goes into C_11); end-value claims |
| 8 | plain-round degree-2 sumcheck over panels | G: step 11 | `stackRounds` [11.1:654]; eqlow [11.1:683-688] | C_11, panel list, As, Bs | Left claim; A0 - Alin, B0 - Blin |
| 9 | batched product sumcheck, plain rounds of degree 3 | A: K_u (x nKF), SE, VM, VD, SF, HB | `sc3` [11.1:655] | start form, W_b at the point | LEFT; two end-value claims per product |
| 10 | sumcheck with a degree per round (2, lt + 2, lt + 1; d_Y = lt + 1) | A: SD | `scd` [11.1:656] | start form, S0 formula | LEFT; KC and IBP claims |
| 11 | lookup (shift, comparison point, tie, key side, table side, leaves, bits) | every segment, first step | lookup [11.1:126-178, 690-963] | ordered call list with (n_c, k_c, table, padding row); npad(y); jLK; claim numbers; TB_0, TB_1, TP as `U3` parts | zx, zy, zk_c, e_c, alpha, theta, C_end, zb_0, zb_1; 31 + v + dL + 1 mask-only claims; LP0-LP2 |
| 12 | join of keys to the key side | A: group 5. H: group 8. G: folded into the start form C_11 (no claim) | join [11.1:905-917] | key forms KF_c (A, H) or JP_c + Cl_9 + KT (G) | 1 claim, or none |
| 13 | smallness test (cells are small; `U3` entries are sums of cells) | every segment | third piece of 11.1 | ordered list of matrices (m_mu, k_mu), ordered list of `U3` parts with their weight vectors, tau | `RNG` matrix; lookup on digits; TIE_mu, READ_q claims; events 2-8 |
| 14 | merge of weight claims | G: step 16 (n = NCL, before `U3`). H: step 11 (n = 1, after the smallness test) | merge [11.1:202-218, 965-996] + 11.5 | values v_a (hidden numbers), per-claim unit and factors (3.11, 5.9) | Left claim; fv', beta, point, x for the pending row |
| 15 | end-value binding claim (hidden value minus an affine form in `U3`) | all three | none (form arithmetic) | readings RS/RL/RX; PL/LV/XL/OG; part_n, SL/HN/A2 | one claim each |
| 16 | linear relations on a norm's digit row (carries; LE0-LE3, LR1-LR4) | G: groups 5, 6 (NI norms). H: groups 5, 6 | none | digit forms at PV / pV, eps, M | NS + 8 claims per norm |
| 17 | consistency of batched scalars | G: group 3 (1). A: group 6 (1), group 8 [BE] - [AE] + 1. H: item 4 | none | batching powers | claims |
| 18 | one-hot sum | G: group 10 | none | RS(`sel`, zt, lamM, e) | LamM claims |
| 19 | acceptance-policy equations (B2), (B3), (B4), (Z) | H: group 9 | none | HN forms, `C`, `theta`, `cap`, RC, ERC, V, JV, `F`, offE | 4 claims |
| 20 | final batching under chi into the segment's one equation | every segment, last own round | "the one equation" [11.1:502-532] | all claims in the fixed order | column weights L per combined row, LS(j), c0 -> MC(j), TG for the frame |
| 21 | free-scalar test (every scalar has a non-zero coefficient; fv' exactly 0) | every segment after chi | FORMAT 13.9 event 9 | LS(j) | no acceptance |
| 22 | `coin-zero` (eps_9 != 0) | G only | FORMAT 13.9 event 1 | eps of step 9 | reject |
| 23 | public-file tests (shape, scale file, call lists, no-overflow) | before any proof byte | section 13 | the three public files | reject with a name |

## 7. Size of the job

All numbers below are DERIVED by my script from the formulas cited in sections 3-5 (not printed by upstream), except where a citation is given. For the full-size configuration every derived intermediate agrees with upstream's worked examples: call key bits, dT, NT, v, dL, mz, v_Z, lamS and all per-step scalar counts [11.2:219-227; 11.3:200-206; 11.4:170-176], and the per-segment column counts 24,086 / 10,248 / 20,703 and the total 432,711 [FORMAT:2504-2507]. For the small example there is no upstream worked example: treat the column as an estimate validated only by `iota_3 1`, `iotaA_0 52`, `iotaH_* 0` [pol-small:84-91, 104, 117-122].

Segments: full-size NG = 12, so 12 G + 12 A + 1 H = 25 [FORMAT:2497-2498]; small NG = 2, so 5.

Lookup sizes (n_c in call-list order):

| | G full | A full | H full | G small | A small | H small |
|---|---|---|---|---|---|---|
| n_c | 27,27,27,28,27,27,26,26 | 27,27,26,25 | 28,28,28,27,27,27 | 20,20,20,21,20,20,20,20 | 20,20,20,20 | 20 x 6 |
| dT / NT / rK | 26 / 16 / 4 | 25 / 11 / 4 | 27 / 9 / 4 | 20 / 9 / 4 | 20 / 4 / 2 | 20 / 6 / 3 |
| v, dL | 30, 19 | 29, 18 | 31, 19 | 24, 19 | 22, 18 | 23, 19 |
| mz; v_Z | 499,712; 27 | 221,184; 26 | 385,024; 27 | 65,536; 24 | 30,720; 23 | 40,960; 24 |

Per segment (G shown for g >= 1; group 0 adds: 1 scalar, 1 weight claim, 1 `U3` part, 1 committed matrix, +2 claims at full size, +33 at small because xbI@ZE adds 2^(lmx - la) reads):

| quantity | G full | A full | H full | G small | A small | H small |
|---|---|---|---|---|---|---|
| lookups (own + smallness) | 2 | 2 | 2 | 2 | 2 | 2 |
| sumchecks, total | 160 | 158 | 159 | 151 | 148 | 148 |
| - inside the own lookup (33 + v + dL) | 82 | 80 | 83 | 76 | 73 | 75 |
| - the segment's own | 7 (steps 6, 8, 9, 11, 12, 14, 16) | 8 (2 K_u, SE, VM, VD, SF, SD, HB) | 5 (steps 4, 6, 7, 8, 11) | 7 | 8 | 5 |
| - inside the smallness lookup (44 + v_Z) | 71 | 70 | 71 | 68 | 67 | 68 |
| `PSC round` rounds, total | 1,379 | 1,295 | 1,356 | 1,098 | 996 | 1,038 |
| scalars | 4,058 (g0: 4,059) | 4,190 [11.3:205] | 3,570 | 3,203 (g0: 3,204) | 3,076 | 2,879 |
| claims NCm | 801 (g0: 803) | 767 | 297 | 1,516 (g0: 1,549) | 1,191 | 897 |
| - of which reads NX | 183 (g0: 184) | 80 | 93 | 1,155 (g0: 1,187) | 838 | 707 |
| equation numbers Q | 32,004,992 | 14,166,016 | 24,653,440 | 4,342,144 | 2,073,344 | 2,711,936 |
| matrices in the smallness list NM | 9 | 5 | 8 | 9 | 5 | 5 |
| columns of those matrices (x tau = `RNG` entries) | 24,086 | 10,248 | 20,703 | 3,099 | 1,276 | 1,594 |
| `U3` entries | 407,226 (g0: 407,626) | 60,640 | 61,680 | 166,688 (g0: 167,328) | 34,152 | 11,264 |
| packed matrices committed at moment 0 | 8 (g0: 9) | 4 | 7 | 8 (g0: 9) | 4 | 4 |
| arrays in all (+ `U3`, `ZZ`, `BZ`) | 11 (g0: 12) | 7 | 10 | 11 (g0: 12) | 7 | 7 |
| oracle-message lines in `layout.txt` | 5 | 3 | 3 | 5 | 3 | 3 |
| weight claims | 32 (g0: 33) | 0 | 1 | 32 (g0: 33) | 0 | 1 |
| largest sumcheck degree | 2 | lt + 2 = 12 (SD) | 2 | 2 | lt + 2 = 8 (SD) | 2 |

Scalars per step, full size, from upstream: G: step 1: 1,930; 4: 72; 6: 57; 7: 56; 8: 56; 9: 289; 11: 86 (lamS = 23, NCL - E0 = 32); 12: 57; 14: 53; 16: 39; 18: 1,363 [11.2:225-226]. A: row 3: 1,812; 4: 199; 5: 99; 7: 93; 8: 82; 10: 20; 11: 103; 13: 382; 15: 94; 21: 1,306 [11.3:204-205]. H: step 1: 1,995; 3: 9; 4: 51; 5: 7; 6: 28; 7: 26; 8: 52; 10: 1,363; 11: 39 [11.4:174-175]. Small (derived): G: 1,582; 72; 41; 56; 48; 33; 70 (lamS = 15); 41; 37; 25; 1,198. A: 1,427; 121; 53; 45; 40; 8; 61; 122; 52; 1,147. H: 1,531; 9; 35; 7; 20; 18; 36; 1,198; 25.

Attention sumcheck variables (full / small): K_u `FM` 17 / 11; K_u `FD` 14 / 10; SE 13 / 7; VM 16 / 8; VD 13 / 7; SF 20 / 14; SD 23 / 13; HB 17 / 11 (from [11.3:153-164]). Attention shape numbers: NP = 20 / 8; nM = 22 / 12; nD = 19 / 11; kAs = 7,200 / 120; fillH = 2,880 / 256; fillO = 40,960 / 4,096; kbA = 512 / 1,024; cells of as in use = 471,859,200 / 245,760.

Whole first chain, sub-proofs only (frame rounds, proximity tests and the other two chains excluded):

| quantity | full-size | small |
|---|---|---|
| segments | 25 | 5 |
| lookups | 50 | 10 |
| sumchecks | 3,975 | 746 |
| `PSC round` rounds | 33,444 | 5,226 |
| scalars | 102,547 | 15,438 |
| claims (sum of NCm) | 19,115 | 6,344 |
| equation numbers (sum of Q) | 578,705,664 | 15,547,008 |
| `U3` entries | 5,676,472 | 413,584 |
| columns of the smallness lists | 432,711 [FORMAT:2506] | 10,344 |
| ternary entries sampled in `RNG` (columns x tau, tau = 128) | 55,387,008 | 1,324,032 |
| packed matrices committed | 152 | 29 |
| arrays in all | 227 | 44 |
| `layout.txt` oracle-message lines | 99 | 19 |
| weight claims -> pending rows | 386 -> 13 | 66 -> 3 |

Upstream cross-checks on scale: "At full size n is about 32 million in a feed-forward segment" (n = NCm + Q of the last `BAT-sigma`) and "a segment has fewer than 2^22 weights under test, about 3.4 million in a feed-forward segment" [FORMAT:2518-2520]; the model has 3,076,096 matrix rows and 13 pending rows at full size, 59,392 and 3 at `target_small_f2` [08:846-848]. Note the small example has MORE claims per segment than the full-size one, because with lt = 6 the short parts of `U3` have many blocks (NX grows as 2^(lm - lt)).

## 8. Rule index

### 8.1 Numbered rules: none are defined in 11.2-11.4

The three files define no `Rn.m` rule. They reference these (definition site given):

| ID | one-line statement | defined at | used in 11.2-11.4 at |
|---|---|---|---|
| R1.2 | base field F = Z/p; field 2 has p = 2^64 - 2^32 + 1; the programs build for field 2 alone | FORMAT:98 | 11.2:1073; 11.3:983-984; 11.4:782-783 |
| R1.5 | a digest is any 32 bytes, written with no length before it | FORMAT:109 | 11.3:150 |
| R4.3 | the parameters' bytes; a plan entry of a batching round holds its number of rows | FORMAT:287 | 11.3:185-186 |
| R5.1, R5.2 | rounds of a chain; call j of round i | FORMAT:441, 448 | 11.3:8 |
| R6.2 | order of a round's sampled values | FORMAT:503 | 11.3:9 |
| R6.5 | an element of E that is not 0 (the beta of `PSC Y`) | FORMAT:519 | 11.3:128 |
| R6.7 | n entries of a matrix over {-1, 0, 1} (the `RNG` round) | FORMAT:530 | 11.3:167, 181 |
| R6.9 | the seed of an out-of-domain sample | FORMAT:539 | 11.3:150 |
| R7.12 | which oracle messages share a tree | FORMAT:721 | 11.3:10, 150 |
| R8.2, R8.3, R8.4, R8.7 | items of a chain in a file; answers after a round of kind 3; the hiding polynomial's sum is the last item; where an opening is | FORMAT:873, 900, 917, 933 | 11.3:9, 126, 151, 178-179 |
| R14.3 | the first chain's first query; item `links' identifiers` | 10:70-79 | 11.2:12-13; 11.3:19; 11.4:21 |
| R14.4 | the first chain's rounds; the frame's own rounds of a segment; (a) index-mask message, (d) later moments | 10:191-233 | 11.2:8, 63, 69, 86; 11.3:10, 176; 11.4:8, 64, 73 |
| R14.5 | the item `layout` (arrays, blocks) | 10:131-170 | 11.2:34; 11.3:90-91; 11.4:28 |
| R14.8 | the next token: one unmasked element of E in a round `REPLY` | 10:254-259 | 11.4:9, 51-57, 63, 933 |
| R14.11 | the names of the format's rounds | 10:465 | 11.3:14-15 |
| R15.6 | the digests that are computed; the six default `callH` lines | FORMAT:1272-1286 | 11.4:140 |
| R15.7 | the next token's position; y as the element (y, 0, 0) | FORMAT:1290-1294 | 11.4:57 |

### 8.2 Identifiers that 11.2-11.4 do define (candidates for spec rule IDs)

| family | IDs | where |
|---|---|---|
| G computation lines | lines 1-21 | 11.2:324-377 |
| G steps | steps 1-19 | 11.2:67-91 |
| G claim groups | groups 1-15 | 11.2:124-140, 876-965 |
| G norm lines | LE0, LE1, LE2, LE3, LR1, LR2, LR3, LR4 | 11.2:907-914 |
| G `U3` parts | no. 1-21, "matrix@point" | 11.2:490-500 |
| G panels | 11 rows, two passes | 11.2:770-782 |
| G rounding-site conditions | U-nm, W-nm for nm in gate, up, norm, down, qk, o, v, lr | 11.2:1083-1098 |
| A function steps | 1-7 | 11.3:308-323 |
| A rows | rows 1-25 | 11.3:148-174 |
| A sumchecks | K_u (`FM`), K_u (`FD`), SE, VM, VD, SF, SD, HB | 11.3:621-641 |
| A claim groups | groups 1-10 | 11.3:686-796 |
| A `U3` parts | no. 1-20: tA, tVM, tVD, tM_u, hW, hX, hE, hT, hPi, hR2, tO, tQ_u, tK_u, qO, qVM, qVD, qF, qKx, tB_0, tB_1, tP | 11.3:577-598 |
| A no-overflow conditions | N1, N2, N3, N4, N5, N6, N9 ("The names N7 and N8 are not in use") | 11.3:981-994 |
| A causal-mask ingredients | 1-4 | 11.3:887-909 |
| H integers | items 1-9 | 11.4:257-289 |
| H steps | steps 1-12 | 11.4:61-79 |
| H claims | items 1-27 in groups 1-13 | 11.4:586-689 |
| H policy equations | (B2), (B3), (B4), (Z) | 11.4:661-668 |
| H key forms | KS_NF .. KS_CNF, 1-9 | 11.4:558-571 |
| H `U3` parts | n = 1-15 | 11.4:498-512 |
| H no-overflow conditions | 1-13: U-NF, W-NF, W-HD0 (two), three-digits (two), HE, Z, E2, E3, E4, J-E, guard-radix | 11.4:790-804 |

### 8.3 Rejection names stated in 11.2-11.4

Feed-forward (prefix of content tests: `G<g>:`):

| name | a verifier rejects unless | line |
|---|---|---|
| `policy-call-list` | at most 8 calls; every line has a call's segment; names differ; no call named V, a, b, E; exactly the segments the parameters call for, each once, in a call of its kind | 11.2:202-209 |
| `policy-call-line` | form of a call line; a call's name has at most 8 characters | 11.2:204-210 |
| `shape-words` | 4 <= lt <= 16; 1 <= ll <= 6; 1 <= d, f <= 2^20; nmin <= 28; with routed experts fe is a power of two, f = 2 fe, not (ll = 1 and fe = 1) | 11.2:1032 |
| `shape-L` | L >= 1 and Lam divides L | 11.2:1033 |
| `shape-la` | lt < la <= 16; 2^ls divides d, f, dkv, nqk (and fe); lmq >= la; lmaf >= la | 11.2:1034 |
| `shape-heads` | H, G >= 1; dh a power of two >= 2; H dh = d; H + G <= 64 | 11.2:1035 |
| `shape-NE` | with routed experts NE is a power of two from 2 to 4096 | 11.2:1036 |
| `policy-norm` | 1 <= eps1, eps2 < 2^59 | 11.2:1037 |
| `policy-cs`; `policy-ut` | `cs` is 12; `ut` is 1 | 11.2:1038 |
| `policy-forms`; `header-absent-class` | every digit form <= 2; hr = 0 without routed experts | 11.2:1039 |
| `policy-gcl`; `policy-rcl` | `gcl 1`, `rcl 1` only with routed experts | 11.2:1040 |
| `shape-request-matrix` | lt <= lmaf, lmad, lmar, lmq <= 24; 1 <= NAf, NAd <= 64; la <= lmx <= 24 | 11.2:1041 |
| `shape-lmb` | lmb <= 24 | 11.2:1042 |
| `forest-planes` | 5 <= lmb <= kT + 5 | 11.2:1043 |
| `shape-call-<name>` | max(10, nmin, la) <= n_c <= 44; lJ_c >= ls; `iota_<c>` = n_c - dT | 11.2:1044 |
| `header-absent-call` | the lines `iota_<c>` with c from NC to 7 are 0 | 11.2:1045 |
| `forest-depth-G` | dT >= la | 11.2:1046 |
| `shape-product-layer` | lNI + lPd + lt >= 9; ll + lPf + lt >= 9; with routed experts ll - 1 + lfe + lt >= 9 | 11.2:1047 |
| `shape-theta0` | theta0 is not 0 | 11.2:1048 |
| `KL-length` | the scale file has 13 L words, and 3 L / 2 more with routed experts | 11.2:1054 |
| `KL-shift-range` | 1 <= k <= 16 (h = 0), 24 (h = 1), 32 (h = 2) per shift and its digit form | 11.2:1055 |
| `KL-kq-kk` | kq = kk, or both at least 16 | 11.2:1056 |
| `KL-norm` | 24 <= M <= 47, 17 <= K <= 32, K + 14 >= M for (M1, K1), (M2, K2) | 11.2:1057 |
| `KL-rp` | rp is 0 or 1 | 11.2:1058 |
| `no-wrap-U-<nm>`, `no-wrap-W-<nm>` | SP 2^max(k,16) <= 2^60; (A + 2^(k-1) + Qb 2^k) 2^lift(k) + add_h < 2^60, add_0 = 0, add_1 = 2^16 (Ty + 128), add_2 = 2^16 (Ty2 + 32896) | 11.2:1083-1098 |
| `no-wrap-guard-radix-clamp`, `-clamp-keys`, `-U-xr`, `-W-xr`, `-guard-radix-FS`, `-guard-radix-gate-clamp`, `-guard-flag-gate-clamp`, `-MR`, `-one-hot`, `-linear`, `-guard-radix`, `-ledger`, `-ledger-eps` | the thirteen inequalities of the table | 11.2:1103-1117 |
| `policy-weight-kind`; `header-absent-kind` | each of the twelve lines `wb_qk`..`wb_r` of a kind the model has is 13; a kind it lacks is 0 | 11.2:1119-1122 |
| `coin-zero` | eps of step 9 is not 0 | 11.2:969-970 |
| `internal-g-free-slot` | every scalar but fv' has a non-zero coefficient (ends `NOT CHECKED`) | 11.2:970-974 |

Constants of those conditions [11.2:1074-1081]: Ty = 2^18 (source `TyReq`), Ty2 = 257 Ty, Ty3 = 65793 Ty, BW = 2^12 (`WEIGHT_BOUND`), BC = 2^11 (`CLAMPED_CELL_BOUND`), acc = d BC BW, lsg = 39 with five limbs (30 with four). Standard-parameter-form conditions on this segment: `routed-experts`, `five-limbs`, `both-clamps`, `no-range-words`, `norm-shifts` [11.2:1021-1026].

Attention (prefix `A<g>:`), in the order the programs make them [11.3:949-979]:

| name | a verifier rejects unless | line |
|---|---|---|
| `policy-call-list-A` | 1 to 12 lines `callA`; kinds `KR`, `KFD`, `R16`, `WH`; distinct names; segments among the seven; expanded list <= 12 calls for every group | 11.3:951 |
| `af-shape-heads` | G is a power of two; H >= 1 and G divides H | 11.3:952, 956 |
| `shape-request-matrix-A` | lt <= lmh <= 24; lt <= lmo <= 24; lmbA <= 24; lmS <= 24; 1 <= NAs <= 64 | 11.3:953 |
| `af-policy-wd` | Sx < 32 | 11.3:954 |
| `af-shape-tiles` | 2 <= lt <= 16 and 0 <= lB <= lt - 2 | 11.3:955 |
| `af-shape-sh` | the group has exactly Lam shifts | 11.3:957 |
| `af-shape-la` | 0 <= la - lt <= ldh and la <= 16; 2^la <= 2^lmo; 2^la <= m_qa; S2 divides wcO and wcQ | 11.3:958, 969 |
| `af-policy-softmax` | 1 <= Sx <= 14; 1 <= rx <= 12; lt + Sx + 1 <= 24; Tt reaches 0 at some u0 <= 2^20 + 1 | 11.3:959 |
| `af-shape-lmS` | 1 <= lmS <= nD | 11.3:960 |
| `af-policy-kF` | 8 <= kFD <= 16; u0 + nHD <= 2^kFD <= u0 + 2 nHD for each shift | 11.3:961, 963 |
| `af-policy-sh` | 4 <= sh <= 12 for each shift of the group | 11.3:962 |
| `af-policy-C` | C_sh + 65536 <= 2^24 for each shift | 11.3:964 |
| `af-no-wrap-N1` | Ty4 + Smax < 2^60 | 11.3:988 |
| `af-no-wrap-N2` | 2^40 Ty + 2^20 (Ty + 128) + Ty + 128 + 2^41 < 2^61 - 1, and Ty + 128 + 256 < 2^20 | 11.3:989 |
| `af-no-wrap-N3` | 6 Smax + 2 C_sh + 3 x 65536 + 2^32 + 2^33 (Ty2 + 128 + 2^Sx) < 2^61 - 1 | 11.3:990 |
| `af-no-wrap-N4` | 6 Smax + 2 C_sh + 3 x 65536 < 2^32 | 11.3:991 |
| `af-no-wrap-N5` | TS + Ty4 < 2^60, TS = T 2^Sx | 11.3:992 |
| `af-no-wrap-N6` | 2 x 2047 TS + TS + 2 TS Ty2 + 2 TS + 1 + 65536 (Ty + 128) + 65536 < 2^60 | 11.3:993 |
| `af-no-wrap-N9` | 2^(16 - lt) x 2 T < 2^60 | 11.3:994 |
| `af-policy-call-list` | every line has a segment; each of the seven in exactly one line of its kind; expanded list <= 12 | 11.3:967, 970 |
| `af-policy-nmin` | nmin >= 10 | 11.3:968 |
| `af-shape-call-<name>` | 10 <= n_c <= 44 | 11.3:971 |
| `forest-depth-A` | dT >= lmS and dT >= lt + ldh | 11.3:972 |
| `forest-planes` | 5 <= lmbA <= kT + 5 | 11.3:973 |
| `forest-only-padding-<name>` | not all keys of a call are padding | 11.3:974 |
| `hid-a-fold-list`; `hid-a-slots` | NAs + 4 <= 256; fewer than 2^30 scalars | 11.3:975-976 |
| `policy-iotaA` | `iotaA_0` = 32 + dT for every group | 11.3:977 |
| `internal-qa-layout`, `plan-tensor-layout` | the qa numbers are those of the feed-forward layout, and S2 divides dh | 11.3:978 |
| `table-digest-exp` | if `texp0`..`texp7` are present, the digest of Tt is theirs | 11.3:979 |
| `internal-a-free-slot` | every scalar has a non-zero coefficient in the sum of all claims | 11.3:829-833 |

(Ty4 = 16,843,009 Ty [11.3:943-945].) The five tests on a shift are made shift by shift in increasing order; N1, N2, N5, N6, N9 in this order after them [11.3:965-966].

Head (prefix `H:`):

| name | a verifier rejects unless | line |
|---|---|---|
| `header-y` | the `REPLY` element is (y, 0, 0) with y < V | 11.4:300; FORMAT:1300-1302 |
| `policy-norm-F` | 24 <= `MF` <= 47; `MF` <= `KF` + 14; 17 <= `KF` <= 32; 1 <= epsF < 2^59 | 11.4:731 |
| `policy-toksrc` | `toksrc` is 1 | 11.4:732 |
| `policy-gap-words` | `theta` <= `C`; `cap` <= T; `cap` < 2^16; `F` = 24; `s` <= 63; `sh` is 7 or 8; `sT` + 4 = `sh` or `sh` + 4 <= `sT` <= `sh` + 10; S2 divides JVa; 2 V <= 2^`F` | 11.4:733 |
| `shape-request-matrix-H` | la <= lmhf <= 24; 1 <= NHf <= 64; lt <= lmhd <= 24; lt <= lmhr <= 24; lmbH <= 24 | 11.4:734 |
| `policy-call-list-H` | the tests on the call list (at most 6 calls) | 11.4:735, 138 |
| `shape-call-H-<name>` | n_c >= 10; n_c >= nminH (nmin without it); n_c <= 44; n_c >= la; lJ_c >= ls; `iotaH_<c>` = n_c - dT | 11.4:736 |
| `forest-depth-H` | dT >= la | 11.4:737 |
| `forest-planes` | 5 <= lmbH <= kT + 5 | 11.4:738 |
| `header-absent-call-H` | `iotaH_<c>` for c from NC to 5 are 0 | 11.4:739 |
| `shape-product-layer-H` | lPd + lt >= 9 | 11.4:740 |
| `hid-vocab-cols` | clog2(V) <= lkW | 11.4:741 |
| `hid-h-slots` | fewer than 2^30 scalars | 11.4:742 |
| `no-wrap-H-U-NF` | 2^(16 + `KF`) <= 2^60 | 11.4:792 |
| `no-wrap-H-W-NF` | 2^`MF` + 2^38 + 2^(`KF`-1) + 2^(15 + `KF`) + 2^16 (Ty2 + 32896) < 2^60 | 11.4:793 |
| `no-wrap-H-W-HD0` | 2^8 + 2^(`sh`+16) + 2^(`sh`+31) <= 2^40; and SH + 2^40 + 2^8 BIG + 2^`sh` (Ty2 + 32896) + Ty + 128 < 2^60 | 11.4:794-795 |
| `no-wrap-H-three-digits` | SH <= BIG and SH + BIG + 2^32 <= (2^16 + 1) 2^(`sh`+15); and BIG >= SH + 2^(`sh`+15) | 11.4:796-797 |
| `no-wrap-H-HE` | 2^16 (Be + 2^`F` + 1) + 2^16 < 2^60 | 11.4:798 |
| `no-wrap-H-Z` | JV 2^`F` + 2^24 + (JV - V + 1) 2^`F` < 2^60 | 11.4:799 |
| `no-wrap-H-E2`, `-E3`, `-E4` | T (2^40 + 2^8 `C` + 2^40) + `theta` T < 2^60; T (2^8 + 2^16) + `cap` < 2^60; 2^40 + 2^40 + `C` < 2^60 | 11.4:800-802 |
| `no-wrap-H-J-E` | TyX + 16,843,009 x 2^21 < 2^60 (about the embedding, 11.2) | 11.4:803 |
| `no-wrap-H-guard-radix` | (Ty2 + 32768) + 2^28 (Ty2 + 4096) < 2^59, and Ty2 + 32768 + 65536 < 2^28 | 11.4:804 |
| `internal-h-free-slot` | coefficient 0 for fv', non-zero for every other scalar | 11.4:695-704 |
| `policy` (whole call) | `sT` + 4 = `sh` | 11.4:152-157, 773-777 |

Head constants [11.4:783-788]: Ty = 2^18; Ty2 = 257 Ty; TyX = Ty (256^XL - 1)/255 (4,311,810,305 Ty with five limbs); BW = 2^12; BC = 2^11; SH = 2 d BC BW + 1; Be = 65793 Ty + offE. The inequalities are "computed without overflow (the programs use 128 bits)" [11.4:781-782].

## 9. Verifier-side closed-form computations (the hot loops besides hashing)

Unit of cost: one multiplication in E (cubic extension) unless said otherwise. "full" / "small" are the two example configurations (my arithmetic from the cited formulas).

| # | computation | where | cost in parameters | full | small |
|---|---|---|---|---|---|
| 1 | value of a non-range table at a point: T_c = sum_{t < 2^k_c} eq(zu, t) tab_c(t) (range tables have the closed form sum_i 2^(k_c-1-i) zu_i) [11.1:851-852] | every lookup; tables FC, FL, FS (G), `KR`, `KFD`, `WH` (A, per distinct shift), FE, FC (H; the two FE calls share one table) | 2^k_c per distinct non-range table | 3 x 65,536 per segment | same |
| 2 | generating the tables' rows | FC, `KR`, `WH`: integers. FE: integer recurrence with products below 2^73 [11.4:146-148]. FL, FS, rotary, Tt, `KFD`: float64 [11.1:336-340] | 2^16 rows each; rotary 2 T dh/2 entries; Tt u0 entries | rotary 131,072 words; Tt 2,307 (libm estimate of u0) | rotary 8,192 words |
| 3 | column weights of a call: ew_SEG[x] = eq(zj_c, pos_SEG(x)), plus ewh, sw/wsum/wx, PADW/padW [11.2:592-597; 11.4:460-466] | G and H | 2^lJ_c per call (all zj_c are suffixes of the same coordinates of zx, so one table of the largest size can serve `(reading)`) | G: sum 2^lJ_c = 262,144. H: 1,179,648 (largest 262,144) | G: 36,864. H: 98,304 |
| 4 | **multilinear extension of the rotary tables**: Ct[pa] = sum_t eq(rt, t) Co(l, t, pa), St likewise; then rot (dh entries), AH (64), lf (dh) [11.2:854-863] | G, once per segment (the tables do not depend on the layer; rp only switches them off) `(reading)` | eq table of T + 2 T dh/2 multiplications of an E element by an integer of at most 13 bits | 131,072 | 8,192 |
| 5 | **multilinear extension of the request's tokens**: tokw[vv] = sum of eq(ztE, t) over t with tok_t = vv [11.2:865] | G_0 only | T (a sparse vector over V with at most T non-zeros) | 1,024 | 64 |
| 6 | **token-dependent weights of the head**: ON, phiC, ERC, rhoC, RC [11.4:468-471]; place_HD0 = prefix sums of ew_HD0 over v, then one lookup per checked position [11.4:472]; psiH, sR [11.4:712-714] | H | T + V | 203,072 | 576 |
| 7 | dense weight-claim factor AV[v] = wx_HD0 psiH[v] - sR ew_HD0[v] for v < V [11.4:712] | H, handed to the pending row (11.5) | V | 202,048 | 512 |
| 8 | eqlow tables of step 11: EY (2^wy), EI (2^(w - wy)), sb per panel [11.2:801-806]; EY depends on wy only | G | sum over distinct wy of 2^wy; panels: 5 Lam + 7 LamM-type rows | largest 2^14 | largest 2^10 |
| 9 | As, Bs, Alin, Blin over all panels [11.2:811-819] | G | about Lam (4 d + dq) + LamM (d + 2 NE) + LamM (2 d) coefficient updates, each on 2 limbs | about 1.3 x 10^5 | about 1.3 x 10^4 |
| 10 | LINE_SEG coefficients on `U3` for all 31 calls' segments and Lam layers [11.2:661-693] | G | about (sum over long tensors of nl Lam J / 2^ls) + (sum over short tensors of nl cnt J) | about 1.2 x 10^5 | about 3 x 10^4 |
| 11 | eq tables for end-value claims: 2^(lNI + lPd - ls) (group 2), 2^(ll + lPf - ls) (group 8), 2^(ll - 1 + lfe - ls) (group 9) [11.2:884-886, 933-942] | G | as stated, times XL or 2 limbs | 1,024; 1,024; 256 | 1,024; 1,024; 256 |
| 12 | digit-row forms D_j at four points, fields, groups 4-7 [11.2:546-571, 897-928] | G (NI norms), H (1 norm, six parts) | NI NR per point | 792 per point | 792 per point |
| 13 | tile vectors WI, WJ (nT entries each) from eq(yP, P) eq(ys, sg) over the hP (nT - 1) addresses [11.3:341-345] | A: for (zP_u, zs_u), (rP_u, rs_u) of each `FM` unit and (rPM, rsM) | hP nT per point | 128 | 8 |
| 14 | LE(zj_u, zi_u) (lB steps), ones(zs_u), id(ziX), eqp products of the W_b [11.3:292-295, 633-641] | A | O(number of variables) each | trivial | trivial |
| 15 | piece weights wp = eq(zk_c[0 .. n_c - nb), off / 2^nb) [11.3:467-470] | A | 7 NP pieces, each a product of n_c - nb factors | 140 pieces | 56 pieces |
| 16 | readings PL (2^(nM - lmS) or 2^(nD - lmS) terms), LV, XL (2^(ldh - ls) terms), OG (G terms) [11.3:608-617] | A, groups 2-8 | bounded by the `U3` length nW | 60,640 | 34,152 |
| 17 | S0 of every sumcheck: sum_b W_b AE'_b BE'_b (NP or np terms); SD: NP lt factors [11.3:628, 659]; G steps 8, 11; H steps 4, 6, 7, 8 | all | O(end values) | at most 204 values (SD) | at most 52 |
| 18 | SL / HN / A2 forms and key forms KS_1..9 [11.4:519-571]; (Z) reads 3 JV / S2 entries of part 2; item 26 needs eq(rsP, k) for k < d | H | about 8 JV / S2 + 6 d / S2 + 2 d + 2^lPd | about 4.5 x 10^4 | about 2 x 10^3 |
| 19 | replay of every sumcheck: the unsent coefficient, cur = g(gamma) per round, Left(..) coefficients on mask entries [11.1:580-640] | all | O(scalars): one Horner evaluation per round, degree at most lt + 2 | 4,058 / 4,190 / 3,570 scalars per segment | 3,203 / 3,076 / 2,879 |
| 20 | accumulation of all claims under powers of chi into column weights on every array, LS(j), c0; then the free-scalar test over all ns scalars [11.1:502-532] | all | O(`U3` length + ns + sum of claim sizes) E elements held per segment | `U3`: 407,226 / 60,640 / 61,680 | 166,688 / 34,152 / 11,264 |
| 21 | one inversion in E: 1 / eps_9 [11.2:721]; one inversion in F: iw = 1 / 2^(`sh`+15) [11.4:474]; the constants 1/2 and 2^(-lPd) [11.2:710] | G; H; G and H | constant | | |
| 22 | weight vectors phi of the `U3` parts, needed by the smallness test's READ claims (11.1): long = eq(ls coords) x eq(lt coords), short = eq over T, tok(.) and lng(.) products in A [11.2:504-506; 11.3:572-575; 11.4:489-493] | all | 2^ls + T per part when kept in product form | 21 / 20 / 15 parts | same counts |
| 23 | public-file arithmetic: pos_SEG and npad(y) per tree; no-overflow inequalities in integers up to about 2^72 (hence "128 bits" upstream) [11.2:1086-1098; 11.4:781-782] | once per parameter file | - | | |

Per proof the dominant closed-form loops inside this scope are therefore, at full size: 25 x 3 table evaluations of 2^16 (item 1), 12 x 2^18 + 1.2 x 10^6 column-weight products (item 3), 12 x 131,072 rotary products (item 4), about 5.7 x 10^6 `U3` weights to accumulate (item 20), and one 202,048-entry vector for the head's weight claim (item 7). Everything quadratic in T stays on the prover's side (4.3). The `RNG` matrix (55.4 million ternary entries at full size, section 7) and the smallness test's weights are 11.1's, and are probably heavier than all of the above `(reading)`.

Bend-relevant facts from this scope: integer constants above 32 bits appear in claims (2^39, 2^40, 2^47, 2^48, BIG = 2^37, 2^(`MF`+1) up to 2^48) but only as images in F; table rows are "numbers below p" up to about 2^45 (`KFD`: 2^33 Tt[t]); the no-overflow tests need exact integers beyond 64 bits; eps1, eps2, epsF and theta0 are 64-bit two-line values; the four float64 tables cannot be produced with U32 integer arithmetic alone without a soft-float implementation (see open question 1).

## 10. Open questions and ambiguities

1. **Float64 public tables.** The gate function, the sigmoid, the rotary tables and attention's Tt are defined by IEEE float64 with correctly rounded exp, cos, sin, pow [model:125-128; 11.1:336-340]; "The format does not define these values by integer arithmetic. A second verifier computes the four tables to the bit as the programs do, or takes them as data (what then fixes them: R15.3)" [11.1:338-340]. Decision needed: ship the tables as data and check the four digests (needs the second hash function K(72; table) of 12.6, another researcher's scope), or implement soft-float. u0 (the length of Tt, which fixes C_sh, the `KFD` rows and the padding key) also depends on that table; my u0 = 2,307 for `S 12`, `rx 8` is a libm estimate, not bit-checked.
2. **No R-rules in scope.** 11.2-11.4 define none (section 8.1). The spec must mint IDs for steps, claim groups and conditions; section 8.2 lists the natural units.
3. **Which parameter space to implement.** Upstream writes out forms on which "no call ends with an acceptance": four limbs, `NE 0`, a missing `rcl 1` or `gcl 1`, a line `eg` or `smax`, K above M [11.2:1021-1026], more than one shift per group (`one-shift`) [11.3:56], tables of exponentials other than the step table [11.4:152-157]. Restricting the Bend verifier to the standard parameter form (five limbs, routed experts, both clamps, nsh = 1, step table) would remove a large part of 11.2-11.4, but the exact list of conditions is FORMAT 13.7, which I did not read. Inference, not a finding: both example configurations lie inside that restricted space.
4. **Which `internal-`/self-check tests are required.** Upstream says a second verifier needs none of the listed self-checks [11.2:980-992; 11.3:815-818, 843-847; 11.4:747-752] but DOES need the tests that depend on sampled values: `coin-zero`, the free-scalar test of each segment, and the smallness test's events [11.1:546-550; FORMAT:2458-2463]. What a "verifier with two answers" must output at the `NOT CHECKED` events is said only as "rejects" [FORMAT:2460].
5. **Bound on o.** No lookup has o as its key in either segment; the feed-forward condition `no-wrap-W-o` takes BC as the bound of o on the strength of the attention sub-proof; "Neither comment shows the bound, this page does not show it, and this page knows no test that shows it" [11.3:1003-1010; 11.2:1068-1070]. Likewise "For BC on `xr` ... the source names no origin" [11.2:1070]. These are statement caveats, not implementation choices.
6. **No-overflow conditions are stated, not proved sufficient** [11.2:1060-1065; 11.3:448-451, 996-1000; 11.4:838-839]. The verifier must still evaluate them exactly as written.
7. **Machinery interfaces I did not specify** (11.1 / 11.5, other notes): the exact form Left(C; S0; K); the lookup's LK/LP/LJ claims; the smallness test's TIE/READ claims, their numbering versus their power of chi, and its row weights; the pending row on the stored table and the index groups, units and classes of 11.5 that the factors FR, FE, AV, pt, HV of 3.11 and 5.9 plug into. The interface points are column "inputs/outputs" of section 6.
8. **`layout.txt` to oracle messages.** The mapping of arrays to oracle messages comes from the layout file (R14.5; FORMAT 13.4 step 7), which I only counted (5 / 3 / 3 messages per G / A / H). That `B` life 1 is qa and `B` life 2 is xbO is my inference from the life values.
9. **Small example versus `target_small_f2`.** `examples/accepted-proof/config/policy.txt` has `MF 43` where `prover/examples/target_small_f2/policy.txt` has `MF 44`, and the two `KL.bin` differ. Shapes are equal, so the counts in 08's tables for `target_small_f2` carry over, but any value-level fixture must use the example's own files.
10. **Scale-file facts are read from binary, not from a doc.** That sh is 8 (full) and 12 (small) in all layers, and that only two distinct layer records exist in each `KL.bin`, comes from my script reading the files; upstream text only gives the format [11.2:1005].
11. **Step 9's shape.** d_Y = 1 with S0 = 0 and the form KT = -(1/eps_9) Left(C_9; 0; 0) inside C_11 [11.2:78, 302, 721-726] is unusual. My reading: each term is a product of one SHOWN factor (R, `sc`, `sel`) and one kept factor, so the summand is affine in the shown values; the kept factors are then proved by the second-pass panels of step 11. Confirm against `vf_layers_check.inc` when implementing.
12. **Suffix sharing of the column weights** (section 9 item 3) and "Ct, St once per segment" (item 4) are optimizations I inferred from the definitions of zj_c and of the rotary tables; upstream does not state them.
13. **Head margins at T - 1.** That non-negativity of the three digits alone forces y to be the first arg-max is my reading of [11.4:298-299, 903-904]; upstream reports it only as the source comments' argument.
14. **`kFM`** is hashed but read by no test and no formula [11.3:54]; `wb_emb 21` likewise is only compared [model:100-101]. Both must still be parsed because every byte of the parameter file enters the configuration's digest [08:862-864].
15. **Counts for the small example** (section 7) are derived, not upstream figures. A cheap confirmation would be the plan printed by upstream's planning call, which I was told not to build or run.
