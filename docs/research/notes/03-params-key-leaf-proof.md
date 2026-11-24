# 03 — Parameter file, derived quantities, key file, leaf file, proof file (FORMAT §8–§10)

> Status: superseded
> Recovered working notes, 2026-11-23. Upstream excerpts from FlashProve, Copyright 2026 Anthropic PBC, Apache-2.0.

The [protocol source map](../protocol.md#from-bytes-to-a-verdict) now covers parameter derivation and the key, leaf and request readers. The original calculations follow for reference.

Source: FlashProve 0.16.0-rc.26, commit 9e2bdd8, read-only. All paths are relative to the upstream root
`<scratchpad>/upstream/FlashProve`.

**Citation aliases** (`ALIAS:LINE`):

| alias | file |
|---|---|
| P8 | `docs/format/08-parameters.md` (925 lines, read completely) |
| P9 | `docs/format/09-key-and-leaf-files.md` (975 lines, read completely) |
| P10 | `docs/format/10-proof-file.md` (476 lines, read completely) |
| FMT | `docs/format/FORMAT.md` (only §4, §5–§7, §13.3–13.6 and the 13.8 rows on `KL.bin`/`layout.txt`) |
| VPF | `verifier/docs/parameter-file.md` (read completely) |
| VPD | `verifier/docs/plan-data.md` (read completely) |
| FR / RP | `docs/format/format_rules.py` / `docs/format/read_proof.py` (the format's own scripts; byte-level cross-check) |
| XS / XF | `examples/accepted-proof/` (small) / `examples/full-size/` (full size) |
| KA | `verifier/tests/known_answers/kit_rounds/` (stored output of the planning call, lines `round:`) |

**Markers.** `[C]` = computed by me from the cited formula (not printed upstream). `[I]` = my inference. `[KA]` = my
computation agrees exactly with the stored known answers in KA. Everything unmarked is stated by the cited lines.

**Precedence.** On bytes, hashed strings, order and tests, `FORMAT.md` with the files of its §8–§11 takes precedence
over every other page (`docs/format/README.md:7-9`). §8 has no rule numbers of its own: "cite it by subsection and
item" (P8:15-17). §9/§10 define names, order, lengths and what is sampled; they do *not* define the checks on the
content of the items (P9:37-41, P9:268-269) — those are FORMAT §13 (13.9), outside this note.

**Which example is which.** XS = kit `prover/examples/target_small_f2_roomy` (XS `README.md:67`); XF = kit
`prover/examples/target_full_f2` (XF `README.md:41`). `[C]` byte comparison: XS `config/` is identical to
`target_small_f2_roomy/`; it differs from `target_small_f2/` only in `MF` (43 vs 44, line 105) and in `KL.bin`;
the 32 frame lines are identical in all three, as P8:759-760 says. XF `config/` is identical to `target_full_f2/`, and
its first 32 lines are `blocks/frame/examples/record.f2.txt` (P8:753-755). So the two value columns of P8 §8.5
(`target_small_f2/policy.txt`, `record.f2.txt`) are exactly the small and the full-size example.

---

## 0. What decides the implementation (short)

1. **No file holds a length, count or offset.** A verifier derives the plan of every chain from the three public files
   and then takes planned items off one byte stream; only the length of an opening depends on sampled positions
   (FMT:860-865, R8.1 FMT:869-872).
2. **Two ways to get the plan** (P8:243-254): (a) rebuild §8.4 bit for bit — integer interval arithmetic with
   192-bit mantissas, square roots, fixed-point iterations; (b) take plan, codes and shapes as public inputs in their
   canonical bytes and check files against them; then every §8 condition becomes a hypothesis on those inputs.
   A derived number that is off by one changes every challenge from round 1 (P8:29-32, P8:904-910).
3. Seven chains, seven labels; each chain's first query holds version item, plan, `configuration`, further items
   (§4–§6 below). The shared chain has no random bytes: the binding tree's root replaces them (R13.6, R14.9).
4. Proof of work only in rounds that sample positions (`LOC`, `CS`, `BASE`, `LINK`): 20 / 28 / 32 bits for
   request / batch / committer scope in both examples (P8:340, XS `config/policy.txt:11`).
5. Full size has a stored-table code of length 2^32: positions fill a whole 32-bit word and the leaf index is
   2^32 + x (§9 below).

---

## 1. The parameter file (`<config folder>/policy.txt`)

### 1.1 File level

- Read whole as bytes; fewer than 2^32 bytes; its first line must be `version`, a blank, the program's version word,
  a line feed (FMT:1695). The programs read the file named `policy.txt` alone (`docs/format/README.md:41-42`).
- Two parts: the **frame lines** (first 32 lines, `version` … `table`, one strict parser shared by committer, prover,
  verifier) and the **model's lines** (from `prof` on), which the frame parser passes on unread (P8:36-38).
- Every byte of the file enters the configuration's digest (R4.9); two files that differ in one byte are two
  configurations with two commitment IDs "even if they mean the same" (P8:29-30, P8:47-48).

### 1.2 Grammar of the frame lines (P8 §8.1)

| rule | statement | cite |
|---|---|---|
| line | a name of one or two words, then its values, separated by **single** blanks (0x20), ended by **one** line feed (0x0A); the last line ends with a line feed too | P8:40-41 |
| value | decimal numeral of 1 to 15 digits, no sign, no leading zero; the numeral `0` is admitted. Exception: the value of `version` is four characters | P8:42-43 |
| nothing else | no blank line, no comment, no carriage return, no tab, nothing before the first line | P8:44-45 |
| order | fixed: the 32 lines in the order of §1.4, each exactly once | P8:46 |
| stop | the parser takes the lines one after the other and stops at the first test that fails | P8:50 |
| test order per line | tests 1–4 on every line, tests 5–6 on every line but `version`, in this order, before the line's own tests | P8:51-53 |
| message | `<name>[: <which line>] (line <number>)`, lines counted from 1; a stage prints `parameter file: ` + reason; the call ends `NO: <name> (policy)` (blank and parentheses are part of the name) | P8:53-58 |
| first line in whole calls | unless the file begins with `version `, four bytes and a line feed: `NO: version-unknown (policy)`, before the stages | P8:60-63 |

Parser tests, in the upstream numbering (there is **no test 40**; P8:105-106). Letters are those of §1.4.

| # | test | rejection | cite |
|---|---|---|---|
| 1 | the line ends with a line feed | `parameter-line-missing` | P8:67 |
| 2 | the line begins with the expected name and one blank | `parameter-line-order` | P8:68 |
| 3 | no value is empty: no two blanks in a row, no blank at the end of the line | `parameter-line-blanks` | P8:69 |
| 4 | the expected number of values; a line `stages` has one or more | `parameter-line-values` | P8:70 |
| 5 | a value has 1 to 15 characters, no leading zero unless it is the single digit `0` | `parameter-number-spelling` | P8:71 |
| 6 | every character of a value is a decimal digit | `parameter-number-spelling` | P8:72 |
| 7 | the value of `version` has exactly four bytes | `version-unknown` | P8:73 |
| 8 | the word is the one the build serves (`H821`) | `version-unknown` | P8:74 |
| 9 | `sec`: 1 <= B <= 256 | `parameter-range` | P8:75 |
| 10 | `reading`: 1 | `parameter-range` | P8:76 |
| 11 | `rowcost`: 1 | `parameter-range` | P8:77 |
| 12, 13 | `slots`: 1 <= N <= 2^20; N a power of two | `parameter-range` | P8:78-79 |
| 14 | `answers`: 1 | `parameter-range` | P8:80 |
| 15 | `record`: 1 | `parameter-range` | P8:81 |
| 16, 17 | `work ..`: each of the three values at most 58, and below B of `sec` | `parameter-range` | P8:82-83 |
| 18, 19 | `salt`: 40 <= Y <= 64; a multiple of 8 | `parameter-range` | P8:84-85 |
| 20 | `listed`: 0 | `parameter-range` | P8:86 |
| 21–25 | `group`: J = 1; n <= 32; l < n; nz <= n; lz < nz | `parameter-group-shape` | P8:87-91 |
| 26 | `stages`: number of values a multiple of four and at most 32 (1 to 8 later stages) | `parameter-stages-count` | P8:92 |
| 27–31 | `stages`: k <= 8; h <= k; n <= 32; nz <= n; last stage has k = 0 (so h = 0), every other stage k >= 1 | `parameter-stages-shape` | P8:93-97 |
| 32 | `ranges-part`: 1 <= L <= 40 | `parameter-range` | P8:98 |
| 33 | `own` has the n and l of `omega`; `once-own` those of `once-omega` | `parameter-own-code` | P8:99 |
| 34 | `folded` has the nz and lz of `omega`; `once-folded` those of `once-omega` | `parameter-one-mask-code` | P8:100 |
| 35–39 | `table`: b <= 20; n <= 32; i not 0; i + m < 2^n; e = 0 | `parameter-table-shape` | P8:101-105 |
| 41, 42 | `table`: w <= 40; w >= b | `parameter-table-shape` | P8:106-107 |

Order of application: tests 21–31 pair by pair (21–25 on `group`, 26 on `stages`, 27–31 stage by stage); tests 33 and
34 are made after `ranges-part` has been read, so their reason names line 31 (P8:109-112). Message detail: after the
colon comes the line's name in tests 1–4 and under `parameter-range`, the group's name alone (e.g. `link`) in tests
21–31; tests 5–8 and 33–42 have no colon and no name (P8:55-56).

### 1.3 The 32 frame lines, with both examples

Values: XS `config/policy.txt:1-32` and XF `config/policy.txt:1-32` (line number = row number). Meaning/range: P8:120-153.

| # | line | meaning | admitted by the parser | small (XS) | full (XF) |
|---|---|---|---|---|---|
| 1 | `version W` | `H`, format number 8, field digit, hash digit (R4.3) | the build's one word | `H821` | `H821` |
| 2 | `sec B` | target B: every round's error times 2^-w (w proof-of-work bits) is at most 2^-B | 1..256 | 128 | 128 |
| 3 | `reading R` | formula tying m to the slack: eta = sqrt(rho)/m | 1 | 1 | 1 |
| 4 | `rowcost C` | cost of combining rows of an interleaved word: nothing | 1 | 1 | 1 |
| 5 | `slots N` | largest number of requests in a batch = leaves of the binding tree (R7.18) | 1..2^20, power of two | 64 | 64 |
| 6 | `answers S` | answers to each out-of-domain sample | 1 | 1 | 1 |
| 7 | `record M` | every stored table has a record (R4.8) | 1 | 1 | 1 |
| 8 | `work field A B C` | PoW bits, error kind "non-zero polynomial vanishes at the challenge" | each <= 58 and < B | 0 0 0 | 0 0 0 |
| 9 | `work sample A B C` | … kind "two list members agree on an out-of-domain sample" | same | 0 0 0 | 0 0 0 |
| 10 | `work closeness A B C` | … kind "combination close although words not jointly close" | same | 0 0 0 | 0 0 0 |
| 11 | `work positions A B C` | … kind "far word agrees at all sampled positions" | same | 20 28 32 | 20 28 32 |
| 12 | `work smallness A B C` | … kind "not-small vector has small images" | same | 0 0 0 | 0 0 0 |
| 13 | `salt Y` | bytes of a leaf's salt, every tree alike; also plan word 3, table-shape word 6, `binding tree` word 2 | 40, 48, 56 or 64 | 40 | 40 |
| 14 | `listed P` | a file lists no sampled position (R8.2) | 0 | 0 | 0 |
| 15 | `group link J n l nz lz` | group of a segment of the request's first chain, and the message the last segment is closed into | tests 21–25 | 1 18 17 17 13 | 1 23 22 17 13 |
| 16 | `stages link k h n nz ..` | later stages of the last proximity test of the first chain | tests 26–31 | 4 3 17 17 · 3 3 16 16 · 3 3 15 15 · 0 0 15 15 | 4 3 22 17 · 3 3 19 16 · 3 3 16 15 · 4 4 13 13 · 0 0 15 15 |
| 17 | `group folded …` | group of the folded table, in a batch's shared chain | | 1 17 15 13 6 | 1 24 22 13 6 |
| 18 | `stages folded …` | its later stages | | 4 2 14 12 · 0 0 14 14 | 5 2 21 12 · 4 2 17 12 · 4 2 13 12 · 0 0 14 14 |
| 19 | `group omega …` | group of Omega, shared chain | | 1 18 14 13 6 | 1 22 18 13 6 |
| 20 | `stages omega …` | its later stages | | 4 3 14 13 · 0 0 15 15 | 4 3 18 14 · 4 3 14 13 · 0 0 15 15 |
| 21 | `group own …` | Omega again with the request's own vector W, second chain | | 1 18 14 13 8 | 1 22 18 13 8 |
| 22 | `stages own …` | its later stages | | 4 3 14 13 · 0 0 15 15 | 4 3 18 15 · 3 3 15 14 · 3 3 13 13 · 0 0 15 15 |
| 23 | `group once-folded …` | as `folded`, in a key file; also the two folded rows of a leaf file's link | | 1 17 15 13 6 | 1 24 22 13 6 |
| 24 | `stages once-folded …` | | | = line 18 | = line 18 |
| 25 | `group once-omega …` | as `omega`, in a key file | | 1 18 14 13 6 | 1 22 18 13 6 |
| 26 | `stages once-omega …` | | | = line 20 | = line 20 |
| 27 | `group once-own …` | as `own`, in a key file | | 1 18 14 13 8 | 1 22 18 13 8 |
| 28 | `stages once-own …` | | | = line 22 | = line 22 |
| 29 | `group once-ranges …` | group of the multiplicities of the key file's proof of ranges | | 1 22 18 16 10 | 1 22 18 16 12 |
| 30 | `stages once-ranges …` | its later stages | | 4 3 19 17 · 3 3 17 17 · 0 0 20 20 | same |
| 31 | `ranges-part L` | a part of a lookup of the proof of ranges reads 2^L rows of the committed matrix | 1..40 | 14 | 18 |
| 32 | `table b n i m e w` | the stored table (below) | tests 35–42 | 8 23 524288 65535 0 11 | 11 32 402653184 44040191 0 18 |

(The `·` separators are mine; in the file the numbers are separated by single blanks.)

- `work ..` columns: **A = a request's own rounds, B = a batch's shared rounds, C = the committer's rounds** — not the
  order of the files (P8:155-156, P8:918-920).
- `group J n l nz lz`: J a constant; base code of length 2^n with messages of 2^l entries; mask code of length 2^nz
  with messages of 2^lz entries (P8:156-158).
- Stage quadruple `k h n nz`: the folded row of the stage before is cut into 2^k main rows; 2^h mask rows; base code
  length 2^n; mask code length 2^nz (P8:171-176). Message lengths of later stages and all numbers of random entries
  have no line (P8:178).
- `table b n i m e w` (P8:160-169): 2^b rows; code length 2^n; i entries of a row's message, the last 3·S of them the
  record's pads (R13.8); m random entries of a row (the only number of random entries with a line); e = 0 constant;
  w = number of coordinates of the point a batch shares, the b that fold the rows among them (b <= w <= 40).

### 1.4 What `cp_verify` asks beyond the parser (P8 §8.3)

| asked | if not | cite |
|---|---|---|
| i and m of `table` below 2^32 | `parameter-table-shape (policy)` | P8:201 |
| each of the fifteen `work ..` values at most 32 | `policy-work-most` | P8:202 |
| `slots` at most 256 | `policy-leafd` | P8:203 |
| w of `table` is 1 to 20 | `w-shape-lk` | P8:204 |
| committed matrix (11.5) has at most 2^22 rows | `w-shape-mW` | P8:205 |
| ceil_log2(V) <= w (V the model's line `V`) | `hid-vocab-cols` | P8:206 |
| `sec` <= model's line `tau` | `policy-tau-hb` | P8:207 |
| `tau` = B − A of `work smallness` (so `tau` = `sec`, A = 0); `tau` in {32, 64, 96, 128, 160, 192, 256} (`hid-tau`) | `plan-tau` | P8:208 |
| all that §8.4 derives exists and items 22, 23 hold | `parameters-not-admitted` (+ a line `parameters-not-admitted: ..` naming the group or round) | P8:209 |
| every round of the file's plan meets `sec` (PoW counted) and `sec` >= requested bits (`-bits`, default 128) | `security-bits` | P8:210 |
| `group folded` ≠ `group omega` in n or l (same for `once-`) | no rejection; condition `two-codes` missed → at best `NOT-A-VERIFICATION` | P8:211 |
| no round needs its PoW | no rejection; only matters under `-no-proof-of-work` | P8:212 |

None of these tests reads a byte of a key/leaf/proof file; all but `security-bits` come before a stage opens one of
those files (P8:214-216). `cp_verify` copies B of `sec` and w, b, n, m of `table`, in this order, into the item
`request` (R15.5 words 172–176) (P8:219-220).

### 1.5 Grammar of the model's lines (P8 §8.6; scan `polScan`, VPF:41)

- A **value line** is a name, one blank, a decimal numeral below 2^32 without sign or leading zero; a 64-bit value
  takes two lines `<name>_lo`, `<name>_hi`; every line ends with one line feed and has at most 1,023 bytes, line feed
  counted; an optional line is left out when its value would be the default (one encoding) (P8:864-869).
- Order (FMT:1716-1721, P8:871-883): `prof` … `F`; then optional lines, each at most once, in the order `lidb`,
  `nminH` (only directly after `lidb`), `eg`, `smax`, `rcl`, `gcl`, `xl`; then the 32 digest lines (all or none);
  then all `call`, all `callA`, all `callH` lines.
- A **call line**: the word, the call's name (at most 8 characters), the kind of its table, one or more segment names,
  single blanks; items consist of letters, digits, `.`, `_`, `-` (P8:883, VPF:44). Within a kind the order of call
  lines is free but counts: `iota_<i>` belongs to the i-th `call` line, `iotaH_<i>` to the i-th `callH` line (VPF:46).
- Read by name before the scan: `prof` must be 16..31 and `toksrc` must be 1, else `NO: statement-required`; `lt`
  is the third (P8:885-886). A whole call also reads `C`, `theta`, `cap`, `s`, `sh`, `sT`, `lt` before the stages and
  can end `NO: policy` (e.g. `sT` not `sh` − 4) (P8:886-890).
- Scan test order on a line from `prof` to `F`: more than 19 digits in a row; a name and a value below 2^32; the name
  that is due; the spelling (VPF:61). Rejection names: `policy-line-form`, `policy-line-long`, `policy-zero-byte`,
  `policy-line-<i>`, `policy-name-<name>`, `policy-length`, `policy-cert-words`, `policy-call-line` (VPF:48-59).
- P8 does not specify ranges of the model's lines (P8:894-900); the ranges below are from VPF.

### 1.6 The model's lines, with both examples

Line numbers are those of XS `config/policy.txt`; XF has the same names at the same numbers up to line 130 and one
extra line (`nminH`, XF line 131), so XF has 184 lines / 2,629 bytes and XS 183 lines / 2,479 bytes `[C]`.

| XS line | name(s) | meaning (VPF) | allowed (VPF) | small | full | cite |
|---|---|---|---|---|---|---|
| 33 | `prof` | 16 + profile 4 | 20 | 20 | 20 | VPF:96 |
| 34 | `lt` | log2 of T, tokens in a request's window | 4..16 | 6 | 10 | VPF:102 |
| 35 | `L` | number of layers | multiple of 2^ll; at most 28 blocks | 8 | 48 | VPF:103 |
| 36 | `ll` | log2 of layers per block of layers | 1..6 | 2 | 2 | VPF:104 |
| 37 | `d` | width of the residual stream | 1..2^20 | 512 | 5120 | VPF:105 |
| 38–40 | `H`, `G`, `dh` | query heads; key/value heads; head dimension (H·dh = d) | H+G <= 64; dh power of two >= 2; G power of two dividing H | 4, 2, 128 | 40, 8, 128 | VPF:106 |
| 41–42 | `f`, `fe` | FFN hidden width; one expert's (f = 2·fe with experts) | f 1..2^20 | 1024, 512 | 16384, 8192 | VPF:107 |
| 43 | `NE` | routed experts | 0 or power of two 2..4096 | 4 | 128 | VPF:108 |
| 44 | `V` | vocabulary size | 2..2^20 (see VPF) | 512 | 202048 | VPF:109 |
| 45–48 | `eps1_lo/hi`, `eps2_lo/hi` | constants added in the two norms | 1..2^59−1 (< 2^48 with `xl 5`) | 1/0, 1/0 | 53687/0, 53687/0 | VPF:119 |
| 49 | `cs` | rotary table scale 2^cs | 12 | 12 | 12 | VPF:120 |
| 50–51 | `theta0_lo/hi` | rotary base | not 0 | 10000/0 | 500000/0 | VPF:121 |
| 52–58 | `hq hv ho hgD huD hdD hr` | digit form of seven classes of matrix products | 0, 1 or 2 | 2 1 1 1 1 1 1 | 2 1 1 1 1 1 1 | VPF:122 |
| 59 | `ut` | up-projection output range-checked to 16 bits | 1 | 1 | 1 | VPF:123 |
| 60 | `la` | features evaluated in runs of 2^(la−lt) | lt+1..16 | 8 | 16 | VPF:133 |
| 61 | `nmin` | padding floor of a lookup call (2^nmin keys) | 10..28 | 20 | 20 | VPF:134 |
| 62 | `D` | committed weight matrix rows rounded up to a multiple of D | 2048 (32 for toys) | 2048 | 2048 | VPF:135 |
| 63 | `tau` | random combinations of the smallness test | 32..256 list; = `sec` | 128 | 128 | VPF:136 |
| 64–71 | `lmaf NAf lmad NAd lmar lmb lmq lmx` | log2 rows / parts of the layer sub-proof's matrices | VPF:137-142 | 13 3 12 1 12 13 13 13 | 16 3 15 1 13 16 16 16 | VPF:137-142 |
| 72–83 | `wb_qk wb_v wb_o wb_g wb_u wb_gs wb_us wb_gr wb_ur wb_dn wb_dnr wb_r` | declared bit width of a weight, by kind | 13 (0 if kind absent) | all 13 | all 13 | VPF:148 |
| 84–91 | `iota_0` … `iota_7` | i-th `call` line's lookup has 2^iota_i trees | derived (n − dT); 0 if no such line | 0 0 0 1 0 0 0 0 | 1 1 1 2 1 1 0 0 | VPF:156 |
| 92–93 | `seed_lo`, `seed_hi` | public number; no check reads it | none | 31, 0 | 1, 0 | VPF:157 |
| 94–96 | `lB`, `S`, `rx` | tile side log2; largest softmax weight 2^S; table step | 0..lt−2; 1..14; 1..12 | 4, 12, 8 | 6, 12, 8 | VPF:176-178 |
| 97–98 | `kFM`, `kFD` | (not read by cp_verify); log2 rows of the softmax lookup table | —; 8..16 | 15, 16 | 15, 16 | VPF:179-180 |
| 99–103 | `lmS NAs lmh lmo lmbA` | attention matrices | VPF:181-184 | 11 1 12 13 13 | 16 1 13 16 14 | VPF:181-184 |
| 104 | `iotaA_0` | 32 + dT of the attention forest | derived | 52 | 57 | VPF:185 |
| 105–106 | `MF`, `KF` | final norm multiplier scale / shift | MF 24..47, <= KF+14; KF 17..32 | 43, 30 | 44, 30 | VPF:193 |
| 107–108 | `epsF_lo/hi` | final norm constant | as eps1 | 1/0 | 53687/0 | VPF:194 |
| 109 | `toksrc` | input is the embedding of the request's tokens | 1 | 1 | 1 | VPF:195 |
| 110–114 | `lmhf NHf lmhd lmhr lmbH` | output-head matrices | VPF:196-198 | 14 1 12 12 13 | 16 4 14 13 15 | VPF:196-198 |
| 115–116 | `wb_emb`, `wb_head` | declared width of embedding entry / output matrix | 21; 13 | 21, 13 | 21, 13 | VPF:199-200 |
| 117–122 | `iotaH_0` … `iotaH_5` | as `iota_<i>` for `callH` | derived | all 0 | 1 1 1 0 0 0 | VPF:201 |
| 123–125 | `C`, `theta`, `cap` | acceptance policy: clip, bound on the mean, most positions above the clip | theta <= C; cap <= T, < 2^16 | 256, 256, 0 | 256, 256, 0 | VPF:218 |
| 126 | `s` | logit scale 2^s (provider's statement) | <= 63 | 16 | 15 | VPF:219 |
| 127–129 | `sh`, `sT`, `F` | gap offset 2^sh; nll scale; table scale 2^F | 7 or 8; sh−4 or sh+4..sh+10; 24 | 8, 4, 24 | 8, 4, 24 | VPF:220-222 |
| 130 | `lidb` (optional) | log2 of the most keys in one tree of a request's lookups | 23..30; absent = 22 | 24 | 28 | VPF:232 |
| — / XF 131 | `nminH` (optional, only directly after `lidb`) | replaces `nmin` in the output head | > nmin, 2..28 | absent | 27 | VPF:233 |
| 131–133 | `rcl`, `gcl`, `xl` (optional) | router clamp; gate clamp; five limbs of the residual stream | 1; 1; 5 (absent = 4) | 1, 1, 5 | 1, 1, 5 | VPF:235-236 |
| 134–165 | `tsilu0..7`, `tsig0..7`, `trope0..7`, `texp0..7` | digests of the four public tables, one 32-bit word a line | all 32 or none | present | present (`trope*` differ from XS; the other 24 are equal) | VPF:237; P8:882 |
| 166–173 | 8 × `call <name> <kind> <segments>` | lookup calls of a layer sub-proof | 1..8 lines | identical in XS and XF | | VPF:243 |
| 174–177 | 4 × `callA …` | attention lookup calls | 1..12 lines | identical | | VPF:244 |
| 178–183 | 6 × `callH …` | output-head lookup calls | at most 6 | identical | | VPF:245 |

Literal call lines (both files): `call R16a R16 G U` · `call R16b R16 N1 N1H N2 N2H O D V` ·
`call R16c R16 QK QKH XR LR LT DD` · `call R8 R8 GH UH OH DH VH ROW LH SEL L3 G0` · `call FC FC CN1 CN2 CQK CV CLR` ·
`call FS FS MR CG` · `call FL FL F` · `call R16d R16 UT` · `callA KR KR RM RD` · `callA KFD KFD FM FD` ·
`callA R16 R16 WL IX` · `callA WH WH WH` · `callH R16a R16 NF NFH HD0` · `callH R16b R16 HD1` ·
`callH R8 R8 ROW HD2` · `callH FEa FE HE0` · `callH FEb FE HE1` · `callH FC FC CNF` (XS `config/policy.txt:166-183`).
Table kinds: `R16`, `R8`, `FC`, `FL`, `FS`, `FE`, `KR`, `KFD`, `WH` (VPF:249-255).

---

## 2. Derived quantities

### 2.1 Notation and constants (P8 §8.4 head, items 2–4)

- ceil_log2(v) = least a with 2^a >= v (0 for v = 0 and v = 1); up(v) = 2^ceil_log2(v), so up(0) = 1 in §8
  (R12.16 writes up(0) = 0); "div" rounds down; B, N, S = values of `sec`, `slots`, `answers`; w_T, m_T = w and m of
  `table` (P8:269-271).
- Field 2: p = 2^64 − 2^32 + 1; E has p^3 elements; element of F 8 bytes, of E 24, digest 32, nonce in a file 8; a
  sumcheck's message leaves out the coefficient the check fixes; an element of F is sampled in at most 6 attempts,
  a non-zero element of E in at most 2 (P8:321-327).
- A code is (a, ell, r): length 2^a, ell message entries, r random entries (the **tail**). Field 2: dimension
  ell + r; **kappa = ell + r − 1**; rate rho = kappa / 2^a; minimum distance d = len − kappa; tail(t) = t. Admitted
  only if 1 <= a <= 60, ell >= 1, ell <= len, r <= len, dimension <= len and (field 2) dimension <= 2^min(a, 32)
  (P8:347-355; also R12.1, P9:153-158).
- In field 2 the tail comes first in the polynomial: symbol at z = sum_{j<r} t_j z^j + z^r · sum_{j<ell} m_j z^j, on
  the coset 7·H in bit-reversed order (R12.11, P9:182-191; P8:921-923).

### 2.2 Model shape and frame counts

| quantity | formula | small | full | cite |
|---|---|---|---|---|
| window T | 2^lt | 64 | 1024 | VPF:102 |
| request file length | 4·(T + 2) bytes | 264 (on disk) | 4104 (on disk) | FMT:1699; P10:109-110 |
| layers L; groups of layers NG | NG = L / 2^ll | 8; 2 | 48; 12 | FMT:1735 |
| segments of a request | G_0, A_0, …, G_{NG−1}, A_{NG−1}, H: 2·NG + 1 | 5 | 25 | FMT:1735-1737; P10:187-189 |
| `links' identifiers` | 1 + g for G_g, 2 + NG + g for A_g, 1 + NG for H; listed in segment order | 1, 4, 2, 5, 3 `[C]` | 1, 14, 2, 15, …, 12, 25, 13 `[C]` | FMT:1737-1739 |
| `pending rows` | NG + 1 (G_g and H leave a row on the table, A_g none) | 3 | 13 | FMT:1742-1743; P8:846-848 |
| moments per segment | 3 in a model's proof | 3 | 3 | P10:187; FMT:1744-1750 |
| heads / widths / vocabulary | lines `H G dh d f fe NE V` | 4 / 2 / 128 / 512 / 1024 / 512 / 4 / 512 | 40 / 8 / 128 / 5120 / 16384 / 8192 / 128 / 202048 | §1.6 |
| binding tree depth | ceil_log2(N) | 6 | 6 | P8:735; P8:839 |
| slot in a proof file | 8 + salt + 32·depth bytes | 240 | 240 | FMT:1055-1060 |
| smallness combinations T (not the window) | B − w(`work smallness`) per scope | 128, 128, 128 | 128, 128, 128 | P8:679; P8:838 |
| B − `work positions` (request, batch, committer) | bits a list of positions must give | 108, 100, 96 | 108, 100, 96 | P8:828 |

### 2.3 The stored table and the committed matrix

| quantity | formula | small | full | cite |
|---|---|---|---|---|
| table code (a, ell, r) | (n, i, m_T) of `table` | (23, 524288, 65535) | (32, 402653184, 44040191) | P8:599 |
| rows of the table | 2^b; v = b | 256 (v = 8) | 2048 (v = 11) | P8:164; R4.10 FMT:385-391 |
| kappa; rate rho | i + m_T − 1; kappa / 2^n | 589822; 0.070312 | 446693374; 0.104004 | P8:829 |
| k_col (column variables of the matrix) | w_T; matrix has 2^k_col columns | 11 | 18 | P8:738; P9:466-467 |
| k_lo | w_T − b (<= 30) | 3 | 7 | P8:738 |
| matrix rows m0 | from the model's lines by 11.5 (not i / 2^(w_T−b)) | 59,392 | 3,076,096 | P8:846-848; P8:636 |
| plain entries of a row's message | i − 3·S; must be >= m0 · 2^k_lo | 524,285 >= 475,136 `[C]` | 402,653,181 >= 393,740,288 `[C]` | R13.8 P9:325-326; P9:467-468 |
| pads | last 3·S entries of a row's message; pad of answer i, coordinate t at position l − 3s + 3i + t | 3 | 3 | R13.8 P9:325-327; P8:840 |
| c (coordinates of the record's point) | least c with 2^c >= i | 19 | 29 | R4.10 FMT:395-396; P8:841 |
| record's seeds | S·(c + 1) elements of E, S of them not 0 | 20 | 30 | R13.15 P9:407-409; P8:841 |
| record (stored answers) | S·2^b elements of E | 256 el. = 6,144 bytes | 2,048 el. = 49,152 bytes | P8:680; P8:841 |
| error of entry `RECORD` | se(list at the one-time distance, ceil_log2(i)) | 2^-175.09 | 2^-178.74 | P8:680; P8:841 |
| one-time distance; source; list size | item 16 | 0.731602; Johnson; 114 | 0.664066; Johnson; 26 | P8:830 |
| m_once, m_later | item 16 search | 82, 82 | 24, 24 | P8:831 |
| later agreement | sqrt(rho)·(1 + 1/m_later) | 0.268398 | 0.335934 | P8:832 |
| columns a batch opens (`LOC`, shared chain of a proof) | positions(later agreement), batch scope | 53 | 64 | P8:615-616; P8:833 |
| columns of the key file's one-time test (`LOC`) | positions(one-time agreement), committer scope | 51 | 62 | P8:616-617; P8:834 |
| columns of a leaf file's link (`LINK`): nu_0 anchor, nu_j leaf table | positions(later agr.) and positions(one-time agr.), both committer scope | 51, 51 | 62, 62 | P8:617-620; P8:835 |
| limit of a leaf table, in batches | (cov − one-time columns) div (batch columns), cov = m_T; no verifier tests it | 1235 | 688127 | P8:624-627; P8:836 |
| entries (of a folded row's vector) | i rounded up to a multiple of up(m_T), plus m_T | 589,823 `[C]` | 446,693,375 `[C]` | P8:630-631 |
| main rows R of the folded row | ceil((entries + S) / 2^l_folded) | 18 | 107 | P8:635; P8:837 |
| main rows of Omega | ceil((m0 + S) / 2^l_omega) | 4 `[C]` | 12 `[C]` | P8:636 |
| main rows of W; W's mask row | ceil(2^w_T / 2^l_omega); one mask row if its rows leave fewer than S free cells | 1; none `[C]` | 1; one `[C]` | P8:637 |
| shared split's mask message | one mask row | 1 | 1 | P8:638 |
| index-mask message rows Q (proof) | least Q <= 4096 with Q·(2^lz_own − S) + Q − 1 >= pending + (1 + 2·w_T if pending > 1) | 26 entries → 1 `[C]` | 50 entries → 1 `[C]` | P8:639 |
| index-mask message rows Q (key file) | same with 2 per lookup part + (1 + 2·w_T if more than one part) | 39 entries → 1 `[C]` | 85 entries → 1 `[C]` | P8:639; P9:580-584 |
| `LIN point` elements | v + k_lo = k_col | 11 | 18 | P9:706 |
| `LIN zeta` elements | ceil_log2(m0) | 16 `[C]` | 22 `[C]` | P9:710 |
| `LINK point` / `LINK phi` elements | v / c | 8 / 19 | 11 / 29 | P9:793-797; P9:809-811 |

### 2.4 The derivation routine (P8 §8.4), item by item

One routine does this for committer, prover and verifier (P8:232-233). No line gives a number of positions, a number
of random entries (except m of `table`), the message length of a later stage, or a distance (P8:230-232).

1. **Arithmetic** (P8:276-320). Integers exact and of any size. A **Real** is u·2^e, u >= 0. `cut(x, dir)`: if u has
   more than 192 bits drop the excess s low bits, add s to e, add 1 to u if dir is up and a dropped bit was 1 (not cut
   again: u can have 193 bits). `add`, `sub` (a >= b), `mul` = exact then cut. `div(a, b, dir)`: s = 192 + 2 +
   bits(u_b); q = (u_a·2^s) div u_b, +1 if up and remainder != 0; exponent e_a − s − e_b; cut. `sqrt(a, dir)`:
   s = 2·192 + 4, +1 if e_a − s is odd; r = isqrt(u_a·2^s), +1 if up and not exact; exponent (e_a − s)/2; cut.
   `pow(a, n, dir)`: square-and-multiply from the lowest bit. A **Bound** is (lo, hi, bad): `+` and `*` endwise,
   `a − b` bad unless b.hi < a.lo, `a / b` bad if b.lo = 0; `ratio(x, y)` = Bound(x)/Bound(y). Decisions at the safe
   end: an error is compared at its hi; a bad error counts as 1. Formulas are evaluated exactly in the written order
   (power, then product/quotient, then sum/difference; left to right); a regrouped formula can give another integer.
2. **Constants** — §2.1 above (P8:321-327).
3. **Error kinds, scopes, proof-of-work bits** (P8:328-346). A round's PoW bits (2nd word of its entry) = value of
   `work <kind>` in the column of the chain's scope. Request scope (A): a proof's first and second chains. Batch scope
   (B): a proof's shared chain. Committer scope (C): all chains of a key file and of a leaf file.

   | line | rounds |
   |---|---|
   | `work field` | `BAT`, `BAT-sigma`, `PSC epsilon`, `PSC round`, `PSC Y`, `ZERO`, `LINE`, `LKP shift`, `JOIN`, `LKP`, `FOLD epsilon`, `LIN zeta`, `LINK phi` |
   | `work sample` | `SEND seed` |
   | `work closeness` | `FOLD round`, `BASE lambda`, `LINK point`, `LIN point` |
   | `work positions` | `LOC`, `CS`, `BASE`, `LINK` |
   | `work smallness` | `RNG` |
   | none (0 bits) | `SEAL`, `SEND answer`, `SPLIT`, `PSC values`, `LAST`, `REPLY`, and the entry `RECORD` |

   A plan is rejected if a round's bits are not below B or are above 58; a round with PoW bits has an 8-byte nonce in
   its file (P8:344-346).
4. **Code** — §2.1. A code of length 2^a' *repeated* to 2^a reads as len = 2^a, kappa = kappa_own·2^(a − a')
   (P8:355-357).
5. **Groups and stages** (P8:358-368). A group = 2^k main rows under one base code + 2^h mask rows under one mask
   code, all read at one list of positions (a mask row at the position modulo its length, R7.2), one joint distance.
   Side count c > 1: every main row stands for c rows folded side by side. The mask code **governs** the distance if
   kappa_mask·len_base > kappa_base·len_mask. Faulty group: mask code longer than base code, h > k, or k > 0, h = 0
   and the mask code governs.
6. **Distance rule** (P8:369-372). Agreement alpha = 1 − delta; for an integer m >= 3 on the governing code (mask
   code repeated to the base length if it governs): root = sqrt(rho); eta = root / m; alpha = root + eta.
   (P8:374-469 is on what the bounds rest; no acceptance condition reads it.)
7. **A code at an agreement** (P8:470-485). Bad if kappa >= len. far = floor(hi of delta·len). If
   3·far < len − kappa: count = far + 1, list size 1, source "third". Else source "Johnson": root = sqrt(rho);
   eta = alpha − root; q = root / eta; m = max(ceil(hi of q), 3) (bad if it does not fit 64 bits);
   Mh = ratio(2m + 1, 2);
   `count(m, delta) = (2·Mh^5 + 3·Mh·delta·rho) / (3·rho·root) · len + Mh / root`;
   `list(alpha) = floor(hi of (alpha − rho) / (alpha·alpha − rho))`; list size 1 if surely 2·delta·len < len − kappa.
   For a distance made from m by item 6: count(m, delta), list(alpha), source "Johnson" at every distance.
   Note the **ceiling at the upper end** (m is the ceiling of the hi of q): it decides four cells of §2.5 (P8:911-916).
8. **A group at its distance** (P8:486-497): base code by item 7 at alpha; mask code read as repeated, by item 7 at
   the same alpha, and where its source is not "third" its list size is added to its count; group list size = larger
   of the two list sizes.
9. **Errors used by sizing** (P8:498-518): fe(g) = ratio(g, |E|); pe(rows) = ratio(rows − 1, |E|) (0 for rows = 0);
   se(lambda, cube) = (lambda·lambda)/2 · x^S with x = fe(cube) if cube >= 2 else ratio(1, |E| − 1);
   mca(code, rows) = count / |E|;
   `fold(j) = mca(base, 2^(k−j)·c) + list·fe(2) [+ 2·mca(mask, 2^(h−j)) if mask code and j <= h]`;
   `last = mca(base, c) + list·fe(1) [+ mca(mask, 1) if mask code]`.
10. **A group holds** under a load (cube, messages, rows) if not bad and: fold(1) (or last if k = 0) <=
    goal(`closeness`); messages·se(list, cube) <= goal(`sample`); list·(pe(rows) + fe(1)) <= goal(`field`), with
    goal(kind, scope) = 2^(w − B). cube(g) = k + ceil_log2(ell) without a mask code, else
    max(k + ceil_log2(ell), h + ceil_log2(ell_mask)) + 1 (P8:545-550).
11. **The integer m**: first good integer in 3..66 (none → m = 0, group bad); then doubling while high < 2^40 and
    good(high); cap 2^40; then bisection; m = low (P8:551-555).
12. **Number of positions**: pos(alpha, bits, extra) = least t with alpha^t + extra <= 2^-bits, by doubling (0 if
    above 2^32) then bisection on `add(pow(alpha.hi, t, up), extra.hi, up) <= 2^-bits`; positions(alpha, extra) =
    pos(alpha, B − w(`work positions`, scope), extra); while sizing extra = the margin 2^-(B+30) (P8:556-563).
13. **One group by itself**: fixed point from t = 0 with r = tail(t) for base and mask code; reject after 32 turns
    (P8:564-570).
14. **Later stages of a test** (P8:571-580): with o the stage before and (k', h', n', nz'): ell' = ell_o·c_o / 2^k'
    (rejected on remainder); carried = 2·ell_mask_o + r_o·c_o + 2·r_mask_o; least = 2k' + 1 − h' if k' > 0 else 1;
    ell_mask' = max(up((carried + S + 2^h' − 1) div 2^h'), up(least)); then the iteration of item 13 with
    r' = r_mask' = tail(t), load cube = cube(stage), messages = 1, rows = 4 + 3·max(r_o, 1024). A test needs k > 0 at
    stage 1 and at least one later stage. `[C]` check, small `link` stage 2: ell' = 131072 / 2^4 = 8192; carried =
    2·8192 + 218 + 2·218 = 17038; (17038 + 1 + 7) div 8 = 2130 → up = 4096: matches §2.5.
15. **The group `link`** (P8:581-598): one pair of codes, one distance, one number of positions for all segments;
    request scope; sized with k = the largest k of R12.16 over the chain's groups, h = 0, side count = the largest
    up(1 + q); load: cube, messages = max(8, 2·(most messages of a segment) + 2), rows = x + 4096·y. This k is for the
    sizing alone: each segment's fold has the k of its own group (R14.4). The message into which the last segment is
    closed has the same codes, distance and t and is stage 1 of the last test.
16. **The stored table** (P8:599-614): tfold(x) = sum_{j=1..b} mca(x, 2^(b−j)) + list·fe(b); good(m): s·fe(w_T) +
    2·tfold(x) <= goal(`closeness`, scope); m_once: committer scope, s = 1, and se(list, ceil_log2(i)) <= 2^-B;
    m_later = min(m_once, search in batch scope with s = N). Errors: `LIN point` (key) fe(w_T) + tfold(once);
    `LIN point` (proof) N·fe(w_T) + tfold(later); `LINK point` fe(b) + tfold(once) + tfold(later).
17. **Columns of the stored table** (P8:615-627): see §2.3. The `LINK` round's error is the larger of the two powers
    alpha^t; the eighth word of its entry is the sum of the two numbers.
18. **The three groups of the test on the table** (P8:628-652): `folded`, `omega`, `own` in a proof (batch, batch,
    request scope; N requests) and `once-…` in a key file (committer scope; 1 request). k, h of a group from its
    members as in R12.16: each member counts up(r) for its r rows of a kind; h = ceil_log2(mask rows that count);
    k = max(ceil_log2(main rows that count), h, 1). Members: `folded` = folded row + shared split's mask message;
    `omega` = Omega + shared split's mask message; `own` = index-mask message + W + Omega. Joint iteration from
    t_f = t_o = t_w = 0 with D = t_o + requests·t_w:
    `folded`: r = tail(t_f), r_mask = tail(t_f + t_o), rows = S + columns + 1 + 2S;
    `omega`: r = tail(D), r_mask = tail(t_f + t_o), rows = 1 + 2S;
    `own`: r = tail(D), r_mask = tail(t_w), rows = 2 + 3S; each with cube(group), messages = 2; reject after 33 turns.
    `[C]` checks against §2.5: small Omega tail 55 + 64·59 = 3831, folded mask tail 101 + 55 = 156; full
    51 + 64·55 = 3571 (also P8:906-907) and 101 + 51 = 152; key file: 49 + 1·49 = 98 and 97 + 49 = 146.
    If `folded` and `omega` are equal in n and l: no split, no shared split's mask message, no group `omega`.
19. **A leaf file's link** (P8:653-658): one group under `group once-folded` with the two folded rows, each
    fr = ceil((entries + S) / 2^l) main rows over E; k = 1 + ceil_log2(fr), h = 0; committer scope; rows =
    2S + both numbers of columns + 1 + 2S; later stages from `stages once-folded`. Its numbers differ from the key
    file's group `once-folded`.
20. **The key file's proof of ranges** (P8:659-671): a lookup with q digit weights, g = ceil_log2(q), is cut into
    parts of 2^(L − g) cells; a part has v = L − g + w_T variables; planes = least number that is >= 2, >= v + 1 and
    with 2^planes > sum of 2^v over its parts; mu = max(1, ceil_log2(planes)); rejected if L > ceil_log2(matrix rows)
    or a lookup has more than 256 parts.
21. **What a round samples** (P8:672-680): `LOC`, `BASE`: positions(alpha, 0). `CS`: fixed point t =
    positions(alpha, list_next·pe(1 + S + sym·t)), sym = c + 2 with a mask code else c; then one element of E (may
    be 0); the eleventh word of its entry is 1 + S + sym·t. The number is the eighth word, the ninth is a (base code
    length 2^a). `RNG`: K·T matrix entries (tenth word), T = B − w, error 2^-T. `RECORD`: S·(ceil_log2(i) + 1)
    elements of E, S of them not 0.
22. **Verdict on a plan** (P8:683-696): unit = 3·ratio(2^z − p, 2^z)^6 (z = bits of p); whole = error +
    unit·(x + y) + (1/|E|^2)·y for a round sampling x elements of which y must not be 0; every round needs
    whole <= 2^(w − B); no sum over rounds; every round has one of the names of R14.11; all rounds on the same two
    codes have their errors from the same m; a round **needs its proof of work** if whole > 2^-B.
23. **Order of the whole and further conditions** (P8:697-748): parse frame lines → read model's lines and the other
    files → derive items 15–18, then 20, then 19 → make the plans (proof, key, leaf) → item 22 on every chain → ten
    conditions on hiding (`main-rows`, `mask-rows`, `mask-room`, `fold-room`, `table`, `padding-entries`,
    `range-checks`, `salt`, `leaves`, `batch`) → configuration's digest → shapes fit each other (key file's binding
    tree depth 0; multiplicities' message is the second oracle message of the one-time chain; one identifier per
    segment; one message of masks at the start of a request; at least one pending row; one plain scalar, the next
    token, in the last segment and no other; the layout fits the codes). Further conditions (each
    `parameters-not-admitted`): matrix has >= 1 row; w_T − b <= 30; ceil_log2(matrix rows) <= 30; w_T <= 60;
    (matrix rows)·2^(w_T−b) <= i − 3S; i + m_T <= 2^32 and 3S < i; every non-last stage's mask message has at least
    2k + 1 − h entries; S < 2^l and S < 2^lz of `group link`, S < 2^lz of `group own`; per segment group
    2·2^lz + r + 2·r_mask + S + (kept rows terms) <= 2^l of `group link`. "This list need not be whole" (P8:748).

### 2.5 Known answers: every group and stage (P8 §8.5, P8:778-822)

Cell = base code (length, ell, r); mask code (length, ell, r); m; delta (6 decimals); list size; t = number of
positions. At both files the number that a round samples equals the number for which the tails were sized
(P8:765-766). `k,h` of stage 1 from P8:843-852; k of later stages from the `stages` lines.

**Small (frame lines of `target_small_f2/policy.txt`):**

| group | stage 1 k,h | stages (base; mask; m; delta; list; t) |
|---|---|---|
| `link` | 9,0 per sizing; last test 1,0 | 1: (2^18, 131072, 218); (2^17, 8192, 218); 517; 0.290939; 107; **218** · 2: (2^17, 8192, 55); (2^17, 4096, 55); 319; 0.748391; 477; **55** · 3: (2^16, 1024, 44); (2^16, 2048, 44); 260; 0.820690; 599; **44** · 4: (2^15, 128, 44); (2^15, 1024, 44); 300; 0.818948; 682; **44** · 5: (2^15, 128, 73); (2^15, 4096, 73); 520; 0.642667; 469; **73** |
| `folded` | 5,0 | 1: (2^17, 32768, 101); (2^13, 64, 156); 483; 0.498201; 241; **101** · 2: (2^14, 2048, 68); (2^12, 256, 68); 600; 0.640111; 535; **68** · 3: (2^14, 2048, 68); (2^14, 1024, 68); 600; 0.640111; 535; **68** |
| `omega` | 2,0 | 1: (2^18, 16384, 3831); (2^13, 64, 156); 295; 0.721371; 384; **55** · 2: (2^14, 1024, 69); (2^13, 1024, 69); 527; 0.634203; 459; **69** · 3: (2^15, 1024, 68); (2^15, 4096, 68); 520; 0.642881; 470; **68** |
| `own` | 3,0 `[C]` | 1: (2^18, 16384, 3831); (2^13, 256, 59); 295; 0.721371; 384; **59** · 2: (2^14, 1024, 75); (2^13, 1024, 75); 528; 0.633201; 458; **75** · 3: (2^15, 1024, 73); (2^15, 4096, 73); 520; 0.642667; 469; **73** |
| `once-folded` | 5,0 | 1: (2^17, 32768, 97); (2^13, 64, 146); 483; 0.498231; 241; **97** · 2: (2^14, 2048, 66); (2^12, 256, 66); 600; 0.640281; 536; **66** · 3: (2^14, 2048, 66); (2^14, 1024, 66); 600; 0.640281; 536; **66** |
| `once-omega` | 2,0 | 1: (2^18, 16384, 98); (2^13, 64, 146); 277; 0.748356; 415; **49** · 2: (2^14, 1024, 49); (2^13, 128, 49); 489; 0.743685; 712; **49** · 3: (2^15, 1024, 39); (2^15, 512, 39); 345; 0.819451; 787; **39** |
| `once-own` | 3,0 `[C]` | 1: (2^18, 16384, 98); (2^13, 256, 49); 277; 0.748356; 415; **49** · 2: (2^14, 1024, 49); (2^13, 128, 49); 489; 0.743685; 712; **49** · 3: (2^15, 1024, 39); (2^15, 512, 39); 345; 0.819451; 787; **39** |
| `once-ranges` | 3,3 `[C]` | 1: (2^22, 262144, 49); (2^16, 1024, 49); 158; 0.748395; 238; **49** · 2: (2^19, 16384, 39); (2^17, 512, 39); 195; 0.822111; 455; **39** · 3: (2^17, 2048, 33); (2^17, 256, 33); 210; 0.873427; 730; **33** · 4: (2^20, 2048, 22); (2^20, 1024, 22); 74; 0.954980; 801; **22** |
| leaf file's link | 6,0 | 1: (2^17, 32768, 97); (2^13, 64, 97); 483; 0.498231; 241; **97** · 2: (2^14, 2048, 66); (2^12, 128, 66); 600; 0.640281; 536; **66** · 3: (2^14, 2048, 66); (2^14, 512, 66); 600; 0.640281; 536; **66** |

**Full size (`record.f2.txt` = first 32 lines of `target_full_f2/policy.txt`):**

| group | stage 1 k,h | stages (base; mask; m; delta; list; t) |
|---|---|---|
| `link` | 8,0; last test 1,0 | 1: (2^23, 4194304, 219); (2^17, 8192, 219); 258; 0.290134; 54; **219** · 2: (2^22, 262144, 55); (2^17, 4096, 55); 158; 0.748392; 238; **55** · 3: (2^19, 32768, 55); (2^16, 2048, 55); 241; 0.748756; 362; **55** · 4: (2^16, 4096, 55); (2^15, 1024, 55); 367; 0.747672; 546; **55** · 5: (2^13, 256, 46); (2^13, 256, 46); 378; 0.807808; 798; **46** · 6: (2^15, 256, 44); (2^15, 1024, 44); 345; 0.819027; 785; **44** |
| `folded` | 7,0 | 1: (2^24, 4194304, 101); (2^13, 64, 152); 182; 0.497247; 91; **101** · 2: (2^21, 131072, 54); (2^12, 256, 54); 168; 0.723703; 222; **54** · 3: (2^17, 8192, 54); (2^12, 256, 54); 293; 0.724400; 388; **54** · 4: (2^13, 512, 54); (2^12, 256, 54); 510; 0.724799; 674; **54** · 5: (2^14, 512, 51); (2^14, 1024, 51); 489; 0.743446; 711; **51** |
| `omega` | 4,0 | 1: (2^22, 262144, 3571); (2^13, 64, 152); 159; 0.746720; 237; **51** · 2: (2^18, 16384, 51); (2^14, 512, 51); 277; 0.748715; 415; **51** · 3: (2^14, 1024, 51); (2^13, 256, 51); 489; 0.743446; 711; **51** · 4: (2^15, 1024, 41); (2^15, 1024, 41); 299; 0.819201; 681; **41** |
| `own` | 5,1 | 1: (2^22, 262144, 3571); (2^13, 256, 55); 159; 0.746720; 237; **55** · 2: (2^18, 16384, 55); (2^15, 1024, 55); 277; 0.748684; 415; **55** · 3: (2^15, 2048, 55); (2^14, 512, 55); 423; 0.746127; 624; **55** · 4: (2^13, 256, 46); (2^13, 256, 46); 378; 0.807808; 798; **46** · 5: (2^15, 256, 44); (2^15, 1024, 44); 345; 0.819027; 785; **44** |
| `once-folded` | 7,0 | 1: (2^24, 4194304, 97); (2^13, 64, 146); 182; 0.497247; 91; **97** · 2: (2^21, 131072, 52); (2^12, 256, 52); 167; 0.724589; 222; **52** · 3: (2^17, 8192, 52); (2^12, 256, 52); 292; 0.725290; 388; **52** · 4: (2^13, 512, 52); (2^12, 256, 52); 509; 0.725690; 676; **52** · 5: (2^14, 512, 49); (2^14, 1024, 49); 489; 0.743685; 712; **49** |
| `once-omega` | 4,0 | 1: (2^22, 262144, 98); (2^13, 64, 146); 158; 0.748371; 238; **49** · 2: (2^18, 16384, 49); (2^14, 128, 49); 277; 0.748730; 415; **49** · 3: (2^14, 1024, 49); (2^13, 64, 49); 489; 0.743685; 712; **49** · 4: (2^15, 1024, 39); (2^15, 512, 39); 345; 0.819451; 787; **39** |
| `once-own` | 5,1 | 1: (2^22, 262144, 98); (2^13, 256, 49); 158; 0.748371; 238; **49** · 2: (2^18, 16384, 49); (2^15, 128, 49); 277; 0.748730; 415; **49** · 3: (2^15, 2048, 49); (2^14, 64, 49); 423; 0.746489; 625; **49** · 4: (2^13, 256, 41); (2^13, 64, 41); 470; 0.809509; 1002; **41** · 5: (2^15, 256, 29); (2^15, 256, 29); 201; 0.906440; 981; **29** |
| `once-ranges` | 4,4 | 1: (2^22, 262144, 49); (2^16, 4096, 49); 138; 0.746717; 206; **49** · 2: (2^19, 16384, 39); (2^17, 2048, 39); 195; 0.822111; 455; **39** · 3: (2^17, 2048, 33); (2^17, 1024, 33); 210; 0.873427; 730; **33** · 4: (2^20, 2048, 25); (2^20, 4096, 25); 91; 0.936628; 684; **25** |
| leaf file's link | 8,0 | 1: (2^24, 4194304, 97); (2^13, 64, 97); 182; 0.497247; 91; **97** · 2: (2^21, 131072, 49); (2^12, 128, 49); 182; 0.748580; 274; **49** · 3: (2^17, 8192, 49); (2^12, 128, 49); 318; 0.748480; 476; **49** · 4: (2^13, 512, 50); (2^12, 128, 50); 570; 0.737851; 805; **50** · 5: (2^14, 512, 40); (2^14, 512, 40); 348; 0.816087; 776; **40** |

Rates `[C]` (kappa / len): `link` stage 1 ≈ 0.5008 / 0.50003; `folded` stage 1 ≈ 0.2508 / 0.25001; `omega`, `own`
stage 1 ≈ 0.0771 / 0.0634; table 0.0703 / 0.1040 (given). Folding: each `FOLD round` halves (it sends two of three
coefficients of a quadratic), a stage folds 2^k rows in k rounds (R12.9, P9:260; P8:173).

### 2.6 Digit and limb widths visible in §8–§10

- Key file's proof of ranges: lookup 1 "on bytes": d = 8, one digit of weight 1, offset 128 (each cell in −128..127);
  lookup 2 "on weights": d = 13, two digits of weights 1 and 256, offset 4096; padding key 0 in both (P9:492-495,
  P9:503-506).
- Matrix rows come in units of two or four digits; only the embedding's units have four digits (P9:495-498; P8:714).
- Declared widths: `wb_*` = 13, `wb_emb` = 21 (VPF:148, VPF:199); residual stream five limbs with `xl 5` (VPF:236).
- Field: p = 2^64 − 2^32 + 1; a lookup needs d + w < 64 so that 2^d·(2^w − 1) < p (P9:531, P9:642-645).

### 2.7 Soundness-accounting numbers that a verifier prints or checks

| number | small | full | cite |
|---|---|---|---|
| requested bits (default) / `sec` | 128 / 128 | 128 / 128 | P8:210 |
| rounds that need their proof of work (three files together) | 38 | 71 | XS `README.md:21`; XF `README.md:20` |
| least round with / without work | 128.00 / 96.23 bits | 128.00 / 96.23 bits | same |
| closeness rounds on the theorem on codes: key, leaf, proof | 37, 12, 78 | 63, 23, 255 | P8:854-858 |
| `commitment-assumed-rounds` (key + leaf) | 49 | 86 | XS `README.md:20`; XF `README.md:19` |

`[C]`/`[KA]` reconstruction of these counts from the frame: PoW rounds = `LOC` + `CS` + `BASE` + `LINK`: small proof
10 + 7 + 3 = 20, key 4 + 7 + 3 = 14, leaf 4 → 38; full proof 31 + 10 + 5 = 46, key 4 + 10 + 5 = 19, leaf 6 → 71.
Closeness rounds = `FOLD round` + `BASE lambda` + `LIN point` + `LINK point`: small leaf 10 + 1 + 1 = 12, key
32 + 4 + 1 = 37, proof 73 + 4 + 1 = 78; full leaf 21 + 1 + 1 = 23, key 58 + 4 + 1 = 63, proof 250 + 4 + 1 = 255.

---

## 3. `layout.txt` and `KL.bin`

Configuration = the three public files; the configuration's digest (R4.9) is
`H(169, 0, 2, none; number of files as a word, then for each file its length as a word and its bytes)` in the order
**parameter file, layout file, scale file** (FMT:372-375; FR:93-94; VPF:336). It is the first parameter item after
the plan in every chain (item `configuration`), the start of stored-tree and inner-vertex hashes, and an input of the
commitment ID.

### 3.1 The scale file `KL.bin`

- Read as 32-bit words, lowest byte first; length a multiple of 4 bytes, at least 8 words (`KL-length`)
  (FMT:1696; FMT:2081; FMT:1572-1576).
- For each of the L layers a record of **13 words**: `kq, kk, kv, ko, kg, ku, kd, M1, K1, M2, K2, sh, rp`. After all
  layers, if the model has routed experts, three words `kr, kgR, kuR` for each layer with an odd number, counted
  from 0 (FMT:1722-1724). Exactly 13·L words, plus 3 for every second layer with experts (`KL-length`, FMT:2161).
- Tests (FMT:2162-2165): `KL-shift-range` each shift from 1 to 16, 24 or 32 as the class line (`hq`..`hr`) is 0, 1
  or 2; `KL-kq-kk` kq = kk or both >= 16; `KL-norm` 24 <= M <= 47, 17 <= K <= 32, K + 14 >= M; `KL-rp` rp is 0 or 1.
  Further: `af-policy-sh` every sh from 4 to 12 (FMT:2312); condition `one-shift` (FMT:2002); `norm-shifts`
  K <= M (VPF:317).
- Use: the scales enter the statement (item `request`, R15.5; a digest of the scale file is words 95–102,
  FMT:1263, FMT:1483) and every byte enters the configuration's digest. No frame quantity of §2 depends on them.
- Examples `[C]`: XS `config/KL.bin` 464 bytes = 116 words = 13·8 + 3·4; first record
  (29, 29, 17, 7, 9, 15, 9, 43, 30, 43, 30, 12, 1), `rp` = 0 in layers 3 and 7, expert words (13, 8, 15) four times.
  XF `config/KL.bin` 2,784 bytes = 696 words = 13·48 + 3·24; first record
  (29, 29, 17, 17, 16, 20, 19, 44, 30, 44, 30, 8, 1).

### 3.2 The layout file `layout.txt`

- If the name exists it must be readable; fewer than 2^32 bytes (FMT:1697). Without it every checking call ends
  `NO: plan-layout` (FMT:2082; VPF:327).
- Two kinds of line, of numbers and single letters (FMT:1751-1752):
  - **group's line** `link moment group class rows life` — one oracle message of that moment of that segment
    (`link` = the segment's number; a "group" here is one oracle message, not a group of §8–§10). Class `N`: rows over
    F; `B`: rows over F kept for `life` later segments; `W`: rows over E (FMT:1754-1758).
  - **block's line** `link moment group array R a K e low row place br bj 0` — elements (R + i, K + c), i < 2^a,
    c < 2^e of that array; element number x = c·2^a + i (`low` = `r`) or x = i·2^e + c (`low` = `c`) is in row
    `row` + (x >> bj) of the group at position `place` + (x mod 2^bj); br + bj = a + e (FMT:1766-1770).
  - Segments, moments, groups count from 1; arrays, rows, positions from 0; an array's number is its place among the
    arrays of its own moment (FMT:1770-1772).
- Skipped lines: only blanks/tabs/carriage returns, or first byte `#`; a last line without line feed is read; all
  groups' lines are taken first, then all blocks' lines, each in file order (FMT:1781-1786).
- **More than one admitted encoding** (parsed with C `sscanf`): any white space, leading zeros, signs, unbounded digit
  counts, no white space needed around the letter; a second verifier that admits the plain encoding alone rejects
  some files `cp_verify` admits (FMT:1788-1796). The file's bytes enter the configuration's digest as they are; the
  parsed layout is encoded again canonically as the item `layout` (FMT:1798-1801).
- Tests (all `plan-layout`, FMT:2203-2208): each non-skipped line is a group's or block's line with nothing after its
  last field; block: `link`, `moment`, `group` not 0, `link`, `moment`, `group`, `array` below 2^20, letter r or c,
  last number 0, a, e, br, bj below 48; group: `link`, `moment`, `group` not 0 and below 2^20, class N, B or W, rows
  1..2^32−1, life below 2^20 and not 0 exactly in class B; groups of a moment, moments, segments come in turn; the
  first oracle message of a segment is not kept; br + bj = a + e; `R`, `K`, `row`, `place` below 2^48 and multiples
  of 2^a, 2^e, 2^br, 2^bj; blocks inside array / sent rows / a row's message, no overlap, each element once, no two
  blocks of one oracle message share an entry, no block covers a pad.
- **How the verifier uses it.** (a) Four of the six words of each segment message (R12.12) come from the group's
  line: main rows = `rows`; second word 3 for `W`, 1 for `N`/`B`; moment = `moment` − 1; life = `life`. Not in the
  file: mask rows = 1 for the first oracle message of a segment's first moment and 0 for every other; leaf class 0
  (FMT:1758-1764). (b) The item `layout` (R14.5, P10:131-157): a list with one entry per segment, each a list of
  arrays: name (text), number of the oracle message, rows, columns, list of blocks; a block is nine words
  (first row in the array; first column; first row of its rectangle in the message's table; first position; b for the
  block's rows; for its columns; for the rectangle's rows; for its positions; 1 if `low` = `r` else 0). Arrays of a
  segment come in the order in which a block's line first names each; blocks in file order; nothing sorts them, and
  the order is hashed (P10:152-157). Byte encoding: FR:482-491. Array names are those of FMT:1744-1750 (`M<i>`,
  `U3`, `ZZ`, `BZ`). Conditions on the item: P10:159-170.
- Examples `[C]`: XS 740 lines = 1 comment + 19 group lines + 720 block lines (27,038 bytes); XF 5,519 lines =
  1 comment + 99 group lines + 5,419 block lines (224,975 bytes). Group lines (`moment group class rows life`):

  | segment | small | full |
  |---|---|---|
  | G_0 (segment 1) | 1 1 N 61 0 · 1 2 B 3 1 · 1 3 B 1 2 · 2 1 W 2 0 · 3 1 N 129 0 | 1 1 N 106 0 · 1 2 B 9 1 · 1 3 B 3 2 · 2 1 W 1 0 · 3 1 N 31 0 |
  | A_g | 1 1 N 23 0 · 2 1 W 1 0 · 3 1 N 61 0 | 1 1 N 42 0 · 2 1 W 1 0 · 3 1 N 14 0 |
  | G_g, g >= 1 | 1 1 N 60 0 · 1 2 B 3 1 · 1 3 B 1 2 · 2 1 W 2 0 · 3 1 N 129 0 | 1 1 N 104 0 · 1 2 B 9 1 · 1 3 B 3 2 · 2 1 W 1 0 · 3 1 N 31 0 |
  | H (last) | 1 1 N 34 0 · 2 1 W 1 0 · 3 1 N 81 0 | 1 1 N 103 0 · 2 1 W 1 0 · 3 1 N 24 0 |

  From these, by R12.16 (P9:890-903), k of each segment's group `[C]`,`[KA]`: small 9, 7, 9, 7, 8; full 8 (G), 7 (A),
  8 (H); h = 0 everywhere (one mask row). Worked example, small group 1: up(61) + up(2) + up(129) = 64 + 2 + 256 =
  322 → k = 9; small group 2: 2 (carrying) + up(3) (kept message whose life ends here) + up(23) + up(1) + up(61) =
  103 → k = 7. KA confirms: 18 `FOLD round` for G#, 14 for A#, 8 for H (small); 96, 84, 8 (full).
