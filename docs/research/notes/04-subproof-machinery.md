# 04 — The shared machinery of sub-proofs (FORMAT §11 head, §11.1, §11.5, protocol "tools", toy runs)

> Status: frozen
> Recovered working notes, 2026-11-23. Upstream excerpts from FlashProve, Copyright 2026 Anthropic PBC, Apache-2.0.

Source: FlashProve 0.16.0-rc.26, commit 9e2bdd8 (read-only copy). Scope read in full: `11-sub-proofs.md`,
`11-1-machinery.md`, `11-5-weights-in-the-table.md`, `protocol.md`, `toys/1-product.md`, `toys/2-links.md`,
`toys/3-key-and-entry.md` parts 7–9 (+ head). Consulted for terms only: `FORMAT.md` §5 and §13.9,
`09-key-and-leaf-files.md` 9.1–9.4, `10-proof-file.md`.

**Citation legend** (all under `docs/`; `X:n` means line n of the file):

| tag | file |
|---|---|
| `11` | `docs/format/11-sub-proofs.md` |
| `M` | `docs/format/11-1-machinery.md` |
| `W5` | `docs/format/11-5-weights-in-the-table.md` |
| `P` | `docs/protocol.md` |
| `T1` / `T2` / `T3` | `docs/format/toys/1-product.md` / `2-links.md` / `3-key-and-entry.md` |
| `F` | `docs/format/FORMAT.md` |
| `S9` / `S10` | `docs/format/09-key-and-leaf-files.md` / `10-proof-file.md` |
| `RD` | `docs/format/README.md` |

Marks: **[INF]** = my inference, not stated by the docs. **[OOS]** = defined in another researcher's scope (11.2–11.4, §8, §4–7).

## 0. Orientation: what is authoritative, and two traps

- On bytes, hashed strings, order and tests, `FORMAT.md` with the files of its sections 8–11 takes precedence over every other page (RD:7-9). §11, §11.1 and §11.5 are "written from the programs' source" (11:8; M:6; W5:6). §11 gives rounds and content, not the soundness arguments, not an honest prover's choices, not how tensors become integers (11:26-29).
- Name map protocol page -> format (RD:59-74): range check = **smallness test** (`smallness`, line `work smallness`); request vector w = **W**; shared vector = **Omega**; test on the table = `the test on the table`; batch tree = `binding tree`; seal = `the seal of an earlier chain`; segment = "link" in hashed names (`group link`, `stages link`, `links' identifiers`; S10:78-79).
- **Trap 1 — the sub-proofs are not the library blocks.** `cp_verify` runs the lookup, the merge and the smallness test by texts of its own (`verifier/src/vf_lookup_argument.h` M:151,923,931; `verifier/src/vf_weights_merge.h` M:212-213, T3:1444-1450; `verifier/src/vf_smallness_packing.h` M:1469; it "compiles nothing" of `blocks/iop/rng.h` M:1459-1461). Toy parts 7 (LKP) and 8 §5 (`batt_shown`) describe library *twins* with other conventions (lowest bit = variable 0: T3:748-749, T3:1221-1223). For a segment's sub-proof, 11.1 is the spec; the toy pages are the spec-level description of the **frame** (SEND, BAT, FOLD, CS, BASE, the test on the table).
- **Trap 2 — two bit orders.** Inside a sub-proof a point is written highest bit first: `eq(z,i) = prod_{s<n} (z_s if bit n-1-s of i else 1-z_s)` (M:346-349, 395-397). In the frame, variable s belongs to bit s (lowest first) and entry (row b, column c) of a table of 2^k rows has index `b + 2^k c` (M:349-351; T1:242-244, 251-253). Three conversions (M:351-354): (1) the points of lookup steps 4 and 8 are sampled lowest bit first, then reversed; (2) the weights of a claim on the rows of an array are passed to the frame with the point reversed; (3) the merge's point is sampled highest column bit first and the frame's row on the stored table takes it reversed.

## 1. Anatomy of a sub-proof

### 1.1 Where it sits in the request chain

- A proof's first chain (label 0x46524d01, S10:70) walks the model segment by segment (R14.4; 11:5). Segment order: G_0, A_0, G_1, A_1, .., H (G_g feed-forward segment of the layers of group g, A_g attention segment, H output head) (11:17-19). Outside the segments a model's sub-proofs send nothing (R14.4 (e); 11:19-20; S10:239-240).
- A sub-proof runs **between the frame's rounds of its segment** (R14.4 (c)); it has no first query and no starting value of its own (M:18-20). The frame's own rounds of a segment: at its beginning `SEND seed` with `SEND answer` (segment 1) or with `LOC` (later segments); at its end `BAT`, `FOLD epsilon`, k x `FOLD round` (R14.4; S10:191-196).
- A **moment** is a point at which the prover commits to arrays (R12.12). Moment 0 is the segment's first prover's message; each later moment is a pair of frame rounds `SEND seed`, `SEND answer` (R14.4 (d)) (M:20-23; S10:218-221). In a model's proof every segment has three moments (S10:187): moment 0 = the arrays `M`mu, moment 1 = `U3`, moment 2 = `ZZ` then `BZ` (M:256-261).
- First-query parameter items of the first chain, in order (R14.3; S10:72-84): `configuration`, `codes`, `the test on the table`, `request's shape`, `layout`, `links' identifiers`, `pending rows`, `binding tree`. Statement items (S10:92-115): `table`, `stored copy`, `request`, `the request file's words`.
- Frame timeline of one segment m of a model's proof (kinds: R14.11, S10:465-473):

| # | round (kind) | prover's message | sampled | cite |
|---|---|---|---|---|
| 0 | `REPLY` (7), last segment only, directly before its `SEND seed` | the next token, 1 element of E, unmasked | nothing | S10:254-259, 351 |
| 1 | `SEND seed` (3) | roots of the trees holding, in order of sending: [m>1: carrying message of segment m-1; kept messages sent again]; the segment's messages of moment 0 (the segment's one mask row is in the first of them); the fresh mask of the segment's fold; [m=1: the index-mask message] | s seeds | S10:352, 354 |
| 2 | m=1: `SEND answer` (7); m>1: `LOC` (4) | s answers per message that gets an out-of-domain sample, in order of sending (fresh mask: none; index-mask message's come last) | m=1 nothing; m>1 the positions (no element); then nonce and the openings of **all trees of the group of segment m-1** | S10:353, 355 |
| 3 | sub-proof rounds after moment 0 | scalars only | per §11.2–11.4 [OOS] | S10:356 |
| 4 | `SEND seed` / `SEND answer` (moment 1: `U3`) | roots; answers | seeds; nothing | S10:357-358; M:259 |
| 5 | `RNG` (5) — "directly after the `SEND answer` of the moment of `U3`" | nothing | (sum of k_mu) x tau entries in {-1,0,1} (R6.7) | M:227, 231-234 |
| 6 | `SEND seed` / `SEND answer` (moment 2: `ZZ`, `BZ`) | roots; answers | seeds; nothing | M:228 |
| 7 | the lookup on the digits, then the rest of the sub-proof | scalars | per §2.6, §11.2–11.4 | M:229 |
| 8 | the sub-proof's last round `BAT-sigma` (1), n = NCm + Q | waiting scalars | chi | M:312-314 |
| 9 | `BAT` (1); `FOLD epsilon` (2); k x `FOLD round` (1) | nothing; hiding sum; (q_0, q_2) | theta; eps; g_j | S10:360-362 |

  The exact interleaving of rows 3–7 with the segment's own steps is per segment kind [OOS]; the fixed facts are the three bullet citations above.
- The request's **index-mask message** (R14.4 (a)): mask rows alone, under the mask code of a request's own group, s answers, leaf class = least number above every segment message's class; goes out in segment 1's first prover's message after that segment's messages and its fold's fresh mask; its answers are the last in `SEND answer`; it has a tree of its own (number 1 in the programs); it joins no segment's group and no round of the first chain opens its tree (S10:197-214, 226-229). It is tested in the second chain's group {index-mask message, W, Omega} (S10:316-320).
- Tree numbers in the programs (three moments, every class 0): segment 1 has trees 0, 2, 3 and the index-mask tree is 1; segment m>1 has trees 3m-2, 3m-1, 3m; the last group has tree 3L+1; the last test's later trees go on from 3L+2 (S10:226-231).

### 1.2 What a sub-proof sends and what the verifier keeps

- Apart from roots and out-of-domain answers in the frame's rounds, **everything a sub-proof sends is scalars**: one element of E, 24 bytes (R1.4) (M:25-27). The scalars of a segment are numbered from 0 in the order sent = "a scalar's number" (= "slot" in rejection names with `free-slot`) (M:27-29).
- The segment's first prover's message commits to a **mask row** with one entry per number. *Hidden value sent alone* = value + mask(j). *End value of a sumcheck* = value + beta x mask(j), beta = that sumcheck's `PSC Y` element (M:29-32).
- The number of scalars of a segment (ns) is public; a verifier rejects a proof that ends before the last scalar (M:33-34). Room: ns + (line `answers`) must not exceed the number of entries of a message of the request's mask code, else the public files are rejected (`plan-mask-row`), because the out-of-domain pads are the last entries of that row (M:306-310).
- **Scalars do not close a round**: a round's prover message is everything sent since the previous round, in order; a hidden value sent alone directly before a sumcheck is in that sumcheck's `PSC epsilon` message, *before* the hiding sum, which is the last item (R8.4). A round whose step sends nothing has an empty message and still asks its query (R5.1) (M:36-40).
- **Nothing is tested during the rounds** except form: a coordinate of a scalar not below p, missing bytes, a failed proof-of-work test. Two exceptions: 11.2 step 9 and 11.4 the next token [OOS] (M:42-44; F:2430-2431 names them `coin-zero`, `header-y`).
- Every check on content becomes a **claim**: an affine form in hidden values and entries of committed arrays that must be 0. Claims have a fixed order, numbered from 0. The segment's last round, a `BAT-sigma`, samples chi; claim i gets coefficient chi^i — except the smallness test's claims on a matrix or on a read (each takes a number, but its equations get powers of their own). The sum of all claims is **one equation**, which the frame tests with the segment's group. "So the order of the claims is part of the protocol." After chi, the verifier also tests that certain weights are not 0 (M:44-52).

### 1.3 Hand-over to the frame

- The sub-proof ends in one equation with a public target: terms `scale x (weight on rows) x (weight on columns)` on named arrays (of this segment or of an earlier, still kept one), plus coefficients on the first ns entries of the segment's mask row, in order. It becomes **one row** of the segment's group (F:2608; T2:731-744; formula in §2.1).
- Arrays are placed in oracle messages by the item `layout` (R14.5): an array = name, number of its oracle message, rows, columns, list of blocks; a block = nine words (first row, first column, first table row, first table position, b rows, b columns, b rectangle rows, b rectangle positions, flag "row index in the low bits"). With a, e, f = words 5, 6, 8: element (word1 + i, word2 + c) has number `x = c 2^a + i` if word 9 is 1, else `x = i 2^e + c`; it is in the message's table in row `word3 + (x >> f)` at position `word4 + (x mod 2^f)`; words 7 + 8 = a + e (S10:131-150). In the group's main table a member's entry (row i, place j) has index `(first + i) + 2^k j` (T2:309-311). A vector stored as an array of NK columns has entry x in row floor(x/NK), column x mod NK (M:467-468).
- The coefficients on masks go to entries 0, 1, .. of the mask row of the segment's first message that has mask rows (exactly one such row) (T2:739-741).

## 2. The machinery, component by component (verifier's side)

### 2.1 Scalars, forms, combined rows, the one equation

**The pair kept per scalar number** — each of the ns numbers gets one pair (shown(j), factor(j)), once; the kind is public (M:447-455):

| scalar with number j | shown(j) | factor(j) | hidden(j) = shown - factor x mask |
|---|---|---|---|
| hidden value sent alone | the scalar | 1 | scalar - mask(j) |
| end value of a sumcheck | the scalar | that sumcheck's beta | scalar - beta mask(j) |
| hiding polynomial's sum, or a coefficient sent in a `PSC round` / `PSC Y` | 0 | -1 | mask(j) |

Third line: sums and coefficients are used as sent in the running claim; the mask entries of their numbers are the coefficients of the sumcheck's hiding polynomial, unrelated to the scalar sent under that number (M:457-461).

**Combined row** A{w}: array A (R rows, NK columns) under a public vector w of R row weights in E; `A{w}[col] = sum_{r<R} w(r) A[r][col]`; F cells read in E; w may depend on every sampled value of the segment, chi included (M:463-467). Three shapes of w (M:470-476): (1) *equality weights on a block of rows* — point z of n coordinates, first row r0 a multiple of 2^n, `w(r0+r) = eq(z,r)`, 0 elsewhere; (2) *ones*; (3) *product over the bits* — elements (lo_q, hi_q) per bit q, bit 0 first, `w(r) = prod_q (hi_q if bit q of r else lo_q)`; powers of x: lo_q = 1, hi_q = x^(2^q).

**Form** f = const(f) + sum_j f[j] hidden(j) + sum f[A{w},col] A{w}[col], public coefficients in E. **Public part** `pub(f) = const(f) + sum_j f[j] shown(j)` (arrays left out), so `pub(f) - f = sum_j f[j] factor(j) mask(j) - sum f[A{w},col] A{w}[col]` (M:478-486). pub(f) is computed only after every number f names has its pair; named arrays need not be committed yet (M:488-497).

**The one equation** (M:502-532). With claims cl_0..cl_(NCm-1) and chi:
1. `L(A{w})[col] = sum_i chi^i cl_i[A{w},col]`;
2. `LS(j) = sum_i chi^i cl_i[j]` for j < ns;
3. `c0 = sum_i chi^i const(cl_i)`.
The smallness test's TIE/READ claims add to the same three sums under their equations' powers; their own numbers i count in NCm but contribute no chi^i term (M:510-512). Passed to the frame as

`sum_{A{w}} sum_{r<R, col<NK} w(r) L(A{w})[col] A[r][col] + sum_{j<ns} MC(j) mask(j) = TG`, with `MC(j) = -LS(j) factor(j)`, `TG = -(c0 + sum_{j<ns} LS(j) shown(j))` (M:520-522).

Each combined row gives a term on its array (named by committing segment + name in that segment's `layout` list) with scale 1, row weights w, column weights L(A{w}). A w that is not a product over bits is passed as one term per row r with w(r) != 0: scale w(r), row weight 1 at r (M:524-530). n of the last `BAT-sigma` = NCm + Q (M:531-532).

**Self-checks a second verifier does not need** (`internal-` names; depend on public files only): a number gets two pairs; a number has no pair at the end; pub() asked too early; a claim number used twice or not at all; a claim added after hand-over (M:534-540). Tests under `internal-` that depend on sampled values **are** needed by every verifier (§2.9; M:546-550).

### 2.2 Steps of one round

| step | round | prover's message | sampled | cite |
|---|---|---|---|---|
| a point of n coordinates | `ZERO` | only waiting scalars (as a rule none) | n elements of E, each by R6.4 (0 allowed) | M:58 |
| a point joining 2^n claims of one shape | `JOIN` | as above | n elements of E | M:59 |
| the coordinate joining the two end values of a product level | `LINE` | nothing | 1 element of E | M:60 |
| batching of n rows | `BAT-sigma` | only waiting scalars | 1 element x; row i (from 0) gets x^i | M:61 |

The n of a `BAT-sigma` is the last of the eleven words of the round's plan entry (R4.3); the round is run and x sampled also where n = 1 (M:63-64). `BAT-sigma` carries no list factor and never batches a sample row (T1:497-500).

### 2.3 The sumcheck with a hiding sum (`PSC`) — every variant

**Statement.** A sum over the points of a cube equals a hidden value given as an affine form, the *start form* C. It runs on a hiding polynomial plus eps x the true summand (M:66-68). A use is defined by six things (M:554-560): (1) C; (2) per variable, in round order, the form of its round (equality at coordinate z_l, or plain) and degree k_l; (3) d_Y and n, both 0 or both >= 1; (4) which map each end value is a value of; (5) S0, a public function of sampled values and end values as sent; (6) the kept form K (usually 0). Way of summing: `phi_l(g) = (1-z_l) g(0) + z_l g(1)` (equality) or `g(0) + g(1)` (plain); **the equality weights are in the phi_l, not a factor of the summand H** (M:562-566). If n > 0 there is one further variable Y, the last, with phi(g) = g(0) = an equality round at z = 0 of degree d_Y, challenge beta; NV = (number of `PSC round`) + [n > 0]; there is no sumcheck with NV = 0 (M:568-571; guard: S9:300-302).

**Rounds** (M:75-80; R13.16 S9:289-300, where g = k+1 coefficients and D = d_Y, M:70-72):

| round | how often | prover's message | sampled |
|---|---|---|---|
| `PSC epsilon` (kind 2) | once | waiting scalars, then 1 scalar: the hiding polynomial's sum hs (last item, R8.4) | eps in E, can be 0 |
| `PSC round` (kind 1) | once per variable | k scalars: coefficients of g, **lowest degree first**, without the omitted one | 1 element of E (0 allowed) |
| `PSC Y` (kind 1) | once, iff n > 0 | d_Y scalars: coefficients of degree 1..d_Y | beta in E, **not 0** (R6.5) |
| `PSC values` (kind 7) | once, iff n > 0 | n scalars: the end values | nothing |

Scalars sent: `1 + sum k + d_Y + n` (M:82). No variable at all: `PSC Y` follows `PSC epsilon` directly. Summand affine in everything it reads: no `PSC Y`, no `PSC values`, ends with its last `PSC round` (M:82-85).

**The omitted coefficient** (M:96-100; R13.16 S9:307-316) — "no round can fail" (M:89):

| form | round's equation | not sent | verifier computes |
|---|---|---|---|
| equality at z | (1-z) g(0) + z g(1) = cur | constant g_0 | `g_0 = cur - z (g_1 + .. + g_k)` |
| plain | g(0) + g(1) = cur | linear g_1 | `g_1 = cur - 2 g_0 - (g_2 + .. + g_k)` |
| `PSC Y` | g(0) = cur | constant g_0 | `g_0 = cur` |

So a plain round's k scalars are g_0, g_2, .., g_k (M:989); an equality round's are g_1, .., g_k. Round polynomials are sent as **coefficients**, never as evaluations: no interpolation on the verifier's side [INF from M:78, 87-89].

**What the verifier computes** (M:580-591):
1. `pub(C)`; read hs; sample eps; `cur = hs + eps pub(C)` (shown value is 0 for numbers of a hiding sum or of a sent coefficient: M:92-94).
2. For each variable l in round order (Y last): read k_l scalars, complete g by the table, sample gamma_l (beta for Y, not 0), `cur = g(gamma_l)`.
3. If n > 0: read n end values; `shown(jE+i) = end value i`, `factor(jE+i) = beta`.
4. For every j from j0 to j0 + sk(NV): `shown(j) = 0`, `factor(j) = -1`.

**Scalar numbers** (M:573-578): j0 = number of hs; `sk(l) = k_0 + .. + k_(l-1)`; the i-th scalar of variable l's round has number `j0 + 1 + sk(l) + i`; `jE = j0 + 1 + sk(NV)`; a hidden value sent alone before the sumcheck has number j0 - 1.

**Hiding polynomial** (M:593-606): `U = sum_{l<NV} u_l(X_l) prod_{i>l} psi_i(X_i)`, psi_i(X) = 1 for an equality round and for Y, X for a plain round; `u_l(X) = sum_deg u(l,deg) X^deg`, deg = 1..k_l for l < NV-1 and 0..k_l for l = NV-1 (only the last variable has a constant): 1 + sk(NV) coefficients, all mask entries: `u(l,deg) = mask(j0 + pos(l,deg))`, `pos(l,deg) = sk(l) + deg - 1` for l < NV-1, `pos(NV-1,deg) = sk(NV-1) + deg`. If NV > 1, mask(j0) is u(0,1), not a mask of hs.

**The claim a sumcheck leaves — its only test** (M:615-640). With psi_l := psi_l(gamma_l) (1 for equality/Y, gamma_l for plain), `tail_l = prod_{i=l+1}^{NV-1} psi_i`, `PP = prod_{l<NV} psi_l`:

`Left(C; S0; K) = sum_{l<NV, deg} gamma_l^deg tail_l mask(j0 + pos(l,deg)) + eps PP (pub(C) - C) + eps K + eps S0 - cur = 0`.

As a form (M:630-636):

| part | coefficient |
|---|---|
| constant | `eps S0 - cur + eps const(K) + eps PP sum_j C[j] shown(j)` |
| hidden(j0 + pos(l,deg)) (a mask entry) | `gamma_l^deg tail_l` |
| hidden(j), each j that C names | `- eps PP C[j]` |
| A{w}[col], each entry C names | `- eps PP C[A{w},col]` |
| what K names | eps x K's coefficient |

S0 + K is the summand at the sampled point with the end values put in as sent; `K = sum_i ka_i (kept map i at the point, as a form)` (13.9 writes A_0 for S0, A_i for ka_i) (M:624-627; F:2557). All-equality sumcheck: every tail_l = PP = 1; plain rounds: products of the later challenges (M:638-640). S0 has **no** factor eq(z, gamma) (M:1005-1007). As a rule Left(..) is added as one claim; a segment can instead put the form into a later start form (11.2 step 9), then it takes no claim number (M:622-624).

**Per end value a second claim** (M:642-645): either hidden(jE+i) enters a later start form, or a claim `hidden(jE+i) - (the map's value at the point, as a form) = 0`. The merge's end value is the one exception (§2.7).

**Uses shared by the sub-proofs** (M:650-658):

| use | C | rounds | d_Y, n | end values | S0 | K |
|---|---|---|---|---|---|---|
| product level, m variables, point z | given | m equality rounds, degree 2; round l at z_(m-1-bit(l)) | 2, 2 | vL, vR | shown(jE) shown(jE+1) | 0 |
| token sumcheck at z (lt coordinates) | hidden(j0-1), the claimed sum | lt equality rounds of degree 2, round l at z_l; then rounds a segment appends (11.4 step 8: lPd equality rounds at 1/2; further round i binds bit lPd-1-i) | segment's | segment's | segment's | segment's |
| lam plain rounds of degree 2 (11.2 step 11) | segment's | round l binds bit lam-1-l | segment's | segment's | segment's | segment's |
| attention: nb products, nv variables | segment's | nv plain rounds of degree 3 | 2, 2 nb | factors of product 0, then 1, .. | `sum_{i<nb} W_i shown(jE+2i) shown(jE+2i+1)` | 0 |
| attention: a degree per round | segment's | plain rounds of degrees k_0, k_1, .., each from 1 to 64 | segment's | segment's | segment's | segment's |
| lookup steps; merge | §2.6; §2.7 | | | | | |

Other facts: a plain sum over a variable is sometimes written as an equality round at the constant z = 1/2 with the start form divided by 2 per such round; each such sumcheck (one in a feed-forward segment, two in the head) has lPd such rounds and the factor 2^(-lPd), lPd least with 2^lPd >= d (M:102-106). In feed-forward segments and the head every round has degree 2 except five rounds of degree 1 in each lookup (M:106-108). *Token sumcheck*: 1 hidden value sent alone (claimed sum), then the sumcheck; claimed sum and hs are one prover's message in this order; `1 + (1 + 2 lt + d_Y + n)` scalars, 2 more per appended round (M:120-124). *eqlow*: for lam rounds where round l binds bit lam-1-l, rs_q = challenge of the round binding bit q; `eqlow(lo,hi,i) = prod_{s<hi-lo} (rs_(lo+s) if bit s of i else 1 - rs_(lo+s)) = eq((rs_(hi-1),..,rs_lo), i)` (M:683-688).

### 2.4 A product level

Product tree over 2^D leaves: `N_m(i) = N_(m+1)(i) N_(m+1)(i + 2^m)`, m = D-1..0, i < 2^m; root N_0(0) (M:660-663). The level with m variables has a point z (m coordinates) and a start form C standing for `sum_{i<2^m} eq(z,i) N_m(i)`; summand `N_(m+1)(0|X) N_(m+1)(1|X)`; end values vL (new bit 0), vR (new bit 1) (M:663-666). Rounds: `PSC epsilon`, m x `PSC round` (degree 2, equality), `PSC Y` (d_Y = 2), `PSC values` (2), `LINE`: **2m + 5 scalars**; m = 0 has no `PSC round` (M:110-112).

With bit(0), bit(1), .. the binding order: round l is an equality round at `z_(m-1-bit(l))`; its challenge becomes coordinate `r_(m-1-bit(l))` of a point r (M:666-669). After `PSC values`, `LINE` samples xi. The level leaves (M:670-675):
1. claim `Left(C; shown(jE) shown(jE+1); 0) = 0` — hiding-polynomial variables counted in the order of the **rounds**, not of the bits;
2. next point `z' = (xi, r_0, .., r_(m-1))` (m+1 coordinates);
3. next start form `C' = (1 - xi) hidden(jE) + xi hidden(jE+1)`.

Orders (M:115-118): **default** = highest bit down to bit 0; **range order** = bits 2, 1, 0, 5, 4, 3, 8, 7, 6, then the others from the highest down to bit 9; a lookup's last key level has a third (§2.6). A product level *outside* a lookup runs the same rounds, `LINE` included, leaves claim 1 only; its xi enters no formula; the segment gives two further claims on hidden(jE), hidden(jE+1) at r (M:677-681).

### 2.5 Batching: three distinct mechanisms

| where | element | rows | powers | cite |
|---|---|---|---|---|
| claims of a segment | chi of the segment's last `BAT-sigma` | claim i; smallness equation x | chi^i; chi^(NCm + x) | M:46-52, 1260-1262 |
| weight claims (the merge) | x of the merge's `BAT-sigma`, n = NA | weight claim a | x^a | M:972-974 |
| all rows of a group (`BAT`, or theta of `CS`) | theta | row N in the fixed class order | theta^N | T1:482-492; S10:411-431 |
| pending rows on the table | x of the frame's `BAT-sigma`, n = `pending rows` | row j | x^j | S10:241-244; F:2583 |

### 2.6 The lookup (variant: product trees with bit-decomposed multiplicities; not a logarithmic derivative)

**Variant.** Not a log-derivative argument. It proves `Z = a_pad x prod_{j<32} G_j^(2^j)` where Z is the product of (alpha - shifted key) over all key positions and G_j is the product, over the table rows whose multiplicity has bit j set, of (alpha - shifted row value) (M:755-757, 739-753; T3:1133-1137). Multiplicities are committed **in bits, in 32 planes**; keys are never sent (M:132-133).

**Sizes** (M:126-156). All calls of a segment's list run as one lookup; the smallness test's two calls run as a second: every segment has two lookups. Call c (list order): 2^(n_c) keys, public table of 2^(k_c) rows. `dT = min(lidb, all n_c)` (`lidb` = 22 if the line is absent); `kT = max k_c`; NC calls (<= 16), cK least with 2^cK >= NC; `NT = sum_c 2^(n_c - dT)` (<= 256), rK least with 2^rK >= NT; `v = dT + rK`; `dL = kT + cK`. Rejected parameter file unless dT >= 10, v < 32, 2^(dL+32) < p. Some key positions are public **padding**: a padding key is a fixed row of its call's table and is not counted in the multiplicities. Padding rows (M:152-155): row 0 of a range table, of the head's table of exponentials, of attention's `KR` and `WH`; row u0 of `KFD`; row 32768 of the clamp, the gate function and the sigmoid. Reject a parameter file under which all keys of a call are padding.

**Tests on sizes, with rejection names** (public files only; M:759-772): per call 5 <= k_c <= 16, t0_c < 2^(k_c), 0 <= n_c <= 62, listed table has 2^(k_c) rows (`shape-pt-words-NAME`); every listed row value < p (`forest-row-value-NAME`); n_c >= 10 (`hid-call-floor`); 32 planes, no separately counted row (`hid-planes-NAME`); 1 <= NC <= 16 (`forest-calls`); dT >= 10 (`forest-depth`); NT <= 256 (`forest-trees`); v < 32 (`forest-keys`); 2^(dL+32) < p (`no-wrap-pin-forest`); npad(y) <= 2^dT (`pt-pub-forest`); per call sum of npad over its trees < 2^(n_c) (`forest-only-padding-NAME`); 5 <= lm <= kT + 5 (`forest-planes`). Purpose stated: v < 32 so a 32-bit multiplicity has room for all keys; 2^(dL+32) < p so the sum of multiplicities cannot wrap (M:774-775).

**Trees and indices** (M:733-753, 172-178). Sort calls by decreasing iota_c = n_c - dT (ties keep list order); give each the next 2^(iota_c) tree numbers: tree0(c) (a multiple of 2^(iota_c)), call(y). Key i of call c is in tree `y = tree0(c) + floor(i / 2^dT)` at `x = i mod 2^dT`. Key-side leaf index is `(x | y) = x 2^rK + y` (tree number in the **low** rK bits):
- y < NT: `alpha - c theta - key_c((y - tree0(c)) 2^dT + x)`, c = call(y); at a padding position the key is tab_c(t0_c), so the leaf is `alpha - padkey_c`, `padkey_c = tab_c(t0_c) + c theta`;
- y >= NT: `alpha - padkey_0` (padding of **call 0**, whichever call has the highest trees: M:1020-1021).
Table-side leaf index `(t | c | j) = (t 2^cK + c) 32 + j` (plane j in the low 5 bits, call c in the next cK, row t in the top kT): leaf = `1 + b(t,c,j) (alpha - 1 - rowval(t,c))`, `rowval(t,c) = tab_c'(t mod 2^(k_c')) + c' theta`, c' = min(c, NC-1), b = 0 for c >= NC. For c >= NC the table repeats the **last** call's rows with shift (NC-1) theta; a table with fewer than 2^kT rows is repeated (M:177-178, 1016-1018).

**The nine steps** (M:158-168):

| no. | step | rounds | scalars | sampled |
|---|---|---|---|---|
| 1 | the shift, only if NC > 1 | `LKP shift` | 0 | theta (1 element); theta = 0 if NC = 1 |
| 2 | point of comparison | `LKP` | 0 | alpha |
| 3 | the tie: 31 sumchecks without a variable, d_Y = 3, 3 end values in the first, 2 in each other | 31 x (`PSC epsilon`, `PSC Y`, `PSC values`) | 7 + 30 x 6 = 187 | 31 x (eps, beta) |
| 4 | point joining the 32 planes' roots | `JOIN` | 0 | 5 elements, coordinate of the lowest bit first |
| 5 | key side: product levels m = 0..v-1 | per level | sum (2m+5) = v^2 + 4v | per level |
| 6 | table side: product levels m = 5..4+dL | per level | sum (2m+5) = dL^2 + 14 dL | per level |
| 7 | table leaves: dL equality rounds of degree 2 then 5 of degree 1; shows no value | `PSC epsilon`, (5+dL) x `PSC round` | 1 + 2 dL + 5 | eps, 5 + dL challenges |
| 8 | a fresh point | `ZERO` | 0 | 5 + dL elements, lowest bit first |
| 9 | the bits are bits: 5 + dL equality rounds of degree 2, d_Y = 2, 1 end value | `PSC epsilon`, (5+dL) x `PSC round`, `PSC Y`, `PSC values` | 2 (5+dL) + 4 | eps, 5+dL challenges, beta |

Total scalars `187 + (v^2 + 4v) + (dL^2 + 14 dL) + (2 dL + 6) + (2 dL + 14)`, neighbouring numbers from jLK (M:777-778). Numbers (M:780-787):

| sumcheck | j0 | jE |
|---|---|---|
| tie step 0 | jLK | jLK + 4 |
| tie step s = 1..30 | jLK + 7 + 6 (s-1) | j0 + 4 |
| key level m = 0..v-1 | jLK + 187 + m^2 + 4m | j0 + 2m + 3 |
| table level m = 5..4+dL | jLK + 187 + v^2 + 4v + m^2 + 4m - 45 | j0 + 2m + 3 |
| step 7 leaves | jLK + 187 + v^2 + 4v + dL^2 + 14 dL | none |
| step 9 bits | leaves' j0 + 2 dL + 6 | j0 + 2 dL + 13 (= jBit) |

**Step 2**: `a_pad = (alpha - padkey_0)^((2^rK - NT) 2^dT) x prod_{y<NT} (alpha - padkey_call(y))^(npad(y))` (M:789-793); `NPAD = (2^rK - NT) 2^dT + sum_{y<NT} npad(y)` (M:709).

**Step 3, the tie** (M:795-812). Hidden values: Z; G_j; `P_31 = G_31`, `P_s = P_(s+1)^2 G_s` (M:715-717). Each step has Y alone (NV = 1), hiding coefficients mask(j0)..mask(j0+3) of degrees 0..3.

| s | C | end values in order sent | numbers | S0 |
|---|---|---|---|---|
| 0 | 0 | Z, P_1, G_0 | jZ = jLK+4, jP_1 = jLK+5, jG_0 = jLK+6 | `shown(jZ) - a_pad shown(jP_1)^2 shown(jG_0)` |
| 1..30 | hidden(jP_s) | P_(s+1), G_s | jP_(s+1) = j0+4, jG_s = j0+5 | `shown(jP_(s+1))^2 shown(jG_s)` |

G_31 has no end value of its own: `jG_31 = jP_31` (M:804, 1019). K = 0. Claim of step s: `mask(j0) + beta mask(j0+1) + beta^2 mask(j0+2) + beta^3 mask(j0+3) + eps (pub(C) - C) + eps S0 - cur = 0`, with `cur = hs + eps pub(C) + g_1 beta + g_2 beta^2 + g_3 beta^3` (M:804-812).

**Step 4**: `JOIN` samples 5 elements, bit 0 of j first; zT_5 = these reversed (bit 4 first); `CT_5 = sum_{j<32} eq(zT_5, j) hidden(jG_j)` (M:814-816).

**Step 5, key side** (M:818-824): zK_0 empty, `CK_0 = hidden(jZ)`; for m = 0..v-1 the product level at zK_m with CK_m gives zK_(m+1), CK_(m+1). Levels m < v-1 bind bits m-1, .., 0 (default order). **Level m = v-1** binds bits `rK+2, rK+1, rK, rK+5, rK+4, rK+3, rK+8, rK+7, rK+6`, then v-2, v-3, .., rK+9, then rK-1, .., 0. After it: zx = first dT coordinates of zK_v, zy = last rK, `C_end = CK_v`.

**Step 6, table side** (M:826-829): for m = 5..4+dL the product level at zT_m with CT_m, default order. zT_(5+dL): first the kT coordinates of t (highest bit first), then cK of c, then 5 of j.

**Step 7, leaves** (M:831-837): start form CT_(5+dL); round l (l = 0..4+dL) is at coordinate l of zT_(5+dL); degree 2 for l < dL, degree 1 for l >= dL; no Y (NV = 5+dL); the last variable (bit 0 of j) carries the constant: `u(4+dL,0) = mask(j0 + 2dL + 4)`, `u(4+dL,1) = mask(j0 + 2dL + 5)`. `zb_0 = (gamma_0..gamma_(4+dL))`. Summand `1 + (planes)(alpha - 1 - rows)`: **S0 = 1**, `K = A_L PL_0`.

**Steps 8–9, bits** (M:839-843): `ZERO` samples 5+dL elements, bit 0 of j first; zq = reversed. Step 9: start form 0, 5+dL equality rounds of degree 2, round l at coordinate l of zq, d_Y = 2, one end value (number jBit). `zb_1 = (gamma_0..gamma_(4+dL))` without beta. Summand b^2 - b: `S0 = shown(jBit)^2 - shown(jBit)`, K = 0.

**After step 9** (M:845-853). Split zb_e into zbt_e (first kT), zbc_e (next cK), zbj_e (last 5).
1. `h_c = rK - iota_c`; `e_c = eq((zy_0..zy_(h_c-1)), tree0(c) / 2^(iota_c))` (1 if h_c = 0).
2. Key point `zk_c = (zy_(h_c)..zy_(rK-1), zx_0..zx_(dT-1))`, n_c coordinates (zy part first: M:1013-1015).
3. zu = last k_c coordinates of zbt_0; `T_c = sum_{t<2^(k_c)} eq(zu,t) tab_c(t)`; range table: `T_c = sum_{i<k_c} 2^(k_c-1-i) zu_i`.
4. `A_L = alpha - 1 - sum_{c<2^cK} eq(zbc_0, c) (T_c' + c' theta)`, c' = min(c, NC-1).

**Planes as a form** (M:855-875): `PL_e = sum_{t<2^kT, c<NC, j<32} eq(zb_e, (t|c|j)) b(t,c,j)`. Hosts keeping planes in a matrix MB of 2^lm rows, NC 2^wd columns (wd = kT + 5 - lm): bit (t,c,j) is in row `(t mod 2^(lm-5)) 32 + j`, column `c 2^wd + floor(t / 2^(lm-5))` (equivalently S = (c 2^kT + t) 32 + j, column floor(S/2^lm), row S mod 2^lm: M:196-197). Row weights `phiB_e(row) = eq((last lm-5 coordinates of zbt_e | zbj_e), row)`, `phiP(row) = 2^(row mod 32)`. Host forms `TB_e(col)`, `TP(col)`; `PL_e = sum_{c<NC, th<2^wd} eq(zbc_e, c) eq(first wd coordinates of zbt_e, th) TB_e(c 2^wd + th)`. lm = line `lmb` / `lmbA` / `lmbH`; matrices b / bA / bH; in the three segment kinds TB_0, TB_1, TP are three parts of `U3` (M:192-195, 873-875).

**Claims** — three groups, each a run of neighbouring claim numbers; the host says where (M:916-917):
- *On mask entries alone*, 31 + v + dL + 1 claims in this order (M:877-889): LK0 `Left(0; shown(jZ) - a_pad shown(jP_1)^2 shown(jG_0); 0)`; LKs (s = 1..30) `Left(hidden(jP_s); shown(jP_(s+1))^2 shown(jG_s); 0)`; LK(31+m), m = 0..v-1, `Left(CK_m; shown(jE) shown(jE+1); 0)`; LK(26+v+m), m = 5..4+dL, `Left(CT_m; shown(jE) shown(jE+1); 0)`; LK(31+v+dL) `Left(0; shown(jBit)^2 - shown(jBit); 0)`.
- *Three claims on the planes* (M:891-903): LP0 `Left(CT_(5+dL); 1; A_L PL_0) = 0`; LP1 `hidden(jBit) - PL_1 = 0`; LP2 `sum_{col<NC 2^wd} TP(col) - (2^v - NPAD) = 0`.
- *The join* (one claim; M:905-917): `LJ = sum_{c<NC} e_c (alpha - c theta - KF_c) + (alpha - padkey_0) sum_{y=NT}^{2^rK-1} eq(zy, y) - C_end = 0`, KF_c = host's key form for `sum_{i<2^(n_c)} eq(zk_c, i) key_c(i)` with tab_c(t0_c) at every padding position. Head and attention add it as a claim; the smallness test adds it written on `ZZ`; a feed-forward segment has **no claim** for it (the join is inside a later start form) [OOS 11.2].

**Ordering duties of the host** (M:930-963): committed and out-of-domain-answered before theta (alpha if NC = 1): the planes, every array the keys are read from, the mask row. Fixed by the chain before that round: order/number of calls, n_c, k_c, table, t0_c, `lidb`, every npad(y), lm and bit placement, the key forms, the mask row's root and length, jLK, the number of earlier claims. The plan does **not** fix them (it holds only v, dL, planes, whether theta is sampled; e.g. (dT,rK) = (10,2) and (11,1) share a plan); by the page's reading the `configuration` digest does. Padding is described twice (a_pad/NPAD vs key forms): `internal-forest-padding-places`, not provable-causable (M:919-928).

**Public tables** (M:316-344): range tables (8, 10, 16 bits) row t = t; the other tables of feed-forward segments and the head have 65,536 rows, each packing argument and value into one number < p: clamp `t + 2^28 (clamp(t - 32768, -2047..2047) + 2048)`; gate `t + 2^28 (s(t) + 4096)`; sigmoid `t + 2^17 x 16 round(4096 sigmoid((t-32768)/256))`; exponentials of the head `u + 2^16 EX[u]`; attention `KR`, `WH`, `KFD` (2^kFD rows). **Four tables are computed in double-precision floating point** (gate, sigmoid, rotary: halves away from zero; attention's exponential: halves to even); "the format does not define these values by integer arithmetic"; a second verifier computes them to the bit or takes them as data; digests may be in the parameter file (lines `tsilu0..7`, `tsig0..7`, `trope0..7`, `texp0..7`; all 32 or none; a file that has them is rejected unless NE > 0; if present each table's digest must match; R15.3, §12.6).

### 2.7 The merge (claims on the committed weights)

- Present in feed-forward segments and the head; attention has none (W5:124-125). NA weight claims (1..4096: W5:133-134), each with hidden(jV_a) (an earlier end value or a hidden value sent alone), all sent before the merge's `BAT-sigma` (M:967-970).
- Rounds: `BAT-sigma` with n = NA samples x (also if NA = 1); start form `C = sum_{a<NA} x^a hidden(jV_a)`; then a sumcheck with **lkW plain rounds of degree 2**, d_Y = 1, one end value fv' — short form [2,..,2 | 1 | 1]; lkW = last number of the line `table`; round 0 binds the highest column bit; **2 lkW + 3 scalars**; `jFv = j0 + 2 lkW + 2` (M:202-205, 972-978; W5:136-141).
- In a plain round the two scalars are g_0 and g_2; `g_1 = cur - 2 g_0 - g_2` (M:989).
- Claim: S0 = shown(jFv) = fv', K = 0: `Left(C; fv'; 0) = 0`; in feed-forward and head it is the segment's last claim. With psi_l = rm_l, `tail_l = rm_(l+1) .. rm_(lkW-1)`, `PP = rm_0 .. rm_(lkW-1)`:
  `sum_{l<lkW} tail_l (rm_l mask(j0+2l) + rm_l^2 mask(j0+2l+1)) + mask(j0+2lkW) + beta mask(j0+2lkW+1) + eps PP (pub(C) - C) + eps fv' - cur = 0`, `pub(C) - C = sum_a x^a factor(jV_a) mask(jV_a)` (M:980-987).
- **fv' is masked by an entry of the request's index-mask message, not by the segment's mask row**; segments with a merge take these entries in the order of the segments. No claim names hidden(jFv): LS(jFv) = 0, MC(jFv) = 0 (M:205-218, 991-993). Soundness rests on the index-mask message (root + answered out-of-domain sample) coming before beta — true by R14.4 (a) (M:207-216).
- What goes out, as a **pending row on the stored table**: fv', beta, the point (rm_0..rm_(lkW-1)) taken reversed by the frame, and x (M:993-996); formula in §4.4.

### 2.8 The smallness test (the protocol page's "range check")

**Statements**: the cells in a segment's packed arrays are small integers, and the entries of `U3` are sums of these cells (M:220-222). Source-stated purpose: each integer is above -2^18 and below 2^18 (twice the offset 2^17); the test does not state a cell is a byte (M:1437-1441).

**Constants** (M:1097-1107): 3 cell rows per packed row (`LANES`); radix 2^20; offset 2^17; low digit 10 bits, high digit 8 bits; at most 8191 columns per matrix; 32 rows of `BZ` / planes; tau = line `tau`; calls `R10z` (call 0, low digits), `R8d` (call 1, high digits). Build-time relations (f1), (f2): `2^20 >= 4 x 2^17 - 1`, `(4 x 2^17 - 2)(1 + 2^20 + 2^40) < p`, `(8191+1) 2^14 2^7 <= 2^34`, `2^(10+8) = 2 x 2^17` (M:1463-1475).

**Steps** (M:225-236): 1 `RNG` (nothing sent; (number of columns of all matrices of the list) x tau entries in {-1,0,1} by R6.7); 2 the moment of the digits (`SEND seed`, `SEND answer`: `ZZ` then `BZ`); 3 a lookup with two calls (so with `LKP shift`). The equations have no round of their own.

**Arrays** (M:249-276, 1109-1145):

| name in `layout` | moment | rows | columns | over |
|---|---|---|---|---|
| `M`mu (each matrix the segment commits to itself) | 0 (first those no other segment reads, then those another reads, list order) | ceil(m_mu / 3) = mp_mu | k_mu | F |
| `U3` | 1 | 1 | length of the vector | E |
| `ZZ` | 2 | tau | 2 mz | F |
| `BZ` | 2, after `ZZ` | 32 | 2^11 | F |

- `M_mu[i'][c] = cell(3i') + 2^20 cell(3i'+1) + 2^40 cell(3i'+2)` over the integers, then mod p; cell rows >= m_mu count as 0; a matrix of an earlier segment has no array here — this segment reads that segment's `M`mu' whole (M:263-264, 274-276, 1111-1119).
- `ZZ[u][off(mu)+i]` = low digit, `ZZ[u][mz + off(mu)+i]` = high digit of `comb(mu,i,u) + 2^17`; `val(u,crow) = ZZ[u][crow] + 2^10 ZZ[u][mz+crow] - 2^17`; mz = sum of m_mu over all matrices of the list; off(mu) = cell rows before mu (M:265-268, 1068, 1129-1133). The high digits begin at column mz, not at a power of two (M:1487-1488).
- `U3` = parts one after another; part f (matrix mat(f), weight vector phi_f of len(f) entries, nb(f) = m_mat(f)/len(f) blocks): `at(0) = 0`, `at(f+1) = at(f) + k_mat(f) nb(f)`; entry for column c, block b is `U3[at(f) + c nb(f) + b]` (column index is the slow one), meant to be `sum_{r<len(f)} phi_f[r] cell(mat(f), b len(f) + r, c)` (M:268-273, 1121-1127, 1500).
- `BZ`: bit b(t,c,j) (t < 2^10, c < 2, j < 32) with `X = (2t + c) 32 + j` is `BZ[floor(X / 2^11)][X mod 2^11]` — row = top five bits of t; not packed; not the rule of b/bA/bH (M:1137-1145).
- **Sampled matrix**: entry number `(col0(mu) + c) tau + u` of the `RNG` sequence is Theta_mu[c][u] (matrix by matrix, earlier segments' included, column by column, increasing u); one entry serves the packed rows and all reads of that column (M:1149-1155, 1491-1492).

**Public-number tests** (M:1365-1382): tau multiple of 32, 32 <= tau <= 256, tau1 = 0 or a power of two (`hid-tau`); tau >= `sec` (`policy-tau-hb`); tau = the plan's derived number, so tau = `sec` (`plan-tau`); NM < 256 and at least one matrix is the segment's own and read by no other (`plan-link`); m_mu >= 1 (`shape-matrix-`); 1 <= k_mu <= 8191 (`hid-k-range`); no weight matrix in the list (`t2f-weight-class`); 2 mz < 2^32 (`t2f-columns-range`); earlier segment's matrix: same m, k, first column (`shape-foreign-`), from an earlier feed-forward segment that lists it as read by others (`plan-fold-source`); n_Z - dT <= 7 (`forest-trees`); v_Z < 32 (`forest-keys`); len(f) >= 1, len(f) | m_mat(f), phi_f has len(f) entries (`shape-functional-`). Hiding condition `range-checks` (16.1 cond. 7) reads these sizes: `floor(14426 x 2^34 / (10000 x 2^14 k_mu)) - 1 - clog2(m_mu) - clog2(tau)`, failing -> `parameters-not-admitted` (M:1384-1391).

**The lookup on the digits** (M:238-241, 1173-1205): NC = 2, tables of 2^10 and 2^8 rows (tab(t) = t; call 1's table repeated four times), padding row 0; `n_Z = max(10, clog2(tau) + lc)`, lc = clog2(mz); keys `key_0(u 2^lc + crow) = ZZ[u][crow]`, `key_1(u 2^lc + crow) = ZZ[u][mz + crow]`; every other key number is padding (tau mz real keys per call). kT = 10, cK = 1, **dL = 11**; dT = min(lidb, n_Z); iota_0 = iota_1 = n_Z - dT; NT = 2^rK with rK = n_Z - dT + 1 (no padding-only tree); **v_Z = n_Z + 1**. Derived values:
1. `a_pad = alpha^(2^(n_Z) - tau mz) (alpha - theta)^(2^(n_Z) - tau mz)`;
2. `e_0 = 1 - zy[0]`, `e_1 = zy[0]`;
3. one key point `zk = (zy[1..rK-1], zx)` (n_Z coordinates);
4. `T_0 = sum_{s=0}^{9} 2^(9-s) zb_0[s]`, `T_1 = sum_{s=0}^{7} 2^(7-s) zb_0[2+s]` (zb has 16 coordinates: ten of t, one of c, five of j);
5. `A_L = alpha - 1 - ((1 - zb_0[10]) T_0 + zb_0[10] (T_1 + theta))`;
6. NPAD = 2 (2^(n_Z) - tau mz); real keys = 2 tau mz;
7. jLK = number of scalars the segment has sent before `RNG`.

Key forms as combined rows (M:1207-1222): tau0 = largest power of two <= tau, tau1 = tau - tau0; block 0 = rows 0..tau0-1, block 1 (if tau1 > 0) = rows tau0..tau-1; R_blk, row0_blk, a_blk = log2 R_blk, h_blk = n_Z - a_blk - lc; cut zk into zk_top,blk (first h_blk), zk_row,blk (next a_blk), zk_col (last lc); `eq(zk, u 2^lc + crow) = eq(zk_top,blk, row0_blk / R_blk) eq(zk_row,blk, u - row0_blk) eq(zk_col, crow)`; kw_blk(u) = eq(zk_row,blk, u - row0_blk) on block blk; `KF_0 = sum_blk eq(zk_top,blk, row0_blk/R_blk) sum_{crow<mz} eq(zk_col, crow) ZZ{kw_blk}[crow]`, KF_1 the same with column mz + crow. Planes read from `BZ` directly: `bw_e(row) = eq(first 5 coordinates of zb_e, row)`; `PL_e = sum_{col<2^11} eq(last 11 coordinates of zb_e, col) BZ{bw_e}[col]` (M:1224-1229).

**Equations** (M:1237-1262):
- packed row: `EP(mu,i',u): val(u,crow) + 2^20 val(u,crow+1) + 2^40 val(u,crow+2) - sum_{c<k_mu} Theta_mu[c][u] M_mu[i'][c] = 0`, crow = off(mu) + 3i'; a term whose cell row is not below m_mu is left out **with its constant -2^17**;
- read (f,b): `ER(f,b,u): sum_{r<len(f)} phi_f[r] val(u,crow+r) - sum_{c<k_mu} Theta_mu[c][u] U3[at(f) + c nb(f) + b] = 0`, crow = off(mu) + b len(f);
- reads numbered q = 0..NX-1 by matrix, then by part f (increasing), then by block b; NX = sum nb(f);
- numbers: tauP = tau rounded up to a power of two; `first_0 = 0`, `first_(mu+1) = first_mu + tauP 2^clog2(mp_mu)`; EP(mu,i',u) has number `first_mu + i' tauP + u`; ER of read q has `first_NM + q tauP + u`; `Q = first_NM + NX tauP`; unused numbers still count in n;
- **equation x gets chi^(NCm + x)**, NCm = number of all the segment's claims (also those added after the test).

**Claims, in order** — 47 + v_Z + NM + NX claims from number n0 (M:278-304, 1264-1277); nJ = n0 + 43 + v_Z:

| number | claim | form | coefficient |
|---|---|---|---|
| n0 .. n0+42+v_Z | LK0..LK(42+v_Z): 31 tie, v_Z key levels, 11 table levels, 1 bits | §2.6 | chi^(number) |
| nJ | LJ | `e_0 (alpha - KF_0) + e_1 (alpha - theta - KF_1) - C_end` (no empty-tree term) | chi^nJ |
| nJ+1 | LP0 | `Left(CT_16; 1; A_L PL_0)` | chi^(nJ+1) |
| nJ+2 | LP1 | `hidden(jBit) - PL_1` | chi^(nJ+2) |
| nJ+3 | LP2 | `sum_{row<32, col<2^11} 2^(col mod 32) BZ[row][col] - 2 tau mz` | chi^(nJ+3) |
| nJ+4+mu | TIE_mu = `sum_{i'<mp_mu, u<tau} chi^(i' tauP + u) EP(mu,i',u)` | below | **chi^(NCm + first_mu)** |
| nJ+4+NM+q | READ_q = `sum_{u<tau} chi^u ER(f,b,u)` | below | **chi^(NCm + first_NM + q tauP)** |

With `pw(u) = chi^u` (rows of `ZZ`), `rw_mu(i') = chi^(tauP i')`, `cellw_mu(i) = rw_mu(floor(i/3)) 2^(20 (i mod 3))`, `colw_mu(c) = sum_{u<tau} chi^u Theta_mu[c][u]`, `spw = sum_{u<tau} chi^u` (M:1073-1077):

`TIE_mu = sum_{i<m_mu} cellw_mu(i) (ZZ{pw}[off(mu)+i] + 2^10 ZZ{pw}[mz+off(mu)+i]) - 2^17 spw sum_{i<m_mu} cellw_mu(i) - sum_{c<k_mu} colw_mu(c) M_mu{rw_mu}[c]` (M:1285);

`READ_q = sum_{r<len(f)} phi_f[r] (ZZ{pw}[off(mu)+b len(f)+r] + 2^10 ZZ{pw}[mz+off(mu)+b len(f)+r]) - 2^17 spw sum_r phi_f[r] - sum_{c<k_mu} colw_mu(c) U3[at(f) + c nb(f) + b]` (M:1290).

The number a TIE/READ claim takes is **not** its power (M:1292-1296). In an attention segment the smallness claims are the segment's last (M:303-304). The full table of column weights per array/row-weights and of added constants is M:1309-1331 (copy it verbatim into the spec); row-weight shapes bit by bit (bit 0 first, as the frame takes them) are M:1345-1351: pw bit s -> (1, chi^(2^s)); rw_mu bit s -> (1, chi^(tauP 2^s)); kw_blk low a_blk bits -> (1-z, z) of zk_row,blk with the last coordinate for bit 0, each higher bit s -> (1,0)/(0,1) by bit s of row0_blk; bw_e five bits -> (1-z, z), the fifth coordinate for bit 0; ones -> (1,1).

**Order facts**: the cells' arrays (own `M`mu, `U3`, earlier segments' arrays sent again) are committed and answered before `RNG`; `ZZ`, `BZ` after; a second verifier takes an array's moment from the table of moments, never from the layout file (M:1157-1171). The list of parts with all phi_f is fixed before `RNG` (M:1402-1404). The test sends no scalar but those of its lookup (M:1399-1400).

### 2.9 Sampled values at which a verifier gives no acceptance

After all claims are added, test that no weight that should bind a committed entry is 0 (M:1408-1411). Events (M:1413-1433; table with names, F:2465-2475): (1) `colw_mu(c) = 0` for some column (`internal-f-table-read`); (2) a column weight of the one equation is 0 (`internal-t2f-untyped-`+array): any entry of `U3`; `ZZ` under kw_blk (crow for call 0, mz+crow for call 1); `ZZ` under pw, any of 2 mz columns, separately for READ and TIE; `BZ`, any of 2^11 columns under bw_0, bw_1 or ones; any column of a matrix's array; (3) `chi^nJ e_0` or `chi^nJ e_1` is 0, or `eq(zk, u 2^lc + crow) = 0` for some real key (`internal-t2f-untiled` / `-untyped-`; enough to test the first row of each block with every column and every row with the first column); (4) two rw_mu(i') of one matrix equal, or one is 0 (`internal-sym-rowvec`); `chi^(NCm+first_mu) cellw_mu(i) = 0` (`internal-f-tie-weights`). Plus (F:2467, 2475): eps = 0 in the second token sumcheck of a feed-forward segment (`coin-zero`, a rejection) and "the coefficient of a scalar in the sum of all claims is 0; the merge's end value fv' is left out" (`internal-g/a/h-free-slot`) [OOS 11.2–11.4]. A two-answer verifier **rejects** at every one of these; `cp_verify` rejects at `coin-zero` and ends `NOT CHECKED` at the others (F:2458-2463). They are a completeness error only.

### 2.10 The frame's blocks (what consumes the segment's row)

**SEND / out-of-domain sample** (T1:274-323; F:2554-2556; R6.9 F:539-549).
- After a prover's message with oracle messages, round `SEND seed` samples s seeds: each `z_0..z_(a-1)` (any elements of E) then `beta != 0`; a = largest cube a_o among the messages with s > 0 in that prover's message; each uses the **first** a_o coordinates. Cube: with both tables `a_o = max(A_m, A_z) + 1`, else the one table's bits; `A_m = b_m + log2 l`, `A_z = b_z + log2 l_zk`, b = ceil(log2 real rows); index of (row r, place c) is `r + 2^b c`.
- Answers open the prover's next message: by oracle message in order of sending, then by answer number; closed by `SEND answer` (empty verifier message) or by the caller's next verifier message (`LOC` / `CS`).
- Sample row per answer: `sum_j u[j] m[j] + sum_j v[j] w[j] = y`, `u[j] = (1 - z_(a_o-1)) prod_{t=A_m}^{a_o-2} (1 - z_t) eq(j; z_0..z_(A_m-1))`, `v[j] = z_(a_o-1) prod_{t=A_z}^{a_o-2} (1 - z_t) eq(j; z_0..z_(A_z-1))` at every non-pad index (frame eq: bit t <-> z_t); one table only: weight `eq(j; z_0..z_(a_o-1))`.
- Pad of answer i: coefficient beta in its own answer's row, 0 in the others, no weight under z. With mask rows: last real mask row R-1, place `l_zk - s + i`. No mask rows, main rows over E: last real main row, place `l - s + i`. Over F: three entries at places `l - 3s + 3i + t`, t = 0,1,2, coefficients `beta X^t`.
- The **ledger** of free mask entries: indices of the mask table from 0 upward below the first pad's index, skipping rows nobody sends; taken in order, each once; closes when the first proximity test on a group holding the message begins (T1:338-343; S9:109-116).
- Checked on the spot: nothing but canonical form / missing answers / nonce (T1:345-350). In all files s = 1: the parameter-file parser refuses any `answers` but 1 (T3:2115).

**BAT on a group** (T1:451-492; S10:411-431). Group layout: a member with K real rows takes an aligned block of 2^ceil(log2 K) rows; blocks placed from row 0 by decreasing size, ties in order of sending; h = least number holding the mask blocks, k = least holding the main blocks with k >= max(h, 1); kept members are not among the 2^k rows. Row order: (1) rows that are neither sample nor generator rows, in creation order — in a segment from the second on: the carried claim, then per kept message sent again its s old sample rows, then **the sub-proof's rows**; (2) sample rows by member in order of sending, by answer; (3) generator rows by the draws: main, each kept row, old mask, fresh mask. One element theta; `c = sum theta^i c_i`, `d = sum theta^i d_i`, `target = sum theta^i t_i`; kept members' coefficients gathered in forms of their own. Row count of a segment's `BAT`: (sub-proof's rows) + s per out-of-domain-sampled member + [m > 1: `1 + s J + t (3 + K)`] (S10:442).

**FOLD** (T1:831-899; F:2611-2612). Prover: hiding sum sigma; verifier eps (`FOLD epsilon`, may be 0); `claim_0 = sigma + eps tau`; k rounds: read (q_0, q_2), `q_1 = claim - 2 q_0 - q_2`, sample g_j (`FOLD round`), `claim_j = q(g_j)`. No test. Output claim on the single rows (M_0 = fold of main rows, kept rows as sent, M_1 = fold of mask rows at g_1..g_h, M_2 = fold of the fresh mask):
`c' = eps fold(c; g_1..g_k)`, i.e. `c'[i] = eps sum_{b<2^k} eq(g,b) c[b + 2^k i]`; `c'_K = eps (1-g_1)..(1-g_k) c_K`; `d'_1 = eps g_(h+1)..g_k fold(d; g_1..g_h)`; `d'_2 = u(g)`; `tau' = claim_k`. With `A_l = prod_{j>l} g_j`: `u[0] = A_h`; `u[l] = g_l A_h` (1 <= l <= h); then `g_(h+1)^2 A_(h+1)`; for l = h+2..k: `g_l A_l`, `g_l^2 A_l`; then 1; 0 elsewhere; for h = k: u = (1, g_1, .., g_k, 0, ..). g_1 goes with the lowest row bit (F:2532-2534).

**The switch** — `LOC` between segments (CS^sigma), `CS` between stages (T1:1135-1154, 1271-1299, 1328-1406; T2:516-584; F:2613-2615).
1. Prover's message: G (+ kept messages sent again, + riders / next segment's messages). 2. `SEND seed`. 3. Answers. 4. `LOC` or `CS`: nonce (proof of work tested before anything is sampled), then t positions in [0, n) (n = old main code's length), and in `CS` one element theta (R6.10). 5. Openings at the **list** (sorted set) of the old group's trees (all members, kept ones, fresh mask), each checked against its root; rows follow the **draws** (repeats counted).
- Symbols at x: `y_0(x) = fold(main column; g_1..g_k)` (rows nobody sent = 0; kept symbols set aside), `y_1(x) = fold(mask column; g_1..g_h)`, `y_2(x) = fold(fresh mask column; g_1..g_h)`; mask rows read at `cp(x) = x mod n_zk`.
- "The rest": `M_1 | M_2 | R_0 | R_Kb.. | R_1 | R_2 | old pads`; offsets `A_1 = 0`, `A_2 = l_zk`, `T_0 = 2 l_zk`, `T_Kb = 2 l_zk + r (1 + q)`, `T_1 = 2 l_zk + r (1 + kappa)`, `T_2 = T_1 + r_zk`, `O_K = T_2 + r_zk + (pads of earlier kept members)` (T1:1201-1209). Stage target: G's main table read as a vector is M_0 (`mu(j) = j`), `P(i)` = i-th non-pad index of the mask table (pads at `(2^h' - 1) + 2^h' (l'_zk - s + i)`; s = 1: P(i) = i). Carrying message: `mu(j) = 2j` (row 0), `P(i) = 1 + 2i` (row 1, last s places = G's pad) (T1:1261-1269).
- Rows made, in order (T1:1337-1360): (a) carried claim `sum_j c[j] m(j) + sum_K carry_K(c_K) + sum_j d_1[j] w(A_1+j) + sum_j d_2[j] w(A_2+j) = tau`; (b) each kept member's old sample rows, carried over, target = old answer; (c) per draw x: main `sum_{j<l} Gm_C(x)[j] m(j) + sum_{j<r} Gt_C(x)[j] w(T_0+j) = y_0(x)`; each kept row; old mask with `Gm_Z(x')`, `A_1`, `T_1`, target y_1(x); fresh mask with A_2, T_2, y_2(x). `carry_K(v) = sum_{e not a pad place} v[e] K^new[e] + sum_i v[e_i] w(O_K + i)`.
- In `CS` only: batch at once, J = 1 + s + 3t rows: number 0 carried claim; 1..s G's sample rows; then per draw (main, old mask, fresh mask): `tau_new = tau + sum_{u=1}^{s} theta^u alpha_u + sum_{i=1}^{t} theta^(1+s+3(i-1)) (y_0(x_i) + theta y_1(x_i) + theta^2 y_2(x_i))` (T1:1391-1406).
- Checked on the spot: openings to roots (R7.10), one value per vertex (R7.14), canonical answers/symbols, nonce, file not ending early; no equation (T1:1421-1438).

**The proximity test on a group** (T1:1470-1557): stages (code, mask code, k, h), S >= 2; conditions: h <= k; every stage but the last k >= 1 and `l_zk >= 2k + 1 - h`; last stage k = h = 0; stage to next: `2^k' l' = l` exactly, `2^h' l'_zk >= 2 l_zk + r + 2 r_zk + s`, `s <= l'_zk`. Sequence: BAT; for i = 1..S-1: FOLD at stage i, then CS into stage i+1; then the last stage as single rows and BASE. Masks ride (word 1, always written by the programs: S10:237-238): the switch into stage i+1 carries G_(i+1) and that stage's fold mask, or BASE's masking word if it is the last. Last stage: `c_last[j] = c_new[2j]`, `d_last = d_new` (the group's one row variable fixed at 0) (T1:1541-1549).

**BASE — the only place where an equation on content is tested** (T1:916-1006; F:2436-2443). Rounds `BASE lambda` (kind 1; message: [root if masks do not ride;] tau*; sample lambda, may be 0) and `BASE` (kind 4; message: M'_0 (l), M'_1 (l'), R'_0 (r), R'_1 (r') elements of E in this order, S10:338-340, 371; sample the positions; nonce; openings of the last stage's tree).
- **B1**, before the positions are sampled: `<c, M'_0> + <d_1, M'_1> = tau* + lambda tau`.
- **B2**, once per distinct listed position x, ascending, both rows: `Enc_C(M'_0, R'_0)(x) = g*_0(x) + lambda y_0(x)` and `Enc_Z(M'_1, R'_1)(cp(x)) = g*_1(x) + lambda y_1(x)`, y = the last oracle message's opened symbols, g* = the masking word's.
- Accept iff B1, all B2, the openings, canonical form and the nonce hold; left-over bytes are rejected at the chain's end (T1:1002-1006).

### 2.11 Discharging the weight claims: the test on the table

(Rounds: S10:373-409; rows: F:2582-2594; library form: T3:1255-1337, 1831-2002. Formal rules R14.4 (e), R14.9, R14.10, R13.19 are [OOS].)
1. **Pending rows.** Each segment with a merge leaves `<Gamma (x) eq(psi, .), M> + beta c = fv'` (§4.4); a request with NG groups of layers has NG + 1 of them (W5:172), the item `pending rows`.
2. **Joining them** (first chain, after the last proximity test; only if `pending rows` > 1): `BAT-sigma` (x), then a sumcheck over the k_col column variables, plain rounds of degree 2 (g = 3), **no round in Y**, linear coefficient not sent, variables bound from the lowest up (S10:241-244; S9:124-125). `R_0 = mu' + eps sum_j x^j tau_j`; `q_1 = R - 2 q_0 - q_2`. It takes `1 + 2 k_col` fresh entries of the index-mask message right after x. Output row: `psi' = gamma`; `g' = sum_j a_j g_j`, `a_j = eps x^j eq(psi_j, gamma)`; masks: for l = 0..K-2 `(w_(2l), gamma_l G_l)`, `(w_(2l+1), gamma_l^2 G_l)` with `G_l = prod_{l<j<K} gamma_j`; for l = K-1 `(w_(2K-2), 1)`, `(w_(2K-1), gamma_(K-1))`, `(w_(2K), gamma_(K-1)^2)`; then every incoming mask term times `eps P x^j`, `P = prod gamma_t`; `tau' = R_K` (T3:1269-1307; F:2583).
3. **W**: `SEND seed`, `SEND answer` for W, then `SEAL` (S10:376-378). New own group {index-mask message, W}; row (Eval): `sum_c eq(psi', c) W<c> + masks' = tau'` (T3:1397-1407; F:2584).
4. **Slot** (R14.7): word, salt, sibling digests -> the binding tree's root, which is the shared chain's statement item and its random bytes (S10:263-271, 284-287).
5. **Shared chain** (label 0x46524d03): `LIN point` psi* (v + k_lo elements; first k_lo = psi_lo, last v = gamma); folded row G_u (`SEND seed`, `SEND answer`); record rows `(Rec_i): sum_{p<plain} eq(p; z^(i)) G_u<p> + beta^(i) sum_{t<3} X^t G_u<P(i,t)> = sum_r eq(r; gamma) y[r a + i]`; `LOC` (empty message; positions in the stored table's code) -> open the **stored table** against the root in the first query -> per draw `(Col_i): sum_p Gm_T(x)[p] G_u<p> + sum_q Gt_T(x)[q] G_u<B+q> = sum_r eq(r; gamma) col_x[r]`; Omega (`SEND seed`, `SEND answer`); `LIN zeta` (k_row elements); `(Fold): sum_{y<m} eq(y; zeta) Omega<y> - sum_{y<m, j<2^k_lo} eq(j; psi_lo) eq(y; zeta) G_u<j + 2^k_lo y> = 0`; [`SPLIT` if two base codes]; proximity test(s); `SEAL` (T3:1900-1973; S10:380-402).
6. **Second chain** (label 0x46524d04): adopts Omega's tree; `(Dot): sum_{y<m} g'[y] Omega<y> - sum_c eq(c; psi*) W<c> = 0`; proximity test on the own group {index-mask message, W, Omega}; its `BAT` batches 2 + 3s rows; W and Omega are always under one code (`parameter-own-code`) (T3:1975-1998; S10:308-323, 448; F:2594).

## 3. Polynomial / code toolkit the verifier needs

### 3.1 Multilinear tools

| tool | definition | cite |
|---|---|---|
| eq, sub-proof order | `eq(z,i) = prod_{s<n} (z_s if bit n-1-s of i else 1 - z_s)`; n = 0 gives 1 | M:395-397 |
| eq, frame order | `eq(j; z) = prod_{t<a} (j_t z_t + (1 - j_t)(1 - z_t))`, bit t of j with z_t | T1:242-244; S9:58-60 |
| eq of two points | `prod_t (a_t b_t + (1 - a_t)(1 - b_t))`; `eq1(u,y) = u y + (1-u)(1-y)` | F:2529; T3:1222-1223; W5:143 |
| conversion | eq_subproof(z, i) = eq_frame(reverse(z), i) | [INF] from M:346-354 |
| index concatenation | `(x | y)`: high bits x, low bits y; same sign joins coordinates of a point | M:398-399 |
| map value (MLE) | `a(z) = sum_{i<2^n} eq(z,i) a(i)` | M:400-403 |
| range-table MLE | `T_c = sum_{i<k_c} 2^(k_c-1-i) zu_i` (sub-proof order); frame order `sum_j 2^j z_j` | M:851-852; F:2570 |
| product-over-bits weights | `w(r) = prod_q (hi_q if bit q of r else lo_q)`; powers: (1, x^(2^q)) | M:473-476 |
| eqlow | `eqlow(lo,hi,i) = eq((rs_(hi-1),..,rs_lo), i)` | M:683-688 |
| fold of a table of 2^a rows | `fold(T; g)[c] = sum_b eq(g,b) T[b + 2^a c]`; stepwise: fixing the lowest variable at g replaces rows 2b, 2b+1 by (1-g) row(2b) + g row(2b+1); same rule folds messages, tails, opened columns and coefficient vectors | T1:795-800 |

### 3.2 Univariate tools

- Round polynomials arrive as **coefficients, lowest degree first** (M:78): evaluation by Horner. Degrees in the shared machinery: 1 (five lookup-leaf rounds, the merge's Y), 2 (most), 3 (the tie's Y; attention's nb-product rounds), and up to 64 (attention's per-round degrees) (M:107, 162, 655-656).
- **No interpolation** is needed anywhere: the one missing coefficient is recovered linearly from the running claim (M:96-100) [INF: no formula in M/W5/T1–T3 uses evaluations-form polynomials].
- Code symbol at a position: `Enc_C(M,R)(x) = sum_{j<r} R_j z_x^j + sum_{j<l} M_j z_x^(r+j)` — tail in the lowest r coefficients, message next; a row over E is encoded coordinate by coordinate (R12.11, S9:187-191; T1:106-107). Used in B2 and, as coefficient vectors `Gm_C(x)[j] = z^(r+j)`, `Gt_C(x)[j] = z^j` (entries in F), in the generator rows (T1:1107-1117). As a product over the bits of j: `f_i = z^(2^i)`, `b_j(x) = prod_{bits i of j} f_i` — why l must be a power of two for a switch (T1:1111-1114, 1249-1250).

### 3.3 Reed-Solomon domain (field 2, Goldilocks) — R12.11 (S9:182-196)

- A code is three words (a, l, r): length 2^a, l message entries, r random-tail entries; admitted: a from 1 to 60, l >= 1, l + r <= 2^a and <= 2^32 (R12.1, S9:153-158). No numbered rule covers lengths above 2^32; no parameter line admits one (S9:191-194).
- The code lives on the coset **7 H**, H the subgroup of order 2^a of F*; the shift is 7 at every length. `w = 7^(5 (2^32 - 1))`, order 2^32, as a word **0xE2AF70635744FD26**. **Point of position x**: `z_x = 7 x prod_{bits i of x that are 1} w^(2^(31-i))` (the factor for bit i is the root of unity of order 2^(i+1)). Position 0 -> 7; position 1 -> -7; positions 2m and 2m+1 are z and -z; the order of the points is the bit-reversed one (S9:182-187; T1:103-106).
- Mask code Z = (n_zk, l_zk, r_zk), n_zk <= n; where a main row is read at x, a mask row is read at the short position `cp(x) = x mod n_zk` (R7.2; T1:1124-1125).
- **NTT/FFT on the verifier's side: none.** The verifier never encodes or decodes a word; it evaluates symbols at the t sampled positions (B2) and uses generator rows as linear forms [INF from T1:991-996, 1349-1355]. z_x costs at most a multiplications from a 32-entry table `w^(2^(31-i))` [INF].

### 3.4 Base field vs cubic extension

| lives in F (8 bytes, canonical < p) | lives in E = F[X]/(X^3 - 2), 24 bytes: coordinates at 1, X, X^2, each a little-endian word < p |
|---|---|
| arrays `M`mu, `ZZ`, `BZ` (M:258-261); main rows over F; table values tab_c(t) < p (M:702); Theta entries in {-1,0,1} (M:1066); code points z_x and generator-row entries (T1:1109); stored-table symbols | every scalar a sub-proof sends (M:25); every sampled challenge (chi, x, eps, gamma, beta, alpha, theta, xi, points) (M:58-61, 77-79); `U3` (M:259); mask rows (always over E, S9:167); carrying message's main rows (T2:287); out-of-domain answers; W, Omega, G_u (S9:88-89); BASE's M', R' (T1:970) |

"All arithmetic is in E. An integer or an element of F in a formula means its image in E": (x, 0, 0) (M:389-390, 1092-1093). E's constant c = 2 in field 2 (R1.4, F:105; T1:226-230). Programs can be built for field 2 alone (T1:225-226).

**Inversion**: the only division in the shared machinery is the constant 2^(-lPd) (M:104-106); plain rounds divide nothing (T3:1286) [INF: no general field inversion is needed by M/W5/frame formulas; 11.2–11.4 may add some — OOS].

### 3.5 Sampling rules the machinery calls (F §5)

R6.4 element of F: at most six attempts on the next words, a word not below p fails (never reduced), all six fail -> 0; an element of E = three elements of F (F:512-518). R6.5 non-zero element of E: at most two elements by R6.4, the first that is not 0, else 1 (F:519-520). R6.6 position in [0, 2^k) = low k bits of the next word; **draws** (order sampled, repeats kept) vs **list** (sorted set) (F:521-529). R6.7 n entries over {-1,0,1}: each run of 32 entries takes one fresh word; entry j reads bits 2j and 2j+1 (from the lowest): 0 if bit 2j is 0, else +1 if bit 2j+1 is 0 and -1 if it is 1; runs counted from the round's first entry (F:530-534). R6.9 a seed = v elements by R6.4 then one by R6.5 (F:539-549). R6.10 in kind 4 the positions come first, then the element (F:550-551). Word caps R6.11: 18 per element by R6.4, 36 per element by R6.5, 1 per position, ceil(n/32) for n matrix entries (F:552-555). The only sampled values that must not be 0: `PSC Y`'s element and a seed's factor (F:505-507).

## 4. Weights in the table (11.5)

The verifier never sees a weight; it must reproduce the public placement to form the row weights Gamma of each pending row.

### 4.1 Matrix and table

- Each committed weight is an integer written in digits d_0..d_(nd-1), value `d_0 + 256 d_1 + .. + 256^(nd-1) d_(nd-1)`; **nd = 4 for the embedding, 2 for every other tensor**. All digits are the cells of one **committed matrix** (written W in 11.5 only; M in §9 and 13.9) with m0 rows and 2^lk columns. A key file states: every cell is in -128..127 and every two-digit weight in -4096..4095 (item `ranges`, R13.14) (W5:17-23).
- Line `table b n i m e w` (R15.2): lk = w, the table has 2^b rows, k_lo = w - b (§9/§10 write k_col for lk and v for b; 11.1 writes lkW). Cell (row y, column c) with `c = j + 2^k_lo r`, j < 2^k_lo, is entry `j + 2^k_lo y` of the message of **table row r**: the high b bits of a column number choose the table's row. Reject unless m0 2^k_lo entries fit a row's message beside its pads (W5:25-31).

### 4.2 Units (W5:35-65)

Deciding lines: `L`, `d`, `dh`, `H`, `G`, `f`, `fe`, `NE`, `V`, `D`, and w of `table`; dq = H dh, dkv = G dh; layer l has experts iff NE != 0 and l is odd. No layout-file line and no scale-file word enters.

| X | tensor | groups in order (name, extent, class) | nd | in |
|---|---|---|---|---|
| 0 | query and key | (hd, 64, A), (cd, dh, A), (kk, d, low) | 2 | every layer |
| 1 | value | (kk, d, low), (x, dkv, high) | 2 | every layer |
| 2 | attention output | (kk, dq, low), (x, d, high) | 2 | every layer |
| 3, 4 | gate, up | (kk, d, low), (x, f, high) | 2 | layers without experts |
| 5, 6 | shared expert's gate, up | (kk, d, low), (x, fe, high) | 2 | layers with experts |
| 7, 8 | routed experts' gate, up | (kk, d, low), (e, NE, low), (x, fe, high) | 2 | layers with experts |
| 9 | down / shared expert's down | (kk, f, low), (x, d, high); with experts (kk, fe, low), (x, d, high) | 2 | every layer |
| 10 | routed experts' down | (kk, fe, low), (e, NE, low), (x, d, high) | 2 | layers with experts |
| 11 | router | (kk, d, low), (x, NE, high) | 2 | layers with experts |
| 12 | embedding | (v, V, A), (x, d, high) | 4 | once, after the layers |
| 13 | output head | (x, V, A), (kk, d, low) | 2 | once, after the embedding |

Order of units: for l = 0..L-1: kinds 0, 1, 2; then 3, 4, 9 (no experts) or 5, 6, 7, 8, 9, 10, 11 (experts); after the layers 12 then 13 (they count as layer L). The extent 64 of hd is a constant (W5:63-65).

### 4.3 Column bits and the position of a digit (W5:69-107)

```
left = lk; cb = 0
for each group g of the unit, in order:            -- extent M
    low / high:  M = o * 2^z (o odd);  t = min(z, left)
    class A:     t = clog2(M) if clog2(M) <= left else 0
    cb0(g) = cb;  left -= t;  cb += t
    lambda(g) = M / 2^t (low, high);  class A: 1 if t > 0 else M
ncb = cb;   rows(unit) = nd * prod_g lambda(g)

cell (digit q < nd, index v_g < M_g per group):
    low:   col = v mod 2^t;                       rho = floor(v / 2^t)
    high:  z' = z - t;  col = floor(v / 2^z') mod 2^t;   rho = floor(v / 2^z) * 2^z' + (v mod 2^z')
    A:     (col, rho) = (v, 0) if t > 0 else (0, v)
    column c = sum_g col_g * 2^(cb0(g))
    row    y = off + rho_0 + lambda_0 * (rho_1 + lambda_1 * (rho_2 + lambda_2 * q))     -- two groups: lambda_2 = 1, rho_2 = 0
```

The first group's row part runs fastest, the digit's number slowest. Columns from 2^ncb on, and columns whose class-A part is >= M, belong to no cell. off = sum of the rows of the units before; **m0 = sum of all units' rows rounded up to a multiple of `D`** (W5:100-107). Rejections (names in 13.8): w < 1 or > 20; `D` other than 2048 or 32; L < 1 or > 4096; one of d, dh, dkv, dq, f < 1 or > 2^24 (and fe, NE if some layer has experts); V < 1 or > 2^24; a unit, a running sum or m0 above 2^22 rows; clog2(V) < 1 (asked as V < 2, `shape-V`) or > w (`hid-vocab-cols`) (W5:109-120).

### 4.4 From weight claims to one pending row (W5:124-174)

- A **weight claim** a names a unit, has one **factor** per index group and a value v_a (shown before as a scalar under a mask). Factor of class low/high: a list HV of o elements of E and a point pt of z coordinates; index `hi 2^z + lo` gets `HV[hi] eq(pt, lo)` (first coordinate of pt = highest bit of lo). Factor of class A: a list AV of M elements; index v gets AV[v]. The claim: sum over the unit's weights, each times the product of its indices' weights, = v_a. 1..4096 claims per segment.
- After the merge (x, rm, beta, fv'): `X_s = rm[lk-1-s]` = coordinate of column bit s. For claim a:
  `e_a = prod_{groups low/high} prod_{i<t} eq1(pt of the group's i-th taken bit, X_(cb0+i)) x prod_{groups A, t>0} sum_{v<M} AV[v] eq((X_(cb0+t-1),..,X_cb0), v) x prod_{s=ncb}^{lk-1} (1 - X_s)`;
  the i-th taken bit (from the lowest) is bit i of lo for class low and bit z - t + i for class high.
- Row weights Gamma over the rows of the matrix (0 outside the named units): claim a adds to Gamma[y], for every row y of its unit, `x^a e_a 256^q prod_g r_g(rho_g)`, with low/high: `r_g(rho) = HV[hi] eq(pl, lo')` where `rho = hi 2^(z-t) + lo'` and pl = the coordinates of pt for the bits not taken, highest first; class A with t = 0: `r_g(rho) = AV[rho]`; class A with t > 0: `r_g = 1`.
- **Pending row**: `sum_{y,c} Gamma[y] eq(psi, c) W[y][c] + beta c_mask = fv'`, psi = rm reversed (column bit 0 first; frame's eq), c_mask = the next entry of the request's index-mask message (segments with claims take them in the order of the segments). A request with NG groups of layers has NG + 1 pending rows (item `pending rows`, R14.3). Joined and tested by R14.4 (e), R14.9, R14.10 (§2.11).

### 4.5 Worked numbers (W5:178-193) — unit-test vectors

| | small (`target_small_f2/policy.txt`) | full (`target_full_f2/policy.txt`) |
|---|---|---|
| `L`, `d`, `dh`, `H`, `G` | 8, 512, 128, 4, 2 | 48, 5120, 128, 40, 8 |
| `f`, `fe`, `NE`, `V`, `D` | 1024, 512, 4, 512, 2048 | 16384, 8192, 128, 202048, 2048 |
| b, w of `table` | 8, 11 | 11, 18 |
| units | 66 | 386 |
| rows of the first three units (kinds 0, 1, 2) | 4096, 128, 256 | 320, 40, 200 |
| first row / rows of the embedding | 57,352 / 512 | 3,045,360 / 20,480 |
| first row / rows of the head | 57,864 / 256 | 3,065,840 / 10,240 |
| sum of the units' rows | 58,120 | 3,076,080 |
| m0 | 59,392 | 3,076,096 |

Small: every unit uses all 11 column bits. Full: the router's units (kind 11) use 17 of 18 column bits, every other unit all 18; V is not a power of two, so in kinds 12, 13 the columns whose token part is >= V belong to no weight.

Traps (W5:197-208): class high gives the highest of its z **low** bits, the odd part o always stays in the rows; three orders of column bits (rm highest first, psi lowest first, a class-A point from the group's highest bit down); the groups' cut (cb0, t) and the table's cut (k_lo) are unrelated; the first group is fastest in y; rows after the last unit belong to no unit and no claim reads them.

## 5. Complexity drivers

Formulas are exact where a line is cited, otherwise [INF] (my counting from the cited tables). "E-mult" = one multiplication in E.

| component | hashing / chain rounds | field work | dominated by |
|---|---|---|---|
| sumcheck with a hiding sum | NV + 1 (+1 for `PSC values`) rounds, one chain query each | per round: completing g (1 E-mult in an equality round, none in a plain one) + Horner (k E-mults); Left(): 1 + sk(NV) mask coefficients (M:596) | negligible alone |
| product level, m variables | m + 4 rounds; 2m + 5 scalars (M:111) | Theta(m) E-mults | — |
| lookup (v, dL) | scalars `187 + v^2 + 4v + dL^2 + 18 dL + 20` (M:777-778); rounds `[NC>1] + 96 + (v^2 + 7v)/2 + (dL^2 + 17 dL)/2 + 2 dL + 14` [INF] | Theta(v^2 + dL^2) E-mults for the rounds; **table MLE: 2^(k_c) E-mults + 2^(k_c) ExF mults per listed table** (65,536 rows each, M:317); plane weights: 2 x 2^lm (phiB) + 2 x NC 2^wd; a_pad: <= 32 squarings per distinct base (exponents < 2^v < 2^32) | listed tables; number of rounds |
| digits lookup (dL = 11, v_Z = n_Z + 1) | e.g. n_Z = 23: 1198 scalars, about 659 rounds [INF] | range tables: O(1) | number of rounds |
| smallness test | `RNG`: n = (sum k_mu) tau entries = ceil(n/32) words = ceil(n/128) 32-byte answer blocks (R6.7, R6.11); **tau = 128 -> one block per column** [INF] | colw: (sum k_mu) x tau signed E-additions of chi^u (no multiplication, Theta in {-1,0,1}) [INF]; column weights: O(mz) on `ZZ` (2 mz columns, up to 4 combined rows), 3 x 2^11 on `BZ`, k_mu per matrix, len(`U3`); distinctness of rw_mu: O(mp_mu) E-mults [INF from F:2508-2510] | `RNG` hashing + colw additions |
| merge | lkW + 4 rounds; 2 lkW + 3 scalars (M:205) | Gamma: one entry per matrix row of every named unit (units of up to 2^22 rows, W5:117), each a product of <= 3 group factors; e_a: O(lk + M) per claim | size of Gamma |
| segment hand-over (the one row) | — | terms scale x w(r) x L[col]: naive cost = number of array elements placed (e.g. `ZZ` alone: tau x 2 mz); with product-form row weights O(columns + touched table entries) [INF; "linear in a written-out stretch" T3:1230-1231] | `ZZ`, `M`mu sizes |
| `SEND` | 2 rounds; s (a + 1) sampled elements | sample row = product form over the cube; O(l) once folded | — |
| `BAT` + `FOLD` | 2 + k rounds | fold of the batched row: up to 2^k l multiply-adds if dense | l |
| switch (`LOC` / `CS`) | per tree of the old group: m distinct leaves, each ceil((8 W + salt)/128) BLAKE2b compressions (R2.6, F:186) + the walk's vertices; opening length `m (8 W + s) + 32 g` bytes (S10:450-460) | symbols: t x (2^k + 2 x 2^h) ExF/E mults; generator rows: t x ((1 + K)(l + r) + 2 (l_zk + r_zk)) coefficients if written out, or O(k + log l) each if kept as geometric/product forms until BASE [INF] | t x W hashing; t x l arithmetic |
| `BASE` | 2 rounds; reads l + l' + r + r' elements | B1: l + l' E-mults; B2: m x (l + r + l' + r') ExF mults (Horner at z_x) | l of the last stage |
| table test | stored-table opening: t columns of 2^v F-symbols each (T3:1742-1743) | (Col): t x (l_T + r_T) coefficients; (Fold): m 2^k_lo coefficients on G_u; (Dot): m + 2^k_col coefficients; pending-row join: k_col rounds | m (matrix rows, up to 2^22), 2^k_col |

Full-size counts given by the docs (F:2497-2512): tau = tauP = 128; 25 segments; columns in the matrices of a list: 24,086 (feed-forward), 10,248 (attention), 20,703 (head); **432,711 columns per proof** -> about 55.4 M ternary entries and 432,711 answer blocks for `RNG` alone [INF arithmetic]; every segment has a matrix of 2^16 cell rows (mp = 21,846); n of the last `BAT-sigma` is about 32 million in a feed-forward segment; a segment has fewer than 2^22 weights under test (about 3.4 million in a feed-forward segment) (F:2516-2520). Toy sizes for the frame: `product` full t = 73/74/74, l = 2^12, 2^11, 2^11; 221 and 224 rows batched (T1:54-57, 1564-1569).

Implementation remark for Bend (U32 only) [INF, not from the docs]: an F element is two U32 limbs, an E element six; one E-mult is 9 F-mults schoolbook plus two doublings (X^3 = 2); every count above multiplies by that constant, so the `RNG` additions, the listed-table MLEs and the t x l generator-row work are the terms to design around.

## 6. Rule index

**(a) No numbered rule (R-ID) is defined in 11, 11.1 or 11.5.** These parts cite rules defined elsewhere:

| rule | one-line statement | defined at | cited at |
|---|---|---|---|
| R1.4 | E = F[X]/(X^3 - c), c = 2 in field 2; an element is 24 bytes | F:105 | M:25 |
| R4.3 | the parameters' bytes; a plan entry has eleven words, the last = rows batched | F:287 | M:64 |
| R5.1–R5.4 | rounds of a chain; a query after every prover's message | F:441-466 | M:13, 40 |
| R6.2–R6.7 | sampling: elements, non-zero elements, positions, {-1,0,1} entries | F:503-534 | M:13-14, 58, 79, 227, 1149 |
| R8.3, R8.4 | answers open the next message; the hiding sum is the last item of its message | F:900, 917 | M:14, 39 |
| R12.12 | a message of a segment (six words: rows, field, mask rows, leaf class, moment, life) | S9:839 | M:20 |
| R13.16 | a sumcheck with a hiding sum, in general (g = k + 1, D = d_Y) | S9:289 | M:70-71 |
| R14.3 | the first chain's first query (items; `pending rows`) | S10:70 | W5:163 |
| R14.4 | the first chain's rounds; (a) index-mask message, (c) sub-proof rounds, (d) later moments, (e) after the last test | S10:191 | 11:5, 19; M:15, 19, 22, 206, 215, 228, 314, 1160; W5:11, 21, 169, 173 |
| R14.5 | the item `layout`: arrays and nine-word blocks | S10:131 | M:386, 463, 1357; W5:38 |
| R14.9, R14.10 | the shared chain; the second chain | S10:275, 308 | W5:173 |
| R14.11 | the names and kinds of all rounds | S10:465 | M:15 |
| R15.2, R15.3 | the parameter file's lines; the second hash function (table digests) | F:1198, 1211 | W5:10, 25; M:340 |
| R4.10, R7.4, R13.8 | a stored table's name, leaf digest, pads and record | F:385, 622; S9:323 | W5:7 |
| R13.14, R13.10 | the item `ranges`; the link's rounds | S9:471, 788 | W5:23, 222, 224 |

**(b) Named tests defined in 11.1 / 11.5** (the IDs a second verifier can reuse):

| name | a verifier rejects unless (or: event) | cite |
|---|---|---|
| `plan-mask-row` | ns + `answers` <= entries of a message of the request's mask code | M:306-310 |
| `shape-pt-words-NAME` | 5 <= k_c <= 16, t0_c < 2^(k_c), 0 <= n_c <= 62, a listed table has 2^(k_c) rows | M:762-764 |
| `forest-row-value-NAME` | every listed row's value < p | M:764-765 |
| `hid-call-floor` | n_c >= 10 | M:765 |
| `hid-planes-NAME` | 32 planes, no separately counted row (cannot fail in this format) | M:765-767 |
| `forest-calls` / `forest-depth` / `forest-trees` / `forest-keys` | 1 <= NC <= 16 / dT >= 10 / NT <= 256 (digits: n_Z - dT <= 7) / v < 32 (digits: v_Z < 32) | M:768-769, 1377-1378 |
| `no-wrap-pin-forest` | 2^(dL+32) < p | M:769 |
| `pt-pub-forest` / `forest-only-padding-NAME` | npad(y) <= 2^dT / per call sum of npad < 2^(n_c) | M:770-771 |
| `forest-planes` | 5 <= lm <= kT + 5 | M:772 |
| (unnamed in 11.1) | dT >= la in a feed-forward segment and in the head | M:185-186 |
| `hid-tau` / `policy-tau-hb` / `plan-tau` | tau multiple of 32 in 32..256 with tau1 = 0 or a power of two / tau >= `sec` / tau = the plan's derived number | M:1367-1369 |
| `plan-link` | NM < 256 and one matrix is the segment's own, read by no other | M:1370 |
| `shape-matrix-` / `hid-k-range` / `t2f-weight-class` / `t2f-columns-range` | m_mu >= 1 / 1 <= k_mu <= 8191 / no weight matrix in the list / 2 mz < 2^32 | M:1371-1374 |
| `shape-foreign-` / `plan-fold-source` | an earlier segment's matrix has that segment's m, k, first column / comes from an earlier feed-forward segment that lists it as read by others | M:1375-1376 |
| `shape-functional-` | len(f) >= 1, len(f) divides m_mat(f), phi_f has len(f) entries | M:1379 |
| `parameters-not-admitted` | hiding condition `range-checks` (16.1 condition 7) on the matrices' sizes | M:1384-1391 |
| table digests | the 32 lines `tsilu*`, `tsig*`, `trope*`, `texp*` are all present or all absent; present only if NE > 0; each digest equals the table's | M:340-344 |
| `shape-V` / `hid-vocab-cols` | V >= 2 / clog2(V) <= w | W5:118-120 |
| (names in 13.8) | w in 1..20; `D` in {2048, 32}; L in 1..4096; d, dh, dkv, dq, f (fe, NE) in 1..2^24; V <= 2^24; no unit, running sum or m0 above 2^22 rows; m0 2^k_lo entries fit a row's message | W5:30-31, 109-117 |
| `internal-f-table-read` | event: colw_mu(c) = 0 | M:1413 |
| `internal-t2f-untyped-`+array | event: a column weight of the one equation is 0 | M:1414-1420 |
| `internal-t2f-untiled` | event: chi^nJ e_0 or chi^nJ e_1 is 0, or eq(zk, .) = 0 at a real key | M:1421-1426 |
| `internal-sym-rowvec` / `internal-f-tie-weights` | event: two rw_mu(i') equal or one 0 / chi^(NCm+first_mu) cellw_mu(i) = 0 | M:1427-1430 |
| `internal-forest-padding-places`, `internal-claim-not-added-..`, `internal-f-matrix-order` | self-checks on public data only; no proof can cause them; a second verifier may assert them | M:919-928, 933-935, 1169-1171 |

**(c) Normative statements without an ID** that the spec will need to name [my labels]: "the order of the claims is part of the protocol" (M:50-51); "scalars do not close a round" (M:36-40); the pair table (M:451-455); pos(l,deg) (M:599-600); the three binding orders (M:115-118, 822-823); the three bit-order conversions (M:351-354); the claim/equation numbering of the smallness test (M:295-302, 1255-1262); `BZ` placement (M:1141-1144); the unit order and the digit position (W5:63-65, 86-98).

## 7. Language-neutral pseudocode (verifier's side)

Channel primitives (defined by FORMAT §4–§7, another note): `read_E()` reads 24 bytes and rejects a coordinate not below p; `round(name)` closes the current prover's message, checks the plan's entry (a mismatch is a program fault, not a rejection: T1:1010-1013), tests the nonce if the entry has proof of work, and returns a sampler with `E()` (R6.4), `E_nonzero()` (R6.5), `ternary(n)` (R6.7), `positions(t, k)` (R6.6).

```
-- per-segment state
seg.j = 0                         -- next scalar number
seg.shown[], seg.factor[]         -- one pair per number, set exactly once
Form = { const : E, hid : number -> E, arr : (array, rowweights, col) -> E }
hid(j) = the form with the single term hidden(j);  pub(f) = f.const + sum_j f.hid[j] * seg.shown[j]

read_scalar()  = (n := seg.j; seg.j += 1; (n, read_E()))
sent_alone()   = ((n, s) := read_scalar(); seg.shown[n] := s; seg.factor[n] := 1; n)          -- M:453

psc(pubC, rounds = [(EQ z | PLAIN, k)], dY, n):                                              -- M:580-591
    j0 := seg.j;  (_, hs) := read_scalar()                    -- hs is the last item of this message (R8.4)
    eps := round("PSC epsilon").E();   cur := hs + eps * pubC
    for (kind, k) in rounds:
        s := k x read_scalar                                   -- lowest degree first
        g := EQ z  -> [cur - z * sum(s)] ++ s                  -- constant omitted
             PLAIN -> [s[0], cur - 2*s[0] - sum(s[1..])] ++ s[1..]      -- linear omitted
        r := round("PSC round").E();   cur := horner(g, r);   gam.push(r)
    if n > 0:
        s := dY x read_scalar;  g := [cur] ++ s
        beta := round("PSC Y").E_nonzero();   cur := horner(g, beta);   gam.push(beta)
        jE := seg.j
        for i < n: (m, e) := read_scalar(); seg.shown[m] := e; seg.factor[m] := beta
        round("PSC values")                                    -- samples nothing
    for j in j0 .. j0 + sum(k) + dY: seg.shown[j] := 0; seg.factor[j] := -1
    return T = {j0, eps, gam, cur, jE, rounds, dY}

left(C, T, S0, K):                                                                           -- M:615-636
    NV := len(T.gam);  psi[l] := (round l is PLAIN ? T.gam[l] : 1)          -- Y counts as equality
    tail[NV-1] := 1;  tail[l] := tail[l+1] * psi[l+1];  PP := tail[0] * psi[0]
    f := 0
    for l < NV, deg in (l < NV-1 ? 1..k_l : 0..k_l):
        pos := (l < NV-1) ? sk(l) + deg - 1 : sk(NV-1) + deg
        f.hid[T.j0 + pos] += T.gam[l]^deg * tail[l]
    f += (T.eps * PP) * (pub(C) - C);   f += T.eps * K;   f.const += T.eps * S0 - T.cur
    return f                                                   -- the claim is f = 0

product_level(C, z[0..m-1], order[0..m-1]):                                                  -- M:660-675
    T := psc(pub(C), [(EQ z[m-1-order[l]], 2) for l < m], dY = 2, n = 2)
    r[m-1-order[l]] := T.gam[l]   for l < m
    xi := round("LINE").E()
    claim := left(C, T, seg.shown[T.jE] * seg.shown[T.jE+1], 0)
    return (claim, [xi] ++ r, (1 - xi) * hid(T.jE) + xi * hid(T.jE + 1))
default_order(m)      = [m-1, m-2, .., 0]
range_order(m)        = [2,1,0, 5,4,3, 8,7,6] ++ [m-1, .., 9]
last_key_order(v, rK) = [rK+2,rK+1,rK, rK+5,rK+4,rK+3, rK+8,rK+7,rK+6] ++ [v-2, .., rK+9] ++ [rK-1, .., 0]

lookup(calls, host):                                           -- size tests of §2.6 first      M:158-168, 789-917
    jLK := seg.j
    theta := NC > 1 ? round("LKP shift").E() : 0
    alpha := round("LKP").E()
    a_pad := (alpha - padkey(0))^((2^rK - NT) * 2^dT) * prod_{y<NT} (alpha - padkey(call(y)))^npad(y)
    T0 := psc(0, [], 3, 3);   jZ := T0.jE; jP[1] := jZ + 1; jG[0] := jZ + 2
    LK[0] := left(0, T0, shown[jZ] - a_pad * shown[jP[1]]^2 * shown[jG[0]], 0)
    for s = 1..30:
        C := hid(jP[s]);  Ts := psc(pub(C), [], 3, 2);  jP[s+1] := Ts.jE;  jG[s] := Ts.jE + 1
        LK[s] := left(C, Ts, shown[jP[s+1]]^2 * shown[jG[s]], 0)
    jG[31] := jP[31]
    zT := reverse(5 x round("JOIN").E());   CT := sum_{j<32} eq(zT, j) * hid(jG[j])
    zK := [];  CK := hid(jZ)
    for m = 0..v-1:   (LK[31+m], zK, CK) := product_level(CK, zK, m < v-1 ? default_order(m) : last_key_order(v, rK))
    zx := zK[0..dT-1];  zy := zK[dT..v-1];  C_end := CK
    for m = 5..4+dL:  (LK[26+v+m], zT, CT) := product_level(CT, zT, default_order(m))
    T7 := psc(pub(CT), [(EQ zT[l], l < dL ? 2 : 1) for l < 5+dL], 0, 0);   zb0 := T7.gam
    zq := reverse((5+dL) x round("ZERO").E())
    T9 := psc(0, [(EQ zq[l], 2) for l < 5+dL], 2, 1);   jBit := T9.jE;   zb1 := T9.gam[0..4+dL]
    LK[31+v+dL] := left(0, T9, shown[jBit]^2 - shown[jBit], 0)
    for each call c:  h := rK - iota_c;  e_c := eq(zy[0..h-1], tree0(c) >> iota_c);  zk_c := zy[h..rK-1] ++ zx
                      T_c := MLE of tab_c at the last k_c coordinates of zb0[0..kT-1]
    A_L := alpha - 1 - sum_{c<2^cK} eq(zb0[kT..kT+cK-1], c) * (T_{min(c,NC-1)} + min(c,NC-1) * theta)
    LP0 := left(CT, T7, 1, A_L * host.PL(zb0));   LP1 := hid(jBit) - host.PL(zb1);   LP2 := host.sum_TP() - (2^v - NPAD)
    LJ  := sum_c e_c * (alpha - c*theta - host.KF(c, zk_c)) + (alpha - padkey(0)) * sum_{y=NT}^{2^rK-1} eq(zy, y) - C_end
    -- the host adds LK[0..31+v+dL] as one run, (LP0, LP1, LP2) as one run, and LJ where its part says

merge(jV[0..NA-1]):                                                                          -- M:965-996
    x := round("BAT-sigma").E()                                -- n = NA, also if NA = 1
    C := sum_a x^a * hid(jV[a])
    T := psc(pub(C), [(PLAIN, 2) for l < lkW], 1, 1);   rm := T.gam[0..lkW-1];  beta := T.gam[lkW];  fv := seg.shown[T.jE]
    add_claim(left(C, T, fv, 0))
    c_mask := index_mask_ledger.take(1)                        -- one per segment with a merge, in segment order
    pending.push({ Gamma(x, X_s = rm[lkW-1-s]) by §4.4,  psi := reverse(rm),  masks := [(c_mask, beta)],  target := fv })

smallness(matrices, parts, n0):                                                              -- M:225-304, 1264-1277
    Theta := round("RNG").ternary((sum_mu k_mu) * tau)         -- Theta[mu][c][u] = entry (col0(mu) + c) * tau + u
    frame: SEND seed, SEND answer   (ZZ, BZ)
    Lk := lookup([R10z, R8d], host = digits)                   -- jLK = scalars sent before RNG
    claims n0.. : Lk.LK[0..42+v_Z], LJ, LP0, LP1, LP2, TIE_0..TIE_(NM-1), READ_0..READ_(NX-1)   (TIE/READ need chi)

settle(seg):                                                                                 -- M:312-314, 502-532, 1406-1433
    chi := round("BAT-sigma").E()                              -- n = NCm + Q
    pw[u] := chi^u;  rw_mu[i'] := chi^(tauP * i');  colw_mu[c] := sum_u pw[u] * Theta[mu][c][u];  spw := sum_u pw[u]
    (L, LS, c0) := sum of chi^i * claim_i (ordinary claims)  +  chi^(NCm + first_mu) * TIE_mu  +  chi^(NCm + first_NM + q*tauP) * READ_q
    if any event of §2.9 holds: REJECT
    MC[j] := -LS[j] * seg.factor[j];   TG := -(c0 + sum_j LS[j] * seg.shown[j])
    frame.add_row(group(seg), terms = [(array, w, L(A{w}))], mask_coefficients = MC[0..ns-1], target = TG)
```

Frame (lowest-bit-first conventions; T1, T2):

```
send(messages):                                                -- T1:274-323
    roots read;  seeds := round("SEND seed"): s x (a x E(), E_nonzero())        -- a = largest cube
    answers := for each message with s > 0, in order of sending, for i < s: read_E()      -- open the NEXT message
    for each (message, i): keep the sample row (u, v, pad coefficient beta_i or beta_i * X^t; target answer)
close(group):                                                  -- T2:456-514
    theta := round("BAT").E();   (c, K_i, d, tau) := sum_e theta^e * row_e   in the order: other rows | sample rows | generator rows
    sigma := read_E();  eps := round("FOLD epsilon").E();  claim := sigma + eps * tau
    for j = 1..k: (q0, q2) := 2 x read_E();  q1 := claim - 2*q0 - q2;  g_j := round("FOLD round").E();  claim := q0 + q1*g_j + q2*g_j^2
    keep c' := eps * fold(c; g);  K'_i := eps * prod_j (1 - g_j) * K_i;  d1 := eps * g_(h+1)..g_k * fold(d; g_1..g_h);  d2 := u(g);  tau' := claim
switch(old group, target G, batching?):                        -- T1:1271-1406; T2:516-584
    send([G, kept messages sent again, riders / next messages])    -- answers are the message of LOC / CS
    R := round(batching ? "CS" : "LOC")                        -- nonce tested before sampling
    draws := R.positions(t, log2 n);   theta := batching ? R.E() : none
    open every tree of the old group at sorted-distinct(draws) against its root;  one value per vertex (R7.14)
    for x in sorted-distinct(draws): y0(x), y1(x), y2(x), kept symbols      -- folds of the opened columns
    rows := [carried claim] ++ [old sample rows of kept members] ++ [per draw: main, kept.., old mask, fresh mask]
    batching ? batch rows ++ G's sample rows with theta^N (carried claim, sample rows, generator rows) : leave them open on the next group
proximity_test(group, stages):                                 -- T1:1496-1503
    BAT;  for i = 1..S-1: FOLD at stage i, then switch(batching) into stage i+1;  then base(c_last[j] := c_new[2j], d_last := d_new, tau)
base(c, d1, tau):                                              -- T1:960-1006
    tau_star := read_E();  lambda := round("BASE lambda").E()
    M0 := l x read_E();  M1 := l' x read_E();  R0 := r x read_E();  R1 := r' x read_E()
    if <c, M0> + <d1, M1> != tau_star + lambda * tau: REJECT                                  -- B1
    draws := round("BASE").positions(t, log2 n);  open the last stage's tree at sorted-distinct(draws)
    for x ascending: if Enc_C(M0, R0)(x) != gstar0(x) + lambda * y0(x) or Enc_Z(M1, R1)(x mod n_zk) != gstar1(x) + lambda * y1(x): REJECT   -- B2
table_test:                                                    -- §2.11
    first chain: if pending > 1: x := round("BAT-sigma").E(); ws := index_mask_ledger.take(1 + 2*k_col);
                 plain degree-2 sumcheck over k_col variables without Y -> (g', psi', masks', tau')
                 send([W]); round("SEND answer"); group OWN := {index-mask message, W}; add (Eval); round("SEAL")
    slot -> binding tree's root -> shared chain: LIN point; send([G_u]); (Rec_i); LOC; open the stored table; (Col_i);
                 send([Omega]); LIN zeta; (Fold); proximity test(s); SEAL
    second chain: adopt Omega; add (Dot) to OWN; proximity_test(OWN)
```

Order of checks that can reject, per chain: form of every element read (always) -> nonce of each round with proof of work, before its sampling -> each opening against its root, after its round -> B1 before BASE's positions -> B2 after BASE's opening -> no byte left at the chain's end. In a segment additionally: the two on-the-spot tests of 11.2/11.4 [OOS] and the zero-weight events right after chi (§2.9).

## 8. What can be unit-tested in isolation, and known answers in the docs

| # | unit | expected values available |
|---|---|---|
| 1 | code points | w = 0xE2AF70635744FD26 = 7^(5 (2^32 - 1)), order 2^32; z_0 = 7, z_1 = p - 7; z_(2m+1) = -z_(2m) (S9:182-187; T1:103-106) |
| 2 | eq in both bit orders; map value; reversal identity | definitional (M:395-403; T1:242-244) |
| 3 | sumcheck round completion (equality / plain / Y) and Left() | property test against an honest transcript built in the test; formulas M:96-100, 619-620; toy shape K + 1 variables, 2K + 5 scalars, rows (U), (E_1), (E_2) written out in T1:637-689 |
| 4 | scalar numbering | sumcheck: `1 + sum k + d_Y + n` (M:82); product level 2m + 5 (M:111); tie 187 (M:162); lookup total and the j0/jE table (M:777-787); merge 2 lkW + 3, jFv = j0 + 2 lkW + 2 (M:205, 977) |
| 5 | binding orders | default, range, last key level (M:115-118, 822-823) — permutation tests; the last key level needs dT >= 10 for its nine special bits to exist [INF] |
| 6 | lookup geometry | tree assignment (M:733-737), e_c / zk_c / T_c / A_L (M:845-853); digits lookup specialisation (M:1195-1205): e_0 = 1 - zy[0], e_1 = zy[0], T_0, T_1, A_L |
| 7 | planes placement | b/bA/bH: row (t mod 2^(lm-5)) 32 + j, column c 2^wd + floor(t / 2^(lm-5)) (M:859-861); `BZ`: X = (2t + c) 32 + j -> row floor(X / 2^11), column X mod 2^11 (M:1141-1144) |
| 8 | smallness numbering | claims 47 + v_Z + NM + NX (M:1266); nJ = n0 + 43 + v_Z (M:1081); first_mu, Q (M:1255-1258); packing constants and (f1), (f2) (M:1463-1475) |
| 9 | `RNG` decoding (R6.7) and colw | bit rule F:530-534; entry index (col0(mu) + c) tau + u (M:1149-1150) |
| 10 | FOLD's mask weights u(g) | k = 2, h = 0: (g_1 g_2, g_1^2 g_2, g_2, g_2^2, 1, 0, ..); k = h = 1: (1, g_1, 0, ..); k = 3, h = 1 at g = (2, 3, 5): **(15, 30, 45, 5, 25, 1, 0, ..)** (T1:898-899); mask-table known answer k = 3, h = 1, (a_1, b_1, a_2, b_2, w, a_3, b_3) = (1..7): row 0 = (3, 0, 4, 6, 7, 5, 0, ..), row 1 = (4, 2, 4, 6, 7, 5, 0, ..) (T1:850-852) |
| 11 | sample-row pads and switch offsets | `links` full: T, TK_0, T0, T1, OP, \|R\| = 64, 137, 210, 283, 356, 359 (groups 1, 2) and 64, 137, 210, 283 (group 3); tiny: 32, 35, 38, 41, 44, 47 and 32, 35, 38, 41 (T2:777-786); pad indices at s = 1: l_zk - 1, 2l - 1, l - 3..l - 1 (T2:361-363) |
| 12 | row counts of batchings | `CS`: 1 + s + 3t -> 221 (t = 73), 224 (t = 74), 11 (t = 3) (T1:54-61, 1582); `links`: 5, 9 + 4t, 9 + 4t, 2 + 3t -> 5, 301, 301, 221 and 5, 21, 21, 11 (T2:778-786) |
| 13 | weight placement (11.5) | the whole table of §4.5: 66 / 386 units, offsets, m0 = 59,392 / 3,076,096 (W5:178-193) |
| 14 | group layout and tree widths | `product`: trees of width 9, 18, 12 (T1:95-99; S9:283-287); `links` groups (T2:318-327) |

Whole-run known answers:
- `product` (chain label 1): full 30 rounds, 160,520 bytes, roots in rounds 1, 23, 27, positions 73 in [0, 2^15) (round 24), 74 in [0, 2^14) (round 28), 74 in [0, 2^14) (round 30), 20 proof-of-work bits; tiny 22 rounds, 7,648 bytes, roots in rounds 1, 15, 19, positions 3 / 3 / 5 in [0, 2^7) / [0, 2^8) / [0, 2^9), 6 proof-of-work bits (T1:54-61); stages (k, h) = (2,0), (1,1), (0,0); l_zk = 32 (n = 12) or 16 (n = 4); 16 or 8 sampled elements in the first seed (T1:430-434, 1561-1569).
- `links` (label 2): full 76 rounds, 249,456 bytes, C = (2^15, 4096, 73), Z = (2^15, 32, 73); tiny 58 rounds, 12,800 bytes, C = (2^9, 64, 3), Z = (2^9, 16, 3); seeds of 15, 14, 14, 14 (tiny 9, 8, 8, 8) elements; answers 2, 4, 4, 1 (T2:66-76, 777-786); the item `the chain of links` at full size is 57 words (T2:715-717).
- `key-and-entry`: key file 503,744 bytes (parts at bytes 0, 8, 40, 232, 161,768, 161,816, 408,912), 711 / 34 / 13 rounds; leaf file 131,432 bytes, 19 rounds (T3:116-150).
- Files in the repository (not built by us): `examples/protocol-toy-false-files/` holds `honest/product/tiny.{configuration,parameters}`, `honest/links/tiny-links.{configuration,parameters}`, an honest `key.file` (503,744 bytes) and `entry.file` (131,432 bytes), two honest toy-batch proofs, and false files with the expected rejection words in `LIST.tsv` (e.g. `false/product/tiny.cheat-PSC_FALSE_TARGET.proof`; "BASE: the masked message in the proof does not satisfy the linear claim"). **No honest `product` / `links` proof is stored**: those come from `blocks/toy/handover.cpp` via `tests/new/second/run_honest.sh`, which builds tools (T1:159-180) — out of bounds for this read-only copy.
- `docs/format/format-vectors.txt` = what `format_rules.py` prints: known answers for sections 2–6, one for section 7, and the encodings/rounds of sections 9, 10, 12 (RD:33-35) — nothing for the sub-proof machinery of 11.1.
- Reference second verifiers to read (pure Python, no program code): `tests/new/second/toy_check.py` (`product`), `links_check.py`, `proof_check.py` (toy batch; has the merge as `claims_leave`) (T1:182-189; T2:103-106; T3:255-262).

**There is no worked numeric example of a model sub-proof (lookup, smallness test, merge) in the docs in scope**: only formulas. End-to-end expected values for 11.1 must come from real proof files under `prover/examples/` configurations (another note) or from the Python `read_proof.py`, which walks a proof but (by FORMAT 17.3) does not check sub-proof content.

## 9. Open questions / ambiguities

1. **Floating-point tables.** Gate, sigmoid, rotary and attention-exponential tables are defined by double-precision computation, "not by integer arithmetic" (M:336-340). Bend has U32 only: take the four tables as data and pin them by the digests of R15.3, or emulate IEEE doubles (exp, pow, cos, sin to the bit)? The digest lines are admitted only when NE > 0 (M:341-343) — what pins the tables in a configuration with NE = 0 is "R15.3" per the doc; needs the §12.6 reader's confirmation.
2. **Which verdict at the zero-weight events** (§2.9): 13.9 says every verifier "gives no acceptance" and a two-answer verifier rejects (F:2458-2463). Decide whether the Bend verifier needs a third outcome (`NOT CHECKED`) or folds it into "rejected".
3. **Sub-proof lookups vs the library LKP.** 11.1 numbers all lookup scalars consecutively in the segment's one mask row (M:777-778), whereas the library takes the last key level's two inner masks from a second ledger (T3:1010-1011) and supports fewer live planes and several parts (T3:851-854, 981-989). [INF] none of that applies to segments; confirm against 11.2–11.4.
4. **Index-mask ledger order.** Merges take one entry each "in the order of the segments" (W5:169-170); the pending-row join then takes 1 + 2 k_col entries (T3:1279-1280; F:2583). [INF] so entries 0..NG go to the merges and NG + 1 .. NG + 1 + 2 k_col to the join, numbered by S9:109-116 — not stated in one place.
5. **Round order inside the join / the library twin.** In the proof's pending-row join the variables are bound "from the lowest up" (S9:124-125) and psi' = gamma directly; in a segment's merge round 0 binds the *highest* column bit and the frame reverses rm (M:204-205, 353-354). Both are stated, but they are opposite conventions on the same k_col variables — easy to cross.
6. **Exact interleaving of a segment's rounds** (moments 1 and 2, `RNG`, the two lookups, the segment's own sumchecks) is only partly fixed by 11.1 (M:233-234, 227-229); the rest is 11.2–11.4 and the plan.
7. **How the row weights are handed to the frame** when w is not a product over bits: "one term for each row r with w(r) not 0" (M:528-530). Which combined rows of 11.2–11.4 fall in that case, and the resulting term count, is not in scope here.
8. **Number of out-of-domain answers.** All formulas carry s, but the parameter-file parser refuses any `answers` but 1 (T3:2115) and no second verifier has read s > 1 (T1:534-535). [INF] the Bend verifier may fix s = 1; confirm in §8.
9. **Planner dependence.** Numbers of positions t, stages, codes and per-round proof-of-work bits come from the planning routines (`blocks/numbers/`), "not this part" (T1:1654); the verifier must reject parameters whose round errors miss the target (T1:153). The machinery pages do not say how much of the planner a second verifier must re-implement.
10. **Shapes never exercised by any second verifier**: h > 0 in a segment's group, a life above 1, several kept messages, kept rows over E (T2:824-828). The model's layout has one mask row per segment (S10:231-233), so h = 0 there; whether lives above 1 occur in real configurations (`plan-fold-source` suggests feed-forward matrices are read by later segments, M:1376) needs 11.2/11.3.
11. **`pub(C)` before commitment.** A start form may name arrays not yet committed (M:488-497); the doc says the ordering condition is met "from reading the code" and that "no test or self-check enforces it" — nothing for the verifier to check, but the spec should record the required order.
12. **Hiding sum as a plain scalar**: that hs is "written and hashed like any other scalar has not been read in the source" (T3:1606-1608); R8.4 only fixes its position (last item of a kind-2 round's message).
13. **11.1 is silent on the `internal-…-free-slot` test's exact rule**; 13.9 states it in one line (F:2475) and defers to the second halves of 11.2–11.4.
14. **Toy pages are explicitly unverified against the code word for word** ("No program ... has been written from this page's text word for word", T1:11; T2:7): where a toy formula and FORMAT 13.9 differ, 13.9 and §9–§11 decide (RD:7-9).
