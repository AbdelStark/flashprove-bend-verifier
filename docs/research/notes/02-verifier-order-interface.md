# 02 — What the verifier does, in order; its interface; its results

> Status: frozen
> Recovered working notes, 2026-11-23. Upstream excerpts from FlashProve, Copyright 2026 Anthropic PBC, Apache-2.0.

Digest of `docs/format/FORMAT.md` sections 12 to 18 (lines 1122 to 5069) of FlashProve 0.16.0-rc.26,
commit 9e2bdd8 (upstream is read-only), cross-read with `verifier/docs/output.md`,
`verifier/src/vf_rejection_names.txt`, `docs/verifying.md` and `guide/verify-a-proof.md`. Where the
page gives a string or an order only in part, it was confirmed in the C++ source; those items are
tagged **(src)**.

## Citation legend

Paths are relative to the upstream root. `X:n` means line n of file X.

| tag | file |
|---|---|
| F | `docs/format/FORMAT.md` |
| P10 | `docs/format/10-proof-file.md` |
| FR | `docs/format/README.md` |
| OUT | `verifier/docs/output.md` |
| NAMES | `verifier/src/vf_rejection_names.txt` |
| VER | `docs/verifying.md` |
| GUIDE | `guide/verify-a-proof.md` |
| CPP | `verifier/src/cp_verify.cpp` |
| VFC | `verifier/src/vf_common.h` |
| VFI | `verifier/src/vf_input_files.h` |
| HEAD | `verifier/src/vf_output_head_check.inc` |
| CHK | `blocks/frame/check.h` |
| VRM | `verifier/README.md` |
| SMAP | `verifier/docs/source-map.md` |
| LTREES | `lean/OnBytes/Model/Trees.lean` |

Tags on claims: **(R x.y)** a numbered rule of the format; **(spec/src)** the page itself says the
text is "from the programs' source" and has no numbered rule; **(src)** read by me in the C++;
**(inference)** mine, not stated upstream.

How far each section is normative:

- 12.2, 12.5, all of 13 but 13.1, and 14 have **no numbered rules**: they are written from the
  source of `cp_verify` (F:1151-1152, F:1321-1322, F:1581-1583, F:2629).
- Duty of a second verifier: "must make the same tests on key file, leaf file, proof file, request
  file and token file. It must also make the tests of 13.8 on the three public files. ... need not
  use the same names or the same order of tests: the order decides only under which name a bad call
  is rejected." (F:1583-1588)
- Where 13.8 names a test without its formula, the page does not define it and "the programs'
  source is the only text" (F:1621-1622).
- On bytes, hashed strings, order and tests, FORMAT.md takes precedence over every other page of
  the repository (FR:7-9).

## 0. Findings that shape the implementation

1. A whole call is: tests before the stages, then three stages (`key`, `leaf`, `request`) that
   each work alone on the same bytes, then the parent's closing logic. "No stage passes anything to
   another" (F:1658). `cp_verify` runs them as three processes; "a second verifier can run them one
   after the other, in any order" (F:1830-1831). The call's rejection name is that of the first
   stage that rejected, in the order key, leaf, request (F:1887-1888).
2. Every stage starts with the same eight steps on the three public files (13.4), then forms the
   commitment ID from the public files and the beginning of `key.bin` and compares it with `-id`
   (`model-statement`), before it looks at anything else (F:1711-1714, F:1808-1817).
3. The page defines neither the derivation of sizes and plans nor the round-error accounting by
   numbered rules: "this page does not decide whether a plan meets its target or needs its proof of
   work; a second verifier takes the plan, the codes and the shapes as inputs" (F:3876-3883).
   Section 18 lists what such a verifier must then test or assume (section 8 of this note).
4. Four public tables are made with floating-point `exp`, `pow`, `cos`, `sin`; only the 32 digest
   lines of the parameter file fix them. A verifier may take the tables as data, but must then
   compute K(72; table) and reject if it differs from the file's line (F:1235-1238, F:1491-1501).
5. Widths: section 12 words are 32 bits little-endian (F:1129-1131); the second hash function runs
   BLAKE2b's compression function on 64-bit long words (F:1410-1423); the no-overflow conditions
   are "computed in integers of 128 bits" (F:2168). All three need multi-word arithmetic on a
   U32-only target (inference).
6. Results have five classes (`YES`/`WITHIN LIMITS`, `NO`, `NOT CHECKED`, `NOT-A-VERIFICATION`,
   no verdict). R0.3 asks for two answers: where `cp_verify` ends `NOT CHECKED` or
   `NOT-A-VERIFICATION`, "a verifier with two answers rejects" (F:1632-1633, F:1900-1902,
   F:2354-2355, F:3957-3958).
7. Passing every test is not enough for an acceptance: 14 conditions of 13.7 are part of what an
   acceptance means and "bind every verifier" (F:1892-1902).
8. The page was compared with no second implementation for the claims of section 11 and the rows
   of 13.9 (F:4064-4066), and "no second verifier written from this page has decided on a proof of
   the programs" (F:3867-3868). Where page and program disagree, only the program has ever been
   run; 17.2 lists the known differences (section 7 of this note).

## 1. Request file, token file, next token

### 1.1 Byte layout

- A **word** in section 12 has 32 bits and is four bytes, the lowest first (F:1129-1131).
- **Request file**: T + 2 words, T = 2^lt, `lt` a line of the parameter file. First T **tokens**,
  then two positions r and e (F:1154-1155). So 4 (T + 2) bytes (F:1576-1577).
- **Token file** (the programs call it the y file): one word y, "the next token that the caller
  was served" (F:1162-1164). 4 bytes.
- T comes from the parameter file alone (F:1170-1171). `lt` is from 4 to 16 or every stage rejects
  (`shape-words`, F:2111); for an acceptance `lt` is at most 10 (`rotary-table`, F:2005).
- V, the vocabulary's size, is the line `V`, from 2 to 2^24 (`shape-V`, F:2171).

### 1.2 Meaning of r, e, T

- The proof **checks** positions r up to and not including e: the **checked positions**
  (F:1155-1156).
- Position t is about token t + 1 of the request; position T - 1 is about the **next token**
  (F:1157-1158).
- **Checked tokens** = tokens r + 1 to min(e, T - 1) of the request. The next token is not counted
  among them (F:1158-1160).
- If e = T, position T - 1 is checked and is about the next token, "which has no cost and must be
  the top choice of that position (the index of its largest logit, the lowest index on ties),
  whatever the policy is" (F:1160-1162).
- n = min(e, T - 1) - r is the number of checked tokens (F:2746). R (RC in 11.4) is the number of
  checked positions below T - 1 (F:1336); the two are the same number (inference from the two
  definitions).
- "Every token of the file is an input of the model's run, so a proof fits one request file only.
  But an acceptance is about the checked tokens and, if e = T, the next token, and about no other
  token." (F:1178-1179)
- Client-side recipe: prompt of P tokens and reply of R tokens (end token included): r = P - 1,
  e = P + R - 1; with r = P the reply's first token goes unchecked (VER:119-123). If prompt and
  reply add up to T + 1 tokens, the reply's last token is y and e = T (VER:125-128).

### 1.3 Filler

- A request holds exactly T tokens: the prompt, then the reply, then **filler tokens**
  (VER:115-117). Filler is part of the request, so client and provider must pad with the same
  token; the protocol does not say how they agree; the shipped tools pad with token 0
  (OUT:370-372, VER:130-132).
- Any token id below V is allowed as filler, "but with some filler tokens a request may have no
  proof at all" (OUT:372-373): a token outside the checked positions, "also one that only fills
  the request up to T tokens, can bring the model out of a table or a range, and then an honest
  prover has no proof of the request" (F:1342-1346).
- Example (T = 64, range 9:14): 66 words = 10 prompt ids, 5 reply ids, filler 49 times, then 9,
  then 14 (OUT:364-368). For e < T the token file is four zero bytes (VER:125-126).

### 1.4 What makes the caller's two files malformed

"A verifier rejects the call unless all of the following hold" (F:1166-1176). No numbered rules
(F:1151-1152).

| test | condition | name | line |
|---|---|---|---|
| 1 | the length of each file is a multiple of 4 bytes, and neither file is empty | `statement-required` | F:1168-1169 |
| 2 | the request file has exactly T + 2 words and the token file exactly one | `statement-range` | F:1170-1171 |
| 3 | r < e <= T | `statement-range` | F:1172 |
| 4 | if e < T then y = 0 | `statement-range` | F:1173-1174 |
| 5 | every one of the T tokens, checked or not, and y are below V | `token-range` | F:1175-1176 |

Where they are made:

- **Before the stages, whole call only, on lengths alone** (F:2086, F:2767-2775): by the length
  that `stat` gives (symbolic links followed), before a byte of either file is read: first the
  request file (4 (T + 2) bytes), then the token file (4 bytes). A length of 0 or not a multiple
  of 4 gives `statement-required`; any other wrong length gives `statement-range`. Left out for
  the request file if the line `lt` cannot be read or is above 20; left out for either file whose
  path names no regular file (the read that follows then ends the call with exit code 2). (src)
  CPP:3230-3234, CPP:3343-3344.
  Consequence: with both lengths wrong the name can differ from 12.2's order, since here both
  tests are made on the request file before the token file is looked at (F:2086). A call ends here
  "whatever a later test or a stage would have found in the other files" (F:2086).
- **In the stage request, on what was read** (F:2221-2224). Order (src): odd length of either file
  -> `statement-required` (CPP:2302); either empty -> `statement-required` (CPP:317); sizes ->
  `statement-range` (CPP:318); r >= e or e > T or (e < T and y != 0) -> `statement-range`
  (CPP:324); y >= V -> `token-range` (CPP:2309); any token >= V -> `token-range` (CPP:2321-2322).
  The names `header-y` (CPP:2310) and `token-length` (CPP:2314) belong to repeats at this point
  that cannot fail (F:2224, F:2228).
- A planning call does not make the length test; it reads both files whole and makes tests 1 and
  2 of 12.2 (F:2086).

### 1.5 How the request enters the proof: two items

- The item `request` "is not the bytes of the request file. It is the **statement**: a sequence of
  177 words that each program makes for itself, by its own code, from the parameter file, the
  scale file and the request file" (F:1135-1137). No word of it comes from a key file, a leaf file
  or a proof file (F:1137-1138).
- The request file, whole, is the value of the item `the request file's words`, directly after the
  item `request` (R14.3, item 4; F:1138-1139, F:1180-1181, P10:108-115). Its length word is
  4 (T + 2) + 8, the string's own 4 (T + 2) (P10:110).
- "soundness for the tokens leans on item 4" (P10:114-115): the digest of the request inside
  `request` is "redundancy that the verifier recomputes" (F:1214-1216).
- **(R15.1)** The value of `request` is 177 words of four bytes, lowest byte first: 708 bytes; with
  its length before it as a word of 8 bytes (R1.6) it is encoded in 716 bytes (F:1196-1197).
- **(R15.7)** In the programs' own statement word 171 holds the next token; in the item it is 0
  (F:1290-1292). (src) the item is the statement with word 171 set to 0: CPP:2431-2432.
- The rules of 12.3 hold for one form of the parameter file: `prof` is 20, `NE` is not 0, and the
  32 digest lines are there; `cp_verify` accepts under no other form (F:1185-1188).

**(R15.5) The 177 words** (F:1255-1270). A name means the number of the line of that name.

| words | content |
|---|---|
| 0, 1 | 0x4D363100; the version word (the four characters of the line `version`, the first lowest) |
| 2..28 | `prof` `lt` `L` `ll` `d` `H` `G` `dh` `f` `fe` `NE` `V` `eps1_lo` `eps1_hi` `eps2_lo` `eps2_hi` `cs` `theta0_lo` `theta0_hi` `hq` `hv` `ho` `hgD` `huD` `hdD` `hr` `ut` |
| 29..36 | digest of the lines `call` |
| 37..70 | `la` `nmin` `D` `tau` `lmaf` `NAf` `lmad` `NAd` `lmar` `lmb` `lmq` `lmx`; `wb_qk` `wb_v` `wb_o` `wb_g` `wb_u` `wb_gs` `wb_us` `wb_gr` `wb_ur` `wb_dn` `wb_dnr` `wb_r`; `iota_0`..`iota_7`; `seed_lo` `seed_hi` |
| 71..102 | `tsilu0..7`; `tsig0..7`; `trope0..7`; digest of the scale file |
| 103..113 | `lB` `S` `rx` `kFM` `kFD` `lmS` `NAs` `lmh` `lmo` `lmbA` `iotaA_0` |
| 114..129 | `texp0..7`; digest of the lines `callA` |
| 130..154 | `MF` `KF` `epsF_lo` `epsF_hi` `toksrc` `lmhf` `NHf` `lmhd` `lmhr` `lmbH` `wb_emb` `wb_head` `iotaH_0`..`iotaH_5` `C` `theta` `cap` `s` `sh` `sT` `F` |
| 155..170 | digest of the lines `callH` (155..162); digest of the request (163..170) |
| 171 | 0: the position of the next token (R15.7) |
| 172 | B of the line `sec` |
| 173..176 | of the line `table`: w; b; n; m |

The acceptance policy is words 148 to 154 (F:1307-1308).

**(R15.2) Lines that are read** (F:1198-1210): ASCII text; each line ends with a line feed and is
a name then numbers or names separated by one blank; a number is a decimal numeral without sign
and without a leading zero, below 2^32; no name occurs twice. Order: frame lines `version` to
`table` (section 8; the statement takes `version`, `sec B` and `table b n i m e w`); then the lines
`prof` to `F`, each a name and one number; then lines that give no word; then the 32 digest lines
`tsilu0..7`, `tsig0..7`, `trope0..7`, `texp0..7`; then the **call lines** `call`, `callA`,
`callH`. The programs reject any other order or encoding.

**(R15.4)** The words of a text are its ASCII bytes, four to a word, the first byte lowest; the
last word is filled with zero bytes (F:1253-1254).

**(R15.6) Digests that are computed** (F:1272-1286):

| digest | of what | function | statement words | line |
|---|---|---|---|---|
| lines `call` | the words of the text of these lines, each whole with name and line feed, in file order | K under 73 | 29..36 | F:1480 |
| lines `callA` | the same | K under 73 | 122..129 | F:1481 |
| lines `callH` | the same; if the file has none, the six lines `callH R16a R16 NF NFH HD0`, `callH R16b R16 HD1`, `callH R8 R8 ROW HD2`, `callH FEa FE HE0`, `callH FEb FE HE1`, `callH FC FC CNF`, each with its line feed | K under 73 | 155..162 | F:1274-1277, F:1482 |
| scale file | all its words | TK | 95..102 | F:1483 |
| request | the 2^lt + 2 words of the request file | TK | 163..170 | F:1484 |
| SiLU table | 65,536 words | K under 72 | 71..78; compared with `tsilu0..7` | F:1485 |
| sigmoid table | 65,536 words | K under 72 | 79..86; compared with `tsig0..7` | F:1486 |
| rotary table | 2^lt dh words | K under 72 | 87..94; compared with `trope0..7` | F:1487 |
| softmax table | u0 words | K under 72 | 114..121; compared with `texp0..7` | F:1488 |

A file without a line `call` or `callA` is rejected by all three programs (F:1278-1280). Known
difference: `cp_verify` does not hash the file's bytes of the call lines; it re-forms each text
from the parsed tokens (17.2 item 12, F:4048-4062; (src) CPP:1337-1344).

### 1.6 The second hash function K and TK (R15.3; 12.6)

Exact definition (F:1413-1449; R15.3 at F:1240-1252 takes precedence, F:1406):

- F = BLAKE2b's compression function (RFC 7693, 3.2): state of eight 64-bit long words, block of
  sixteen, a 128-bit counter t, a flag. Two 32-bit words make a long word, the low word first; a
  long word gives back its low word first (F:1410-1411, F:1415-1423).
- First state = BLAKE2b's start for a 64-byte digest and no key (IV with 0x01010040 xored into its
  first word) (F:1244-1245, F:1425-1426).
- **K(num; w)**, num < 2^32, w a list of n words, n < 2^32: cut w into blocks of 32 words, at
  least one block (also if n = 0), the last filled with zero words; block j (from 0) is one call
  of F; low 64 bits of t = 128 (j + 1), but 4 n in the last call; high 64 bits of t = num + 2^32 n
  in every call (num is the low word, n the high word, F:1453-1454); the flag is set in the last
  call alone; the digest is the first eight words of the last state (F:1428-1437).
- **TK(w)**, at least eight words: cut into pieces of 128 words (the last can be shorter), replace
  each by K(10; piece) with n the piece's own length, join; while more than eight words are left,
  do the same under the number 11. "TK of eight words is K(10; w), not w." (F:1439-1449)
- Numbers in use: 10 and 11 in TK, 72 for a public table, 73 for a list of lookup calls (F:1471).
- K is not BLAKE2b: the only difference is the high half of the counter; with that half 0 the same
  steps give BLAKE2b-512 of the list's bytes, "a good first test" (F:1451-1459).
- Printing a digest: eight words in order, each as eight lower-case hex digits, most significant
  first (not a BLAKE2b library's byte order). A digest line of the parameter file holds one word
  as a decimal number (F:1464-1467).
- Known answers: 14 in the table at F:1524-1539; 57 more in `verifier/tests/hash_vectors.txt`
  (format at F:1544-1550).
- What it is for: "A second verifier needs it to form that item and to check the 32 digest lines"
  (F:1403-1404). Binding the request needs H alone (the file's words are an item of their own
  under H); K alone decides which four tables a parameter file names (F:1216-1223).

### 1.7 The four public tables (12.6)

Formulas at F:1496-1514 (from the source; "R15.6 does not define them"): SiLU (65,536 entries),
sigmoid (65,536 entries, two forms by the line `gcl 1`), rotary (cosines then sines, 2^lt dh
entries), softmax (u0 entries, ends before the first 0). "The formulas do not fix the tables bit
for bit ... What fixes the tables is the 32 digest lines of the parameter file, so for a formal
definition the four tables are data" (F:1498-1501). A fifth table, the head's table of
exponentials, "is made by an integer recurrence and has no digest" (F:1733-1734).

The page's rule for a verifier that takes the tables as data: it "still computes each table's
digest under K and rejects if it differs from the file's line, or its verdict is about tables that
nothing ties to the commitment" (F:1235-1238). That prover's and verifier's tables agree to the
bit "is a matter of completeness, not of soundness" (F:1238-1239).

Also rejected (spec/src): a scale file of fewer than eight words; a parameter file or layout file
of 2^32 bytes or more (F:1516-1518).

### 1.8 The next token

- **(R14.8)** The next token is one element of E, unmasked, a prover's message by itself in a round
  `REPLY` of kind 7 in which the verifier says nothing; the round comes directly before the
  `SEND seed` with which the last segment begins (P10:254-259).
- **(R15.7)** The token y is the element of E with e_0 = y and e_1 = e_2 = 0 (F:1293-1294).
- The comparison, as `cp_verify` makes it (F:1296-1303):
  1. turn the caller's y into the element (y, 0, 0);
  2. read the prover's element in the round `REPLY`;
  3. go through all segments of the first chain, to the end of their last proximity test;
  4. then, "before it reads anything more of the first chain", compare the two elements, all
     three coordinates; if they differ reject: `reply-differs`.
- An element not of the form (y, 0, 0) with y below V is rejected earlier, inside the last
  segment: `header-y` (F:1300-1302, F:2228). (src) HEAD:32: exactly one plain scalar, c1 = c2 = 0,
  c0 < V.
- The head's sub-proof takes the token of position T - 1 from the **proof's** element, not from
  the caller's file (src: HEAD:33-36); the caller's y meets it only in the one comparison (src:
  CHK:176, reason `the proof is about another reply`). So a wrong y beside an otherwise valid proof
  ends `NO: reply-differs`, not `proof-refused`.
- "The next token is compared at this one point and nowhere else. The next token enters the
  chain's hash as a prover's message, so every value that the verifier samples later depends on
  it." (F:1302-1303)
- The comparison is made whatever r and e are; with e < T the caller's y is 0 (test 4), so the
  proof's element must be 0 too (inference from F:1173-1174 and F:1296-1300).

## 2. Acceptance policy

### 2.1 Where it is

- Not a file: seven lines of the parameter file, `C` `theta` `cap` `s` `sh` `sT` `F`, statement
  words 148 to 154 (F:1307-1308).
- Fixed three times over: the configuration's digest takes every byte of the parameter file and is
  a parameter item of each of the proof's three chains; the item `request` holds the seven words;
  the commitment ID takes the same digest (F:1309-1314).
- The ID is in no first query: "A proof meets the ID only by way of the tables" (F:1316-1321).

### 2.2 Tests on the seven lines: `policy-gap-words`

A verifier rejects a parameter file unless all hold (F:1348-1358; (src) CPP:1667-1690):

- theta <= C;
- cap <= T and cap < 2^16;
- F = 24;
- s <= 63;
- sh is 7 or 8;
- sT = sh - 4, or sh + 4 <= sT <= sh + 10;
- 2 V <= 2^F;
- 2^(la - lt) divides JVa, where JV is V rounded up to a multiple of 2^(la - lt) and JVa is half
  the least power of two that is not below JV.

The line `s` "is what the provider gives as the exponent of the model's logits. It is printed and
compared (below), and it is in no equation." (F:1361-1362)

### 2.3 Cost, and what a proof is about

- A checked position t < T - 1 has a **cost**. win = the position's token; lam[v] = the position's
  integer logit of vocabulary entry v. **gap** = max over v < V of lam[v] - lam[win] + [v < win]
  ([v < win] is 1 if v is below win, else 0). So gap = 0 exactly if the token's logit is the
  largest with the lowest index on ties; a token that ties with a lower-numbered one has gap 1
  (F:1324-1328).
- cost = gap + 2^sh under the **step table** (sT = sh - 4) (F:1328, F:1360-1361). Where
  sT >= sh + 4 a second form (negative log-probability at exponent sT, if greater) exists in the
  stages' code only; no whole call judges under it (F:1328-1333, F:1373-1378).
- C and theta are in units of a cost, not of a gap (F:1332-1333).
- With R the number of checked positions below T - 1, "A proof is about the following: the costs,
  each counted as at most C, add up to at most theta R; at most cap of them are above C; and, if
  e = T, y is the top choice of position T - 1, with the lowest index on ties." (F:1336-1338)
- A proof is also about the run at all T positions: "no value of the integer model leaves a table
  or a range at any position" (F:1340-1342).

### 2.4 The four kinds

| kind | condition | line |
|---|---|---|
| `exact-match` | C = theta = 2^sh, cap = 0, sT = sh - 4 | F:1368 |
| `clipped-gap` | sT = sh - 4, with any other C, theta, cap | F:1369 |
| `log-probability` | not one of the two above, and sT = s | F:1370 |
| `another-table` | every other case | F:1371 |

(src) VFC:615-628; the exact-match predicate also asks sh < 63 (VFC:616).
"A whole call of `cp_verify` takes the kinds `exact-match` and `clipped-gap` alone" (F:1385-1386).
`cp_commit` and `cp_prove` reject the other two at their start (`prover-only-policy-kind`), so no
proof of the programs is made under one (F:1376-1378).

### 2.5 The option `-policy` and the rejection `NO: policy`

- Syntax: `-policy <kind>,<C>,<theta>,<cap>,<s>,<sh>`, commas and no blanks; the kind is
  `exact-match` or `clipped-gap` and no other (F:2636, F:2667, F:1396-1397). Each number has 1 to
  10 digits without a leading zero (F:2652; (src) VFC:683-704). Another form: one line on standard
  error that begins `-policy requires`, exit code 2 (F:2667).
- Comparison: the kind and the five numbers C, theta, cap, s, sh must **equal** those of the
  parameter file, each by equality (F:1387-1388; (src) VFC:678-681). sT and F are not named:
  both kinds imply sT = sh - 4 and F is always 24 (VFC:669-671).
- A whole call ends `NO: policy`, with a line before it that begins `policy:`, in four cases
  (F:2743-2758):
  1. the parameter file has an sT other than sh - 4 (with or without `-policy`, also where no
     token is checked);
  2. `-policy` names another kind, or another C, theta, cap, s or sh, than the file sets;
  3. the call has no `-policy`, n is above 0, and the file's policy is not `exact-match`;
  4. the named numbers say nothing: C below 2^sh; or theta below 2^sh; or theta above C; or
     theta = C and 0 < n <= cap. "The first three of these are tested on the command line alone,
     before any file is opened."
- Order of the tests (F:2079, F:2087; (src) CPP:3322 then CPP:3254-3271):
  a. command line alone, before any file is opened: C < 2^sh, theta < 2^sh, theta > C (in this
     order: VFC:660-663);
  b. once the request file and the token file are read and before the proof file is opened:
     (a) sT = sh - 4; (b) with `-policy`, kind and five numbers are the file's; (c) without
     `-policy` and with r < T - 1, the file's policy is `exact-match`; (d) with `-policy`, not
     (theta = C and 0 < n <= cap).
- When the tests are left out (F:2087, F:2760-2764): all four if the length of the request file or
  of the token file is not a multiple of 4 bytes, or if one of the lines C, theta, cap, s, sh, sT
  cannot be read; (c) and (d) if `lt` cannot be read or is above 20, if the request file has not
  T + 2 words, or if r < e <= T fails. "By the source a stage rejects such a call."
- A part-call and a planning call do not make these tests (F:2087, F:2764).
- The stage request asks (b) and (c) once more as the conditions `policy-named` and `exact-match`
  (F:2087, F:1966-1967); a miss there gives `NOT-A-VERIFICATION`, not `NO` (section 3.8).
- A call that checks no token of the request (R = 0) "is not rejected for theta = C, whatever cap
  is" (F:1392-1393).
- Literal `policy:` lines (src): `policy: the parameter file sets the kind of policy <kind>; this
  program takes exact-match and clipped-gap` (CPP:3261); `policy: the option -policy names another
  kind of policy or another C, theta, cap, s or sh than the parameter file sets` (CPP:3263);
  `policy: the request covers more than the output token, the parameter file sets another policy
  than exact-match, and the call has no -policy` (CPP:3269); `policy: a result under the named
  policy would mean nothing: <one of four sentences>` (CPP:3242-3249).

### 2.6 `YES` or `WITHIN LIMITS`

- `WITHIN LIMITS: clipped-gap C=<C> theta=<theta> cap=<cap> s=<s> sh=<sh>`, exit code 0: every
  stage passed every test, no cause of 14.4 applies, and a token of the request was checked
  (r < T - 1) under a `clipped-gap` policy that the caller named with `-policy`. The five numbers
  are the parameter file's (F:2682).
- `YES`, exit code 0: every stage passed, no cause applies, "and no token of the request was
  checked under another policy than `exact-match`: the policy is `exact-match`, or r = T - 1 and
  the call is about the next token alone" (F:2683).
- (src) the decision is `otherKind = (r + 1 <= min(e, T - 1)) and not exact-match` (CPP:2988-2992).
- **The next-token exception**: with r = T - 1 and e = T the call ends `YES` under either policy,
  "because no token inside the window is checked" (VER:421-423); `claim=next-token` can come
  beside `policy=clipped-gap` (F:3148-3149). The next token is always judged as the top choice
  (F:1160-1162, F:1338).
- Same exit code, another last line: "a caller reads both the exit code and the last line"
  (F:2671-2673). "The program's source says of this result that it is not a `YES`" (F:2682).
- The option `-next-token` says the proof must be about the next token alone (r = T - 1 and
  e = T); with other r, e the call ends at best `NOT-A-VERIFICATION` (F:2666, F:2812-2814).

### 2.7 `above-clip`

n = min(e, T - 1) - r, m = min(cap, n). If C <= 2^sh the field is m; else the least of m and
n (theta - 2^sh) / (C - 2^sh) rounded down, with 0 for the quotient where theta <= 2^sh
(F:3080-3084; (src) VFC:642-648, with twelve asserted known answers at VFC:649-654). It is 0 under
`exact-match` (F:3086).

## 3. The verifier's algorithm, in order

Numbering: phases A to G are this note's; inside them the format's own numbers are kept (13.3
rows 1 to 8, 13.4 steps 1 to 8, 13.6 items 1 to 8, 13.7 conditions 1 to 14, 13.9 tests 1 to 5 and
events 1 to 9).

### 3.0 Five duties of every verifier (13.1)

- **R0.1** hash the encoding of parsed objects, or accept canonical encodings only; the public
  files are the exception: hashed byte for byte (R4.9), and the layout file has more than one
  admitted encoding (F:1626-1629).
- **R0.2** a key file, a proof file or any other file never sets a public parameter; it can repeat
  one, and the verifier compares (F:1630-1631).
- **R0.3** whatever depends on the bytes of a file makes a verifier answer "rejected"; it never
  ends the process and never leaves the answer open (F:1632-1633).
- **R0.4** whatever a decision reads that is neither a prover's nor a verifier's message is read
  out of the items of its chain's first query or computed from them (F:1634-1636).
- **R0.5** every public fact has one home; where two forms of one fact must exist (plan beside
  shapes; values beside the digest of the public files; request file beside its digest), one
  routine makes both and the verifier takes that routine's result alone (F:1637-1643).

### 3.1 Phase A — the command line (no file is opened)

| step | what | on failure | line |
|---|---|---|---|
| A1 | five positional arguments first, in order: `<config folder> <ivk folder> <request file> <y file> <proof file>`; options after them in any order | usage text, exit 2 | F:2634-2639; CPP:3279 |
| A2 | options: unknown option, a second `-bits`/`-id`/`-j`/`-policy`, or an option without its value | usage text on standard error, last line `cp_verify: this command line was not accepted: <what>`, exit 2 | F:2653-2656, F:2677; CPP:3115 |
| A3 | `-policy` has the form of 2.5 | one line on standard error beginning `-policy requires`, exit 2 | F:2667; CPP:3299-3303 |
| A4 | a number is 1 to 7 decimal digits, no sign, no leading zero but in `0`; `-bits` 0 to 1000000; `-j` 1 to 256 | usage text, exit 2 | F:2651-2652, F:2661, F:2663; VFC:353-370 |
| A5 | `-id` is 64 hex digits (capital letters count as small ones) | `-id requires 64 hex digits` on standard error, exit 2 | F:2660; CPP:3311-3317 |
| A6 | requested bits are at most 128 (half a digest's bits) | `NO: cp-bits-above-digest`, exit 1 | F:2078; CPP:3321 |
| A7 | with `-policy`: C >= 2^sh, theta >= 2^sh, theta <= C | line `policy: ..`, then `NO: policy`, exit 1 | F:2079; CPP:3322 |

Without `-bits` the requested bits are 128 (F:2661). An option without a value can be given more
than once (F:2653-2654).

### 3.2 Phase B — the files are read, and the tests before the stages

"The verifier reads every file once, whole, into memory, before any stage starts. Every parse and
every hash of a file works on these bytes" (F:1677-1678). Only a regular file is read; symbolic
links are followed (F:1678-1679). "No file holds a length, a count or an offset: every length
follows from the three public files (R0.2) and, for an opening, from the sampled positions (R8.1)"
(F:1689-1691). The program reads no environment variable, writes no file and keeps nothing
between calls (F:1706-1707).

The files (13.3, F:1693-1702):

| # | file | path | read as | tested before the stages |
|---|---|---|---|---|
| 1 | parameter file | `<config folder>/policy.txt` | bytes | fewer than 2^32 bytes; first line is `version`, a blank, the program's version word, a line feed |
| 2 | scale file | `<config folder>/KL.bin` | 32-bit words | length a multiple of 4 bytes; at least 8 words |
| 3 | layout file | `<config folder>/layout.txt` | bytes | if the name exists it must be readable; fewer than 2^32 bytes |
| 4 | key file | `<ivk folder>/key.bin` | bytes | at least 8 bytes; `CPIK`; the version word |
| 5 | request file | as named | 32-bit words | length 4 (T + 2) bytes before a byte is read; then the test `policy` |
| 6 | token file | as named | 32-bit words | length 4 bytes, tested after file 5's length and before a byte of 5 or 6 is read |
| 7 | proof file | as named | bytes | at least 12 bytes; `CPPF`; the version word; bytes 8 to 11 give k |
| 8 | leaf file | `<ivk folder>/leaf/<k>.bin`, k in decimal | bytes | nothing, not even its head |

The version word: the program is built for one field and accepts `H821`; it rejects `H811`
(F:1704-1705). "There is no test on k: a k without a leaf file ends where the leaf file is read"
(F:1705-1706).

The tests, in the order of the run (table "Before the stages", F:2076-2090; order confirmed (src)
CPP:3327-3353, VFI:36-53, CPP:843-850):

| step | test | name | line |
|---|---|---|---|
| B1 | read `policy.txt` | unreadable: exit 2, role `policy` | F:2092-2101; VFI:38 |
| B2 | read `KL.bin`; its length is a multiple of 4 bytes | `KL-length` (role `KL`) | F:2081; VFI:40-41 |
| B3 | `layout.txt`: if the name exists it must be readable; if it does not exist nothing is rejected here (every stage rejects later under `plan-layout`) | role `layout` | F:2082; VFI:42-45 |
| B4 | read `key.bin` | role `key` | CPP:3328 |
| B5 | `policy.txt` has fewer than 2^32 bytes; `KL.bin` has at least 8 words; `layout.txt` has fewer than 2^32 bytes | `close-list-long`; `KL-length`; `close-list-long` | F:2080-2081; CPP:843-848 |
| B6 | `policy.txt` begins with the eight bytes `"version "`, four characters and a line feed, and the four characters are the program's version word (R4.3) | `version-unknown (policy)` | F:2083; CPP:3222-3227 |
| B7 | `key.bin` has at least 8 bytes | `cp-key-length` | F:2084; VFI:26 |
| B8 | first four bytes of `key.bin` are `CPIK`, the next four the version word of `policy.txt` (R13.1) | `cp-key-head` | F:2085; VFI:27 |
| B9 | lengths of request file then token file, by `stat` (1.4) | `statement-required`, `statement-range` | F:2086; CPP:3343-3344 |
| B10 | read the request file, then the token file | roles `request`, `y` | CPP:3345-3346 |
| B11 | the four tests (a) to (d) of `policy` (2.5) | `policy` | F:2087; CPP:3348 |
| B12 | read the proof file; it has at least 12 bytes | role `proof`; `cp-proof-length` | F:2088; CPP:3349, VFI:50 |
| B13 | first four bytes `CPPF`, next four the version word of `policy.txt` (R14.2) | `cp-proof-head` | F:2089; VFI:51 |
| B14 | k = bytes 8 to 11; `leaf/<k>.bin` is a regular file that can be read | `cp-entry-missing` | F:2090; CPP:3352-3353 |

Notes:

- An unreadable input is no rejection: one line
  `input-unreadable-<role>: <the file> cannot be read: <reason>` on standard output, no line
  `NO:`, exit code 2. `<role>` is `policy`, `KL`, `layout`, `key`, `request`, `y`, `proof`, and
  `entry` for the leaf file of the part-call `-leaf`. The file is named by its role, never by its
  path (F:2092-2101, F:2678; (src) VFC:302-312).
- The leaf file of a whole call is the one exception: k is the proof's word, not the caller's, so
  a missing file is a rejection (`cp-entry-missing`) (F:2090, F:2101).
- B9 comes before B10: a wrong length gives exit code 1 "even if one of these three files is
  missing or unreadable" (OUT:282-286).
- A rejection before the stages prints no heading: its last line, and under `policy` the line
  before it, are all (F:3006-3007).

### 3.3 Phase C — every stage: the public files (13.4)

"Each of the three stages begins with the same steps on the three public files. Until they are
done, a stage cannot read the key file, the leaf file, the request file, the token file or the
proof file. So the number, kind and length of everything in a file is fixed before a request is
known, but for the length of an opening." (F:1711-1714) All three stages make these tests on the
same bytes, "so a call with such a fault is rejected by the stage key, the first in the order"
(F:2103-2104).

The eight steps (F:1716-1804):

1. **The parameter file.** Frame lines `version` to `table` by their parser (section 8). The other
   lines in one order and one encoding: `prof` to `F` in the order of R15.5; then the optional
   lines, each at most once, in the order `lidb`, `nminH` (only directly after `lidb`), `eg`,
   `smax`, `rcl`, `gcl`, `xl`; then the 32 digest lines, all or none; then the call lines `call`,
   `callA`, `callH`. The verifier writes each value into its own statement as it goes
   (F:1716-1721).
2. **The scale file.** For each of the L layers a record of 13 words: kq, kk, kv, ko, kg, ku, kd,
   M1, K1, M2, K2, sh, rp. After all layers, with routed experts, three words kr, kgR, kuR for
   each layer with an odd number, counted from 0 (F:1722-1724).
3. **The shape.** The numbers of the statement are tested one by one and together, the
   no-overflow conditions among them (F:1725-1728).
4. **The public tables.** Compute (or take as data, R15.3) the four tables, take K(72; table) of
   each, write the digest into the statement, reject if the file's line differs (F:1729-1734).
5. **The segments.** NG = L / 2^ll groups of layers. For g = 0 .. NG - 1: the feed-forward segment
   G_g and directly after it the attention segment A_g; the head's segment H is last. Identifiers:
   1 + g for G_g, 2 + NG + g for A_g, 1 + NG for H; these are the item `links' identifiers`.
   G_g and H leave a row on the stored table, A_g none, so `pending rows` is NG + 1. The last
   segment has one plain scalar, the next token (F:1735-1743).
6. **The arrays.** Each segment commits to arrays in moments: first the packed arrays `M<i>` of
   the segment's own matrices (first those that no other sub-proof reads, then those that one
   does); then one moment for each vector over E (`U3` alone); last `ZZ` and `BZ`. The layout file
   numbers the arrays of a moment in this order, from 0 (F:1744-1750).
7. **The layout file.** Two kinds of line. Group's line `link moment group class rows life`
   (class `N`, `B` or `W`). Block's line `link moment group array R a K e low row place br bj 0`:
   element x = c 2^a + i (`low` = `r`) or x = i 2^e + c (`low` = `c`) is in row
   `row` + (x >> bj) at position `place` + (x mod 2^bj); br + bj = a + e. Segments, moments and
   groups are counted from 1; arrays, rows and positions from 0. Blank lines and lines beginning
   `#` are skipped; all groups' lines are taken first, then all blocks' lines. The parsed layout
   is encoded again, canonically, as the item `layout` (R14.5); the file's bytes enter the
   configuration's digest as they are, so two encodings of one layout give two commitment IDs
   (F:1751-1801). The programs read each line with `sscanf`, so signs, leading zeros and missing
   blanks pass; "A second verifier that admits the plain encoding alone rejects some files that
   `cp_verify` admits" (F:1788-1796).
8. **Sizes and plans.** "One routine takes the bytes of the three files, in the order of R4.9, and
   the sub-proofs' shapes, and derives every size and the plan of every round of key file, leaf
   file and proof file (section 8). The stages take its result alone (R0.5)." (F:1802-1804)

The tests on the public files, in the order of the table "On the public files, in every stage"
(F:2106-2210; "roughly in the order of a run", F:2056-2057). Conventions of that table: a bare
name is the number of the line of that name; a name without `_lo`/`_hi` is low + 2^32 high;
T = 2^lt; "with experts" means NE above 0 (F:2058-2060). `[cf]` = the page says it cannot fail.

| # | name | what must hold | F line |
|---|---|---|---|
| C1 | `parameter-<name> (policy)` | frame lines `version` to `table` admitted by their parser (section 8); the name is the parser's | 2108 |
| C2 | `statement-required` | line `prof` there with a value 16 to 31, line `toksrc` there with value 1 ("there" = some line begins with the name and one blank, and the first such line has one to ten digits and nothing else) | 2109 |
| C3 | `policy-name-lt` | the line `lt` is there | 2110 |
| C4 | `shape-words` | lt from 4 to 16 | 2111 |
| C5 | `header-version` | the version word in the statement is the program's [cf] | 2112 |
| C6 | `policy-line-long` | no line after the frame lines has more than 1023 bytes, line feed counted | 2113 |
| C7 | `policy-zero-byte` | no line holds a zero byte | 2114 |
| C8 | `policy-line-<i>` | the i-th name of R15.5's list (2 for `prof`; `la` is 29, `MF` is 74): a name and a number below 2^32, nothing after | 2115 |
| C9 | `policy-name-<name>` | each line `prof` to `F` has the name due in R15.5's order; ends with the name that was due | 2116 |
| C10 | `policy-line-form` | one encoding: printable name without a blank, one blank, decimal numeral without sign or leading zero, at most ten digits, below 2^32, one line feed; also any line with more than 19 digits in a row | 2117 |
| C11 | `parameter-table-shape (policy)` | i and m of the line `table` below 2^32 [cf] | 2118 |
| C12 | `policy-work-most` | no proof-of-work number of the lines `work` above 32 | 2119 |
| C13 | `policy-leafd` | `slots` at most 256 (binding tree's depth at most 8) | 2120 |
| C14 | `policy-cert-words` | no line `clt`, `clns` or `cms` | 2121 |
| C15 | `policy-lidb` | optional `lidb`: first of the optional lines, once, above 22 | 2122 |
| C16 | `plan-identity-cap` | lidb at most 30 | 2123 |
| C17 | `policy-nminH` | optional `nminH`: directly after `lidb`, once, 2 to 28, above nmin | 2124 |
| C18 | `policy-gate-table` | optional `eg` (4 to 7) then `smax` (2047, 1023, 511 or 255), once each, in position | 2125 |
| C19 | `policy-rcl` | optional `rcl`: value 1, once, in position | 2126 |
| C20 | `policy-gcl` | optional `gcl`: value 1, once, in position | 2127 |
| C21 | `policy-xl` | optional `xl`: value 5, once, in position | 2128 |
| C22 | `policy-tables` | the 32 lines `tsilu0` to `texp7`: all or none; before the first call line; directly one after another in R15.2's order; each one word; only with NE above 0 | 2129 |
| C23 | `policy-call-line` | every other line is a call line: ends with a line feed; tokens separated by single blanks, none empty, bytes A-Z a-z 0-9 . _ - only; second token (the call's name) at most 8 characters; at least four tokens; first is `call`, `callA` or `callH`; the three kinds in this order | 2130 |
| C24 | `policy-length` | all lines `prof` to `F` are there | 2131 |
| C25 | `hid-tau` | tau a multiple of 32 from 32 to 256, and tau less the largest power of two not above it is 0 or a power of two | 2132 |
| C26 | `hid-hb` | sec from 1 to 4096 [cf]; second test at an attention sub-proof's plan [cf] | 2133 |
| C27 | `policy-tau-hb` | tau at least sec | 2134 |
| C28 | `hid-planes-<call>` | a constant of every lookup call is 5 [cf] | 2135 |
| C29 | `statement-length`, `header-magic`, `policy-profile` | prof 16 to 31 [cf]; the other two are tests on the statement the verifier built itself | 2136 |
| C30 | `policy-profile` | prof is 20 | 2137 |
| C31 | `shape-words` | lt 4 to 16; ll 1 to 6; d and f 1 to 2^20; with experts fe a power of two, f = 2 fe, and not both ll = 1 and fe = 1 | 2138 |
| C32 | `shape-L` | L not 0 and a multiple of 2^ll | 2139 |
| C33 | `shape-groups` | 2 + 2 L / 2^ll below 2^16 | 2140 |
| C34 | `plan-groups-base` | at most 28 groups of layers: 2 + 2 L / 2^ll at most 59 | 2141 |
| C35 | `shape-la` | lt < la <= 16; 2^(la - lt) divides d, f, fe (with experts), G dh and (H + G) dh; lmq >= la; lmaf >= la | 2142 |
| C36 | `policy-norm` | eps1 and eps2 from 1 to below 2^59 | 2143 |
| C37 | `shape-heads` | H, G, dh not 0; dh a power of two, at least 2; H dh = d; H + G <= 64 | 2144 |
| C38 | `policy-cs` | cs is 12 | 2145 |
| C39 | `header-absent-class` | without experts hr is 0 | 2146 |
| C40 | `policy-forms` | hq, hv, ho, hgD, huD, hdD, and with experts hr, at most 2 | 2147 |
| C41 | `policy-ut` | ut is 1 | 2148 |
| C42 | `shape-D` | D is 2048 or 32 (two tests: power of two from 2 to 4096 where the sub-proofs' layout is derived; 2048 or 32 where the committed matrix's layout is made) | 2149 |
| C43 | `shape-NE` | with experts NE a power of two from 2 to 4096 | 2150 |
| C44 | `policy-gcl` | gcl there only with experts | 2151 |
| C45 | `policy-rcl` | rcl there only with experts | 2152 |
| C46 | `shape-request-matrix` | lmaf, lmad, lmar, lmq from lt to 24; NAf, NAd from 1 to 64; lmx from la to 24 | 2153 |
| C47 | `plan-tensor-layout-fill-<arr>` | the tensors of a request matrix cover each feature once; `<arr>` is `stream` or `qa` [cf] | 2154 |
| C48 | `policy-call-list` | lines `call`: at most 8; each a name, a kind and at least one call's segment; no two with one name; none named V, a, b or E; each named call's segment is present in this form of the model, has the call's kind and is in exactly one call; every present call's segment is named | 2155 |
| C49 | `shape-lmb` | lmb at most 24 | 2156 |
| C50 | `shape-words` | nmin at most 28 | 2157 |
| C51 | `shape-call-<call>` | for each call q with 2^n_q keys: iota_q below 2^31; n_q at least 10, at least la, at most 44; its columns at least 2^(la - lt); iota_q = n_q - dT, dT the least of lidb (22 if absent) and all n_q. (`hid-call-floor`: repeats of n_q >= 10 [cf]) | 2158 |
| C52 | `forest-depth-G` | depth of a tree of a feed-forward lookup forest at least la | 2159 |
| C53 | `header-absent-call` | iota_q is 0 for every q from the number of calls up to 7 | 2160 |
| C54 | `KL-length` | `KL.bin` has exactly 13 L words and, with experts, 3 more for every second layer | 2161 |
| C55 | `KL-shift-range` | each shift kg, ku, kd, kq, kk, kv, ko (and kr, kgR, kuR with experts) is from 1 to 16, 24 or 32 as the line of its class (hq to hr) is 0, 1 or 2 | 2162 |
| C56 | `KL-kq-kk` | kq and kk equal, or both at least 16 | 2163 |
| C57 | `KL-norm` | both norms of a layer: 24 <= M <= 47, 17 <= K <= 32, K + 14 >= M | 2164 |
| C58 | `KL-rp` | rp is 0 or 1 | 2165 |
| C59 | `table-digest-silu`, `table-digest-sigmoid` | computed tables have the digests K(72; table) of `tsilu0..7` and `tsig0..7`, where the file has these lines | 2166 |
| C60 | `header-absent-hash` | without experts the sigmoid digest's position holds zeros [cf] | 2167 |
| C61 | `no-wrap-<name>` | the feed-forward segments' no-overflow conditions, in 128-bit integers, from the lines and `KL.bin`. `<name>`: U-`<site>`, W-`<site>` (sites gate, up, norm, down, qk, o, v, lr, xr), guard-radix, guard-radix-FS, guard-radix-clamp, guard-radix-gate-clamp, guard-flag-gate-clamp, clamp-keys, MR, one-hot, linear, ledger, ledger-eps. Single conditions: 11.2, second half | 2168 |
| C62 | `header-absent-kind` | the line `wb_..` of an absent weight kind is 0 | 2169 |
| C63 | `policy-weight-kind` | each present line `wb_qk` to `wb_r`, and `wb_head`, is 13; `wb_emb` from 2 to 31 | 2170 |
| C64 | `shape-V` | V from 2 to 2^24 | 2171 |
| C65 | `policy-weight-width-emb` | wb_emb is 21 | 2172 |
| C66 | `hid-vocab-cols` | the least c with 2^c >= V is at most w, the last number of the line `table` | 2173 |
| C67 | `w-list-token-factor` | the vocabulary's index fits the column variables of the committed matrix [cf] | 2174 |
| C68 | `shape-words` | where the committed matrix's layout is made (11.5): L 1 to 4096; d, dh, G dh, H dh, f 1 to 2^24; with experts fe, NE likewise; V 1 to 2^24 [cf]; `w-shape-lk`, `w-shape-mW` are raised here too | 2175 |
| C69 | `shape-theta0` | theta0 not 0 | 2176 |
| C70 | `table-digest-rope` | the computed rotary table has the digest of `trope0..7` | 2177 |
| C71 | `policy-norm-F` | 24 <= MF <= 47; 17 <= KF <= 32; KF + 14 >= MF; 1 <= epsF < 2^59 | 2178 |
| C72 | `policy-toksrc` | toksrc is 1 [cf] | 2179 |
| C73 | `policy-gap-words` | the tests of 2.2 | 2180 |
| C74 | `shape-request-matrix-H` | la <= lmhf <= 24; 1 <= NHf <= 64; lt <= lmhd <= 24; lt <= lmhr <= 24; lmbH <= 24 | 2181 |
| C75 | `policy-call-list-H` | lines `callH` (or the six of R15.6): at most 6; no two with one name; each of the nine call's segments NF NFH HD0 HD1 ROW HD2 CNF HE0 HE1 in exactly one call of its kind; no other call's segment named | 2182 |
| C76 | `shape-call-H-<call>` | for each call q of `callH`: n_q at least 10, at least la, at most 44; columns at least 2^(la - lt); iotaH_q = n_q less the depth of a tree of the head's lookup | 2183 |
| C77 | `forest-depth-H` | depth of a tree of the head's lookup forest at least la | 2184 |
| C78 | `header-absent-call-H` | iotaH_q is 0 for every q from the number of calls up to 5 | 2185 |
| C79 | `no-wrap-H-<name>` | the head's no-overflow conditions. `<name>`: U-NF, W-NF, W-HD0, three-digits, HE, Z, E2, E3, E4, J-E, guard-radix. Single conditions: 11.4, second half | 2186 |
| C80 | `policy-call-list-A` | lines `callA`: at least one, at most 12; kind KR, KFD, R16 or WH; no two with one name; each call's segment one of RM RD FM FD WL WH IX; at most 12 calls after expansion by shift | 2187 |
| C81 | `af-shape-heads` | G a power of two that divides H | 2188 |
| C82 | `shape-request-matrix-A` | lt <= lmh <= 24; lt <= lmo <= 24; lmbA <= 24; lmS <= 24; 1 <= NAs <= 64 | 2189 |
| C83 | `af-policy-wd` | S below 32 | 2190 |
| C84 | `policy-iotaA` | iotaA_0 is 32 plus the depth of a tree of the attention sub-proof's lookup forest, in every group of layers | 2191 |
| C85 | `plan-tensor-layout` | feed-forward (owner of qa) and attention (reader) list the same tensors q, kx, v, o with the same numbers; Lam, H dh, G dh, la - lt the same on both sides; 2^(la - lt) divides dh; the four tensors have H dh or G dh features | 2192 |
| C86 | `table-digest-exp` | the computed softmax table has the digest of `texp0..7` | 2193 |
| C87 | `shape-product-layer`, `shape-product-layer-H` | each product layer has at least 9 variables | 2194 |
| C88 | `policy-sym-readers` | each symbol tree a feed-forward sub-proof owns is planned for one reader more than the number of outside readers; head and attention: one reader, and they own no tree another sub-proof reads | 2195 |
| C89 | `plan-layout`, `plan-mask-row` | every array a segment reads is placed by the layout file and still kept; the mask rows have room: scalars plus answers at most the entries of a message of the request's mask code, and the index-mask message has room for the rows on the table with their batching | 2196 |
| C90 | `plan-link` | every committed array of a segment has exactly one name; the lists of its arrays have equal lengths | 2197 |
| C91 | `plan-link` | a smallness test has fewer than 256 matrices [cf] and at least one is the segment's own and read by no other; the arrays committed at a moment are exactly the layout file's at that moment | 2198 |
| C92 | `plan-fold-source` | a matrix read from an earlier segment belongs to an earlier feed-forward segment, is listed there as read by others, with the same rows and columns | 2199 |
| C93 | `plan-layout` | `layout.txt` is there, is read without a fault, fits the arrays the sub-proofs declare and fits the codes | 2200 |
| C94 | `plan-link` | the number of segments with claims on the weights is NG + 1 | 2201 |
| C95 | `parameters-not-admitted` | the frame lines are admitted together with the sub-proofs' shapes | 2202 |
| C96 | `plan-layout` | each line not skipped is a group's line or a block's line, with nothing after its last field | 2203 |
| C97 | `plan-layout` | block's line: `link`, `moment`, `group` not 0; `link`, `moment`, `group`, `array` below 2^20; the letter is r or c; the last number is 0; a, e, br, bj below 48 | 2204 |
| C98 | `plan-layout` | group's line: `link`, `moment`, `group` not 0 and below 2^20; class N, B or W; rows 1 to below 2^32; life below 2^20, and not 0 exactly in class B | 2205 |
| C99 | `plan-layout` | a group is in a segment and moment the request has; groups of a moment numbered in turn; moments and segments in turn; the first oracle message of a segment is not kept | 2206 |
| C100 | `plan-layout` | a block is in a group the file has and belongs to an array of its moment; E arrays in rows over E, F arrays in rows over F; kept as long as its last reader needs; all blocks of an array in one group; every array has a block | 2207 |
| C101 | `plan-layout` | br + bj = a + e; `R`, `K`, `row`, `place` below 2^48 and multiples of 2^a, 2^e, 2^br, 2^bj; a block inside its array, its message's rows and a row's message; blocks of an array do not overlap and hold each element once; no two blocks of one message share an entry; no block covers a pad of the message's out-of-domain sample | 2208 |
| C102 | `plan-head`, `plan-link`, `plan-shape` | one head's segment, the last; identifiers distinct, each with a plan; 2 to 64 segments [cf] | 2209 |
| C103 | `parameters-not-admitted` | the three files and the sub-proofs' shapes are admitted by the routine that derives every size and plans every round (section 8); the stage's line before its last gives the reason | 2210 |

Further names raised "where the plans of the sub-proofs are made, in every stage, or inside a
sub-proof of a segment, in the stage request" (F:2297-2302, table F:2304-2341): section 4.3.

Three kinds of public-file test, which the tables do not separate (F:1590-1622):

- (a) tests that give a relation its meaning or a round its error: the names with `no-wrap`,
  `no-wrap-pin-forest`, `forest-keys`;
- (b) bounds on sizes with no such reason: `forest-calls` (16), `forest-trees` (256), `slots` at
  most 256 (`policy-leafd`). A verifier that admits more differs from `cp_verify` only on files
  that `cp_verify` rejects, "But this page says nothing on such sizes, so the duty holds for these
  bounds too";
- (c) the ten conditions on hiding (16.1): `cp_verify` rejects a configuration that misses one
  (`parameters-not-admitted`; part (a) of condition 3 under `plan-mask-row`). They are a
  committer's and prover's duty, not a verifier's, except three parts asked of every verifier:
  part (a) of condition 3 (room in a segment's mask row), part (d) of condition 3 (the shared
  split's mask message has a free entry), and the fourth line of condition 6
  (i >= m0 2^(w_T - b) + 3 S: the weights leave the pads' positions free).

"This page does not sort every name of 13.8 into these kinds, so the duty is on all of them but
(c), and on the three parts of (c) that are named there" (F:1619-1620).

### 3.4 Phase D — every stage: the commitment ID (13.5)

Depends on: Phase C (configuration's digest, table's shape). Reads: the beginning of `key.bin`.

1. Read the beginning of `key.bin` for its form (R13.2): the head (8 bytes), the root (32 bytes),
   the record's stored answers (24 bytes each). "Each of the table's 2^v rows (v: R4.10) has the
   same number of stored answers, and each answer is a canonical element of E." (F:1808-1810)
   Failure: `key-refused`, in every stage (F:2216).
2. From the root, its own configuration's digest and its own shape of the table, form the
   anchor's name (R4.10) (F:1810-1811).
3. From the name, sample the record's seeds (R4.8), "which are in no file" (F:1811-1812).
4. From the configuration's digest, the name, the seeds and the stored answers, form the
   commitment ID (R4.11) (F:1812-1813). The hash input, in 13.2's words (F:1647-1657): the
   configuration's digest; the anchor's name as a string of bytes (the word 112, then the name's
   112 bytes, which hold the configuration's digest a second time); the list of the elements of
   the record's seeds (one flat list, their number as a word before them, no word before any
   seed); the list of the record's stored answers (their number as a word before them); and an
   empty list (the word 0). The configuration's digest takes the three public files in the order
   `policy.txt`, `layout.txt`, `KL.bin` (R4.9).
5. Compare the ID, as 64 lower-case hex digits (the digest's 32 bytes in order, two digits each),
   with the caller's, in which capital letters count as small ones; reject if they differ:
   `model-statement` (F:1813-1815, F:1655-1657).

Facts:

- "This comes before the stage looks at anything else of key file, leaf file, request or proof
  file, and it is the only test of a stage in which the caller's ID meets the files."
  (F:1815-1817)
- "Nothing of the key file's proofs, of a leaf file, of the request or of the proof file enters
  the ID." (F:1818-1819)
- Without `-id` nothing is compared, every other test is made, and the call cannot end with an
  acceptance (F:1819-1821).
- The parent compares the stages' IDs with one another and with the caller's once more, as a guard
  on itself: `internal-id-two-ways` (F:1817-1818; (src) CPP:2878-2885).
- `h_par=` prints the same configuration's digest word by word (each 32-bit word most significant
  digit first); it is compared with nothing (F:1654-1657).
- Under `model-statement` the call prints three lines and nothing else (section 5.5).

### 3.5 Phase E — the three stages (13.6)

| stage | reads | steps after Phases C and D | line |
|---|---|---|---|
| key | `key.bin` | error accounting of the key file's plan; conditions 2, 4 and 13 of 13.7; every test on the whole file (section 9) | F:1835 |
| leaf | `key.bin` (its beginning only); the leaf file | error accounting of the leaf file's plan; conditions 2, 4 and 13; every test on the whole leaf file, against the anchor's root and stored answers | F:1836 |
| request | `key.bin` (beginning only); the leaf file (beginning only); request file; token file; proof file | the tests of 12.2; the digest of the request, which completes the statement; the beginning of the leaf file for its form (head, root, stored answers: R13.3); error accounting of the proof's plan; conditions 2 and 7 to 13; every test on the whole proof | F:1837 |

**The error accounting** (F:1839-1847): every round's error, proof of work counted, must be at
most 2^-sec, and sec must be at least the requested bits: `security-bits`. "It reads no byte of
key file, leaf file or proof file." It also notes whether a round needs its proof of work. The
first half cannot fail at this point (the planning routine has already rejected such a plan under
`parameters-not-admitted`); the program's condition has a third part, "some round of the plan has
an error above 0" (F:2218).

**Stage key** (src order: CPP:2272-2296): `security-bits`; then every test on `key.bin` from its
first byte to its last -> `key-refused`, with the reason and where in the file in the stage's line
before its last (F:2219); then the form condition `two-codes`; last line `STAGE PASSED: key`.
A key file has three chains in this order: one-time chain (32 random bytes, then rounds), the
slot (the word 0 and a salt: a binding tree of depth 0), shared chain (no random bytes), second
chain (32 random bytes) (R13.2, F:978-990, F:1003-1005).

**Stage leaf** (src order: CPP:2272-2296): `security-bits`; then every test on the leaf file
against the anchor as read from the beginning of `key.bin` -> `entry-refused` (F:2220); form
condition `two-codes`; last line `STAGE PASSED: leaf`. A leaf file has one chain, the link's
chain (R13.3, F:1012-1014).

**Stage request**, in order (F:2221-2231 with (src) CPP:2298-2535):

| step | what | name on failure | line |
|---|---|---|---|
| E1 | 12.2 tests 1 to 4 on the caller's two files (order in 1.4) | `statement-required`, `statement-range` | F:2221-2223 |
| E2 | y below V | `token-range` | F:2224; CPP:2309 |
| E3 | digest of the request TK(all T + 2 words) into statement words 163..170 | (none) | F:1837; CPP:2316-2318 |
| E4 | every one of the T tokens below V | `token-range` | F:2224; CPP:2321-2322 |
| E5 | the beginning of the leaf file has the form of R13.3: head (`CPEN`, version word), root, the record's stored answers | `entry-refused` | F:2225; CPP:2343-2346 |
| E6 | error accounting of the proof's plan | `security-bits` | F:2218; CPP:2359 |
| E7 | evaluate conditions 7 to 13 of 13.7 (they do not reject; a miss is named in the stage's line `result:`) | (none) | F:2024-2027; CPP:2365-2408 |
| E8 | form the item `request` (the statement with word 171 = 0) and the item `the request file's words` | (none) | CPP:2431-2432, CPP:2470-2471 |
| E9 | read the proof, items 1 to 8 below | `proof-refused`; `reply-differs`; names of the sub-proofs | F:2226-2231 |

E1 to E5 come before E6 in the source; the table of 13.8 lists `security-bits` before them. For
the two parts of that test which the page describes, the call's name is not affected: the first
cannot fail at this point and the second (sec against the requested bits) is the same in all
three stages, so the stage key finds it first (inference from F:1887-1888 and F:2218).

**The proof is read by one reader from its first byte to its last, in this order** (R14.1;
F:1869-1883):

1. the head, 12 bytes; "the number in it must be the k of the leaf file whose table is used"
   (reason `the proof was made on another stored copy of the table`, F:2274);
2. the first chain. Its first query has the label 0x46524d01 and the items of R14.3: `table`
   holds the root and stored answers of the **leaf** table, `stored copy` holds k, `request` is
   the statement, `the request file's words` holds the request file whole. "Then come the
   segments, each with its sub-proof (sections 10 and 11), to the end of their last proximity
   test";
3. the comparison of the next token (1.8) -> `reply-differs`;
4. the rows that the segments leave on the stored table, joined into one; the request's own
   vector (W); the first chain's seal;
5. the request's slot in its batch, "which with the seal gives the binding tree's root (R14.7)":
   one word below 2^depth, the salt of the slot's leaf, depth digests (sibling of the leaf first)
   (P10:263-269; reason `the request's place in its batch`, F:2276);
6. the shared chain (R14.9; label 0x46524d03, no random bytes in the file, the binding tree's
   root is used instead: P10:276, P10:284-287): the test on the leaf table, its proximity tests,
   its seal;
7. the second chain (R14.10; label 0x46524d04, P10:308-311), whose statement is the two seals
   (the first chain's, then the shared chain's); its proximity tests;
8. the end of the file: "no byte is missing and none is left over".

Loops and dependencies inside the stage request:

- **Per chain** (three chains; seven over the three files, F:4818-4819): form the first query
  from Phase C's values and the file's leading items; a chain whose run's value is 32 zero bytes
  is rejected (R4.5; F:2259); a chain that holds the seal of a rejected chain is rejected from its
  start (F:2260, F:4860-4863).
- **Per segment** (2 NG + 1 segments in the order G_0, A_0, .., G_(NG-1), A_(NG-1), H; F:1735-1737):
  the segment's `SEND seed`, its `SEND answer` or `LOC`, its sub-proof and later moments, its
  `BAT`, `FOLD epsilon` and `FOLD round`; only then the next segment (P10:327-331). Names inside a
  sub-proof are printed after its prefix and a colon, as in `G0:`, `A11:`, `H:`; some
  (`coin-zero`, `header-y`, `chain-refused`) are printed bare (F:2300-2302).
- **Per round**: tests of form only. "While the rounds of a chain run, a verifier rejects only for
  form: a value that is missing or not canonical, a failed proof-of-work test, a listed position
  that differs. No equation is tested in a round." (F:2415-2417) The verifier forms rows instead;
  "At a group's end all its rows are batched into one, the group is folded, and what is left goes
  into the next group" (F:2420-2421).
- **Per round that samples positions**: nonce, listed positions, stored trees' openings, the
  chain's own trees by place, next message (R8.7; F:1101-1102); every opening must lead to its
  root (test 1 of 13.9).
- **After the last segment's proximity test**: the next-token comparison; if `pending rows` is
  above 1, `BAT-sigma` and a sumcheck with k_col variables that joins the rows; then `SEND seed`
  and `SEND answer` for W; then `SEAL` (P10:239-245). With the programs `pending rows` is NG + 1,
  at least 2 (F:4005-4006).
- **Depends on**: the request stage needs Phase C (plans, shapes, statement words 0..170 but the
  request digest), Phase D (anchor's beginning, for the ID only), the leaf file's beginning (root
  and stored answers for the item `table`), k from the proof's head, and the caller's two files.
  It needs nothing from the stages key and leaf (F:1658-1662).

"`cp_verify` always checks a proof on a leaf table, that of the leaf file `leaf/<k>.bin`, with k
from the proof's head, also for k = 0. It never checks one on the anchor" (F:1663-1665). "A
verifier that checks a proof alone has checked nothing about the table." (F:1662)

### 3.6 The tests on content (13.9)

"In the frame, that is, outside the sub-proofs, the tests on content are these five, and no
others, beside the tests of form of 13.8" (F:2423-2424):

1. every opened leaf, with its path, leads to the root that was sent, and every opened column of
   a stored table leads to the root in the chain's first query, and no vertex of a tree gets two
   values under one root (R7.14) (F:2433-2435);
2. at the end of each proximity test, in `BASE`, before the stage's positions are sampled: the
   masked message M' that the prover sends in the clear satisfies
   < c, M'_main > + < d, M'_mask > = target* + lambda target (F:2436-2440);
3. in `BASE`, at every position of the list and for both rows: the encoding of M' with its
   randomness R' equals the opened symbol of g* plus lambda times the opened symbol of the row; a
   mask row is read at the position modulo its length (F:2441-2443);
4. the next token is the caller's (F:2444);
5. every chain was brought to its end, and none has rejected (F:2445-2446).

Three tests of form that are "easy to miss" (F:2425-2427): no chain's run's value is 32 zero
bytes (R4.5); the number in the proof's head is that of the leaf table that is read (R14.2); the
slot is below 2^depth (R14.7). The slot is tested for its form alone: seal, salt and path give
the binding tree's root, which enters the shared chain's first query (F:2448-2449).

Inside a sub-proof: `header-y` and the tests on sampled values (F:2430-2431).

**Sampled values at which no verifier gives an acceptance** (F:2451-2475). "A verifier with two
answers (R0.3) rejects. `cp_verify` rejects at event 1; at the others it ends with `NOT CHECKED`
and the name in the table, after the sub-proof's prefix" (F:2460-2462).

| no. | event, in one segment | name in `cp_verify` | defined in |
|---|---|---|---|
| 1 | the element eps of the second token sumcheck is 0 | `coin-zero` | 11.2, step 9 |
| 2 | all tau entries of a column of the sampled matrix Theta are 0 | `internal-f-table-read` | 11.1, third piece, event 1 |
| 3 | colw_mu(c) = 0 for a column whose entries are not all 0 | `internal-f-table-read` | 11.1, third piece, event 1 |
| 4 | chi = 0 | one of these names, or `internal-f-tie-weights` | 11.1, third piece, events 2 to 4 |
| 5 | two row weights rw_mu(i') of one matrix are equal | `internal-sym-rowvec` | 11.1, third piece, event 4 |
| 6 | a weight of the join on `ZZ` is 0 | `internal-t2f-untiled`, `internal-t2f-untyped-` | 11.1, third piece, events 2 and 3 |
| 7 | a weight on a column of `BZ` is 0 | `internal-t2f-untyped-` | 11.1, third piece, event 2 |
| 8 | the weight of an entry of `U3` is 0, or the weight that the claims READ_q put on a column of `ZZ` is 0 | `internal-t2f-untyped-` | 11.1, third piece, event 2 |
| 9 | the coefficient of a scalar in the sum of all claims is 0 | `internal-g-free-slot`, `internal-a-free-slot`, `internal-h-free-slot` | second halves of 11.2, 11.3, 11.4 |

All nine give the format a completeness error (F:2492-2494). Event 2 is the most likely: about
2^-109.3 for a full-size proof (F:2503-2507).

### 3.7 The rows a verifier forms (13.9) — index

13.9 gives every coefficient and target a verifier must form (R0.4), in seven tables. Their
detail belongs with sections 9 to 11; the index, for completeness:

| table | rows on | line |
|---|---|---|
| out-of-domain samples and sumchecks, in every chain | round `SEND seed` (the cube of an oracle message; the pad of answer i); round `SEND answer` (one row per answer); a sumcheck with a hiding sum (one row; one claim per shown map) | F:2550-2558 |
| a key file's one-time chain: the proof of ranges | each lookup (padding's public factor, the tie, product trees, `LINE`, leaves, the bit test, the row without a message, claims on keys, row on the committed matrix) | F:2560-2576 |
| the rows on the committed matrix (one-time chain; first chain) | after each segment with claims on the weights; the joining sumcheck (`BAT-sigma`); the own group with W, row (Eval) | F:2578-2584 |
| the shared chain and the second chain | the record's rows on the folded row; `LOC`; `LIN zeta` row (Fold); the split with a masked share; row (Dot) | F:2586-2594 |
| a leaf file: the link | rows on both folded rows; `LINK`; `LINK phi` equality row | F:2596-2602 |
| a segment of a proof file's first chain | the sub-proof's one equation; placement of members' rows; `BAT`; `FOLD epsilon`/`FOLD round`; what a closed group leaves; `LOC`/`CS`; the switch's rows | F:2604-2615 |
| a proximity test | stage i batching order; `BASE` | F:2617-2622 |

The sumcheck round rule: "the verifier fills in q_1 = claim - 2 q_0 - q_2, so that
q(0) + q(1) = claim, and the new claim is q at the sampled value g_j. No test is made here."
(F:2611)

### 3.8 Phase F — from the stages to the result (13.7)

"The call rejects if any stage rejects. Its rejection name is that of the first stage that
rejected, in the order key, leaf, request. It accepts only if all three stages have passed, have
formed the same commitment ID, and that ID is the caller's, and only if the conditions below
hold." (F:1887-1890)

A missed condition "says nothing against the proof". `cp_verify` makes every test all the same
and, if none fails, ends `NOT-A-VERIFICATION`, "but for conditions 3, 5, 6, 11 and 14, where it
rejects; a verifier with two answers rejects" (F:1897-1902).

| no. | condition | name in `cp_verify` | where asked | effect of a miss in `cp_verify` | line |
|---|---|---|---|---|---|
| 1 | the caller has named a commitment ID and it is the one the stages form | `id-named` | the call | `NOT-A-VERIFICATION` | F:1904-1906 |
| 2 | the error accounting of each of the three plans is made with at least 128 requested bits (so `sec` >= 128 and every round's error, proof of work counted, <= 2^-128); above 128 is refused; "128 is the only number of requested bits under which a call can end with an acceptance" | (no name: prints that fewer than 128 bits were requested) | every stage, and the call | `NOT-A-VERIFICATION` | F:1907-1921 |
| 3 | the line `reading` is 1 | (parser) | parser | `NO` | F:1922-1923 |
| 4 | every closeness term in the plans of key file and leaf file rests on the bound within a third of a code's distance or on the theorem on codes; "That holds by the derivation: no verifier tests it" | (none) | (none) | (none) | F:1924-1938 |
| 5 | each of the fifteen numbers of the lines `work ..` is at most 32 | `policy-work-most` | every stage | `NO` | F:1939-1944 |
| 6 | `prof` is 20 | `policy-profile` | every stage | `NO` | F:1945 |
| 7 | `toksrc` is 1 | `prompt-source` | request | rejected earlier | F:1946-1947 |
| 8 | the lines `rcl 1` and `gcl 1` are both there | `both-clamps` | request | `NOT-A-VERIFICATION` | F:1948-1949 |
| 9 | KF <= MF, and K1 <= M1 and K2 <= M2 in every layer's record | `norm-shifts` | request | `NOT-A-VERIFICATION` | F:1950-1954 |
| 10 | the 32 lines of the tables' digests are there | `table-digests` | request | `NOT-A-VERIFICATION` | F:1955-1957 |
| 11 | the acceptance policy, four parts: (a) sT = sh - 4; (b) if r < T - 1, the kind is `exact-match` or the caller has named kind and five numbers; (c) what the caller named is the file's; (d) the named numbers exclude something | `exact-match` (b), `policy-named` (c) | before the stages; (b), (c) again in the request stage | `NO: policy` before the stages | F:1958-1970 |
| 12 | the one form of the parameters: the ten rows below | (ten names) | request | `NOT-A-VERIFICATION` | F:1971-1972 |
| 13 | two codes: the lines `group folded` and `group omega` differ in code length or in message length, and so do `group once-folded` and `group once-omega` | `two-codes` | all three stages | `NOT-A-VERIFICATION` | F:1973-1985 |
| 14 | the line `answers` is 1 | (parser) | parser | `NO` | F:1986-1992 |

Condition 12 (F:1994-2005):

| name | what must hold |
|---|---|
| `routed-experts` | NE is above 0 |
| `five-limbs` | the line `xl 5` is there |
| `placement-table` | the configuration directory has a layout file (without one the call is rejected earlier) |
| `no-range-words` | neither the line `eg` nor the line `smax` is there |
| `three-bytes` | S is below 32 (a larger value is rejected earlier) |
| `ring-degree` | D is 2048 |
| `one-shift` | all layers of a group of layers have the same word sh in `KL.bin` |
| `one-placement` | the layout file places the matrices that another sub-proof reads in the same way in all groups of layers, number by number, the letter of each block's line among them |
| `softmax-table` | S is 12 and rx is 8 |
| `rotary-table` | theta0 is 10000 or 500000, dh is at most 128, lt is at most 10 |

"Conditions 7 to 13 are the **standard parameter form**; of condition 11, its parts (b) and (c).
All of them but 11 read the three public files alone. The stage request asks 7 to 13; the stages
key and leaf ask 13. The lines of conditions 3, 6 and 14 the parser holds at one value. Every
stage also asks condition 2" (F:2024-2027). (src) the list and its order: VFC:709-726.

These ten rows are not the ten conditions on hiding (F:2007-2009).

### 3.9 Phase G — the parent's closing sequence (src: CPP:2848-2954)

The first that applies ends the call (F:2671-2673, OUT:266-280):

1. the first rejecting stage's name is `model-statement`: three lines, exit 1 (CPP:2848-2853);
2. print the stages' output if the call can still pass, or under `-show-stages` (CPP:2855-2859);
   print the heading `---- the call ----` (CPP:2860);
3. a stage rejected: `refused by the stage <stage>[: <reason>]`, `NO: <name>`, exit 1
   (CPP:2861-2864). "A rejection goes before a failure: if one stage rejects and another is
   killed, the call ends with `NO`" (F:2679);
4. a stage ended under an `internal-` name, was killed, or its output does not fit:
   `NOT CHECKED: <name>`, exit 5 (CPP:2865);
5. guards: `internal-covered-line` (CPP:2869), `internal-sums-line` (CPP:2871),
   `internal-id-two-ways` (CPP:2879-2885), and with `-no-proof-of-work` one part of
   `internal-sums-line` (CPP:2883);
6. collect the call's own causes `id-named` and `no-proof-of-work` (CPP:2886-2892); print the
   accounting, the causes, `commitment ID:`, `id:`, `h_par=`, the line on weight hiding,
   `covered:`, the lines `stage <name>: work:` (CPP:2895-2903);
7. any cause, fewer than 128 requested bits, or a test build: `commitment:`, `proof of work:`,
   `result-v1 status=14 ..`, `NOT-A-VERIFICATION`, exit 14 (CPP:2928-2933);
8. the last guards, made only on the way to an acceptance: two under `internal-sums-line`,
   `internal-policy-not-given`, `internal-policy-kind` (CPP:2935-2944; F:2680);
9. a token of the request was checked under another kind than `exact-match`: `commitment:`,
   `proof of work:`, `result-v1 status=0 ..`, `WITHIN LIMITS: ..`, exit 0 (CPP:2945-2950);
10. else `commitment:`, `proof of work:`, `result-v1 status=0 ..`, `YES`, exit 0
    (CPP:2951-2954);
11. if standard output could not be written: no last line, exit 15 (CPP:3413-3416).

### 3.10 Dependency summary

| needs | from |
|---|---|
| T, V, every size, plan and shape; statement words 0..162 and 171..176 | the three public files alone (Phase C) |
| statement words 163..170 | the request file (stage request, E3) |
| commitment ID | Phase C + the beginning of `key.bin`; compared in every stage (Phase D) |
| item `table` of the key file's chains | the beginning of `key.bin` |
| items `the first table`, `the further table` of the link | the beginning of `key.bin`; the beginning of the leaf file |
| item `table` and `stored copy` of the proof's first chain | the beginning of the leaf file; k of the proof's head |
| binding tree's root (shared chain's first query) | the first chain's seal + the slot's word, salt and siblings |
| second chain's statement | the first chain's seal, then the shared chain's seal |
| the call's verdict | all three stages passed on the same bytes, same ID, the caller's ID, conditions of 13.7 |

## 4. Rejection names

### 4.1 How many, and the scheme

- `verifier/src/vf_rejection_names.txt` has **304 entries, all different**: 141 begin with
  `internal-`, 163 do not (counted by script over NAMES:1-304).
- "An entry is a whole name or the fixed beginning of names that end in a variable part"
  (SMAP:236). 31 entries end with `-` (14 of them `internal-`); the printed name then goes on
  with the name of a call, a matrix or a tree (F:2299-2300). Two more entries are beginnings
  without a trailing hyphen: `version-unknown` (printed `version-unknown (policy)`; "The blank and
  the brackets are part of the name", OUT:346) and `parameter-` (printed
  `parameter-<name> (policy)`, F:2108).
- The file "lists the names that a stage or a call rejects with, but not the names that the parent
  process itself gives a `NOT CHECKED`, such as `internal-stage`" (VRM:154-155). Seven such names
  exist (4.4), so the full set is **311**.
- The 141 `internal-` entries are exactly the list of F:2366-2404 (checked by script: no entry
  missing on either side).
- Every other entry is named in 13.8, whole or as a beginning, except `J-E` (NAMES:1) and
  `one-hot` (NAMES:52). Both are completions that 13.8 lists under `no-wrap-H-<name>` (F:2186) and
  `no-wrap-<name>` (F:2168), so they are not names of their own (inference).
- The file "is not a source of the program, but it is in this folder and so enters the source
  digest `build=`" (SMAP:236).
- "The names are printed words and are not hashed"; "One name can belong to several tests"
  (F:2056, F:2060).
- A name raised inside a sub-proof comes after the sub-proof's prefix and a colon, as in `G0:`,
  `A11:`, `H:`; `coin-zero`, `header-y` and `chain-refused` are printed bare (F:2300-2302).
- (src) A name counts as internal if `internal-` comes first or right after an alphanumeric
  prefix and a colon (VFC:342-346).
- The Lean verifier keeps these names "so that the two programs can be compared", gives them
  without the sub-proof's prefix, and uses the general name `refused` where the C++ has no line
  (LTREES:41-42, LTREES:55-59).

Families of the 163 entries that are not `internal-` (the leading word names the subject;
grouping mine):

| family | count | entries |
|---|---|---|
| `policy` | 34 | `policy`, `policy-call-line`, `policy-call-list`, `policy-call-list-A`, `policy-call-list-H`, `policy-cert-words`, `policy-cs`, `policy-forms`, `policy-gap-words`, `policy-gate-table`, `policy-gcl`, `policy-iotaA`, `policy-leafd`, `policy-length`, `policy-lidb`, `policy-line-`, `policy-line-form`, `policy-line-long`, `policy-name-`, `policy-nminH`, `policy-norm`, `policy-norm-F`, `policy-profile`, `policy-rcl`, `policy-sym-readers`, `policy-tables`, `policy-tau-hb`, `policy-toksrc`, `policy-ut`, `policy-weight-kind`, `policy-weight-width-emb`, `policy-work-most`, `policy-xl`, `policy-zero-byte` |
| `af` | 21 | `af-no-wrap-N1`, `-N2`, `-N3`, `-N4`, `-N5`, `-N6`, `-N9`; `af-policy-C`, `af-policy-call-list`, `af-policy-kF`, `af-policy-nmin`, `af-policy-sh`, `af-policy-softmax`, `af-policy-wd`; `af-shape-call-`, `af-shape-heads`, `af-shape-la`, `af-shape-lmS`, `af-shape-sh`, `af-shape-tiles`; `af-unclosed-call` |
| `shape` | 21 | `shape-D`, `shape-L`, `shape-NE`, `shape-V`, `shape-call-`, `shape-call-H-`, `shape-foreign-`, `shape-functional-`, `shape-groups`, `shape-heads`, `shape-la`, `shape-lmb`, `shape-matrix-`, `shape-product-layer`, `shape-product-layer-H`, `shape-pt-words-`, `shape-request-matrix`, `shape-request-matrix-A`, `shape-request-matrix-H`, `shape-theta0`, `shape-words` |
| `hid` | 13 | `hid-a-fold-list`, `hid-a-owner-uses`, `hid-a-slots`, `hid-a-weight-matrix`, `hid-call-floor`, `hid-g-slots`, `hid-h-slots`, `hid-hb`, `hid-k-range`, `hid-planes-`, `hid-profile-segment-`, `hid-tau`, `hid-vocab-cols` |
| `plan` | 12 | `plan-fold-source`, `plan-groups-base`, `plan-head`, `plan-identity-cap`, `plan-layout`, `plan-link`, `plan-mask-row`, `plan-shape`, `plan-tau`, `plan-tensor-layout`, `plan-tensor-layout-fill-`, `plan-w-zero` |
| `forest` | 10 | `forest-calls`, `forest-depth`, `forest-depth-A`, `forest-depth-G`, `forest-depth-H`, `forest-keys`, `forest-only-padding-`, `forest-planes`, `forest-row-value-`, `forest-trees` |
| `header` | 8 | `header-absent-call`, `header-absent-call-H`, `header-absent-class`, `header-absent-hash`, `header-absent-kind`, `header-magic`, `header-version`, `header-y` |
| `cp` | 6 | `cp-bits-above-digest`, `cp-entry-missing`, `cp-key-head`, `cp-key-length`, `cp-proof-head`, `cp-proof-length` |
| `KL` | 5 | `KL-kq-kk`, `KL-length`, `KL-norm`, `KL-rp`, `KL-shift-range` |
| `table-digest` | 4 | `table-digest-exp`, `table-digest-rope`, `table-digest-sigmoid`, `table-digest-silu` |
| `no-wrap` | 3 + 2 | `no-wrap-`, `no-wrap-H-`, `no-wrap-pin-forest`; the stand-alone completions `J-E`, `one-hot` |
| `statement`, `token` | 3 + 2 | `statement-length`, `statement-range`, `statement-required`; `token-length`, `token-range` |
| `w`, `t2f`, `pt` | 3 + 2 + 1 | `w-list-token-factor`, `w-shape-lk`, `w-shape-mW`; `t2f-columns-range`, `t2f-weight-class`; `pt-pub-forest` |
| single | 13 | `chain-refused`, `coin-zero`, `close-list-long`, `entry-refused`, `key-refused`, `link-claim-count`, `model-statement`, `parameter-`, `parameters-not-admitted`, `proof-refused`, `reply-differs`, `security-bits`, `version-unknown` |

### 4.2 From a name to a class and an exit code

| last line | exit code | which names | line |
|---|---|---|---|
| `NO: <name>` | 1 | every name that is not `internal-`: a test failed before the stages or in a stage. Also `NO: internal-..` where the program met a fault of its own **before any stage** (no verdict on the proof), and in a planning call, which has no stages | F:2679, F:2888-2889; OUT:255, OUT:348 |
| `NOT CHECKED: <name>` | 5 | three kinds: (1) a name under which a stage ended and which begins with `internal-`, also after a sub-proof's prefix; (2) `internal-stage`; (3) the parent's guards `internal-covered-line`, `internal-sums-line`, `internal-id-two-ways`, `internal-policy-not-given`, `internal-policy-kind`, `internal-result-line` | F:2680 |
| `NOT-A-VERIFICATION` | 14 | no name in the last line; the causes (condition names of 13.7 and 14.4) are in the lines before | F:2681, F:2790-2806 |
| usage text, or one line `input-unreadable-<role>: ..` | 2 | no name: not a verdict | F:2677-2678 |

- "A call in which a stage ends under such a name [`internal-`] ... and in which no other stage
  rejects, does not end with `NO` but with `NOT CHECKED: <name>`" (F:2343-2345).
- `NOT CHECKED` under `internal-stage` or `internal-exception-parFor`: the machine can be the
  cause, a second call can end otherwise; any other name recurs on the same files (F:2680,
  OUT:288-292).
- Eight `internal-` names can be raised by a rare sampled value and are tests on content of every
  verifier: `internal-f-table-read`, `internal-t2f-untyped-`, `internal-t2f-untiled`,
  `internal-sym-rowvec`, `internal-f-tie-weights`, `internal-g-free-slot`,
  `internal-a-free-slot`, `internal-h-free-slot` (F:2346-2351). Some other `internal-` tests are
  tests on the public files that every verifier makes: `internal-qa-layout`,
  `internal-weight-limbs` (F:2351-2353).
- "A verifier with two answers, as R0.3 asks, rejects in all the cases of this paragraph"
  (F:2354-2355).
- `internal-claim-values` is raised only in code that serves tests (F:2355-2358).
- A `NO` is not always the provider's fault: `table-digest-<name>` means the caller's
  floating-point library computes a table differently, and the proof may be honest (OUT:345);
  `coin-zero` rejects an honest proof at a rare challenge (OUT:304-306).

### 4.3 The names by stage

**Before the stages** (F:2076-2090): `cp-bits-above-digest`, `policy` (command line),
`close-list-long`, `KL-length`, `version-unknown (policy)`, `cp-key-length`, `cp-key-head`,
`statement-required`, `statement-range`, `policy` (files), `cp-proof-length`, `cp-proof-head`,
`cp-entry-missing`. Conditions and order: 3.1 and 3.2.

**On the public files, in every stage** (F:2106-2210): rows C1 to C103 of 3.3.

**Where the plans of the sub-proofs are made (every stage) or inside a sub-proof (stage
request)** (F:2304-2341):

| name | what must hold | F line |
|---|---|---|
| `af-shape-tiles` | lt from 2 to 16, lB from 0 to lt - 2 | 2306 |
| `af-shape-sh` | a group of layers has exactly 2^ll values sh | 2307 |
| `af-shape-la` | 0 <= la - lt <= log2 dh, la <= 16; la <= lmo and la <= lmq; 2^(la - lt) divides 2^lmo / T and 2^lmq / T | 2308 |
| `af-policy-softmax` | S 1 to 14, rx 1 to 12, lt + S + 1 <= 24; the softmax table reaches 0 at a row u0 <= 2^20 + 1 | 2309 |
| `af-shape-lmS` | lmS at least 1 and at most nD (11.3) | 2310 |
| `af-policy-kF` | kFD 8 to 16; the table with 2^kFD rows has room for its first u0 + nHD rows, and at most nHD rows more, for each shift | 2311 |
| `af-policy-sh` | every value sh that occurs is from 4 to 12 | 2312 |
| `af-policy-C` | for each shift sh, C_sh = u0 2^sh has C_sh + 65536 <= 2^24 (not the line `C` of the policy) | 2313 |
| `af-no-wrap-N1` .. `-N6`, `-N9` | attention's no-overflow conditions (11.3, second half) | 2314 |
| `af-policy-call-list` | every line `callA` has at least one call's segment; each of the seven occurs exactly once, in a line of its kind (RM, RD in KR; FM, FD in KFD; WL, IX in R16; WH in WH); at most twelve expanded calls | 2315 |
| `af-policy-nmin` | nmin at least 10 | 2316 |
| `af-shape-call-` | each expanded call of attention has 2^n keys, n from 10 to 44 | 2317 |
| `forest-depth-A` | depth of a tree of attention's lookup forest at least lmS and at least lt + log2 dh | 2318 |
| `hid-a-owner-uses` | the number of sub-proofs that read the matrix qa is not 0 | 2319 |
| `hid-a-fold-list` | an attention sub-proof's smallness test has NAs + 4 matrices, at most 256 | 2320 |
| `hid-a-weight-matrix` | an attention sub-proof has no weight matrix in its list [cf] | 2321 |
| `hid-a-slots`, `hid-g-slots`, `hid-h-slots` | the sub-proof sends fewer than 2^30 scalars | 2322-2324 |
| `af-unclosed-call` | every lookup call has been given its keys exactly once [cf] | 2325 |
| `hid-profile-segment-` | every call's segment of a feed-forward sub-proof has a relation [cf] | 2326 |
| `shape-pt-words-` | each lookup call's table has 2^k rows, k from 5 to 16; its other numbers in range; a table given as a list has 2^k entries | 2327 |
| `forest-row-value-` | every public value of a lookup table's row is below the field's prime | 2328 |
| `forest-calls` | a lookup forest has 1 to 16 calls | 2329 |
| `forest-depth`, `forest-trees`, `forest-keys` | a tree has depth at least 10; at most 256 trees; at most 2^31 keys | 2330 |
| `no-wrap-pin-forest` | 2^(kT + cK + 32) is below p | 2331 |
| `pt-pub-forest`, `forest-only-padding-` | no tree has more padding keys than positions; no call consists of padding only | 2332 |
| `forest-planes` | the multiplicities' matrix has 2^lm rows with 5 <= lm <= kT + 5; lm is lmb, lmbA or lmbH | 2333 |
| `shape-matrix-`, `hid-k-range`, `t2f-weight-class`, `shape-foreign-`, `t2f-columns-range` | in a smallness test's list: each matrix has at least one row and 1 to 8191 columns; none is a weight matrix; a matrix of an earlier segment is that segment's whole matrix; twice the sum of all rows is below 2^32 | 2334 |
| `plan-tau` | the line `tau` equals the number of combinations of the smallness test that follows from the frame lines | 2335 |
| `plan-w-zero` | a number that the plan passes with each symbol matrix is 0 | 2336 |
| `w-shape-lk` | w, the last number of the line `table`, is from 1 to 20 | 2337 |
| `w-shape-mW` | the committed matrix has at most 2^22 rows | 2338 |
| `chain-refused` | inside a sub-proof the chain has not rejected: every scalar read is there and canonical; in a round with proof-of-work bits the nonce is there and passes. Also where the library's routine for a segment answers that a call was not due | 2339 |
| `coin-zero` | in a feed-forward sub-proof, eps of `PSC epsilon` of the second token sumcheck (11.2, step 9) is not 0 | 2340 |
| `shape-functional-` | a linear functional on a matrix of the smallness test has a length that is not 0 and divides the matrix's number of rows, and as many coefficients as its length | 2341 |

"A round that is not the one that the plan has next gives no rejection: by the source that is a
fault of the program and not of a proof, and a guard of the library ends the process" (F:2339).

**On the key file, the leaf file, the caller's files and the proof file** (F:2214-2231):

| name | what must hold | stage | F line |
|---|---|---|---|
| `key-refused` | the beginning of `key.bin` has the form of R13.2 | every stage | 2216 |
| `model-statement` | the commitment ID formed from the files equals the one after `-id` | every stage | 2217 |
| `security-bits` | every round's error, proof of work counted, at most 2^-sec, and sec at least the requested bits | every stage | 2218 |
| `key-refused` | every test on `key.bin` (section 9), first byte to last | key | 2219 |
| `entry-refused` | every test on the leaf file (section 9), against the anchor read from the beginning of `key.bin` | leaf | 2220 |
| `statement-required` | 12.2, test 1 | request | 2221 |
| `statement-range` | 12.2, tests 2, 3 and 4 | request | 2222-2223 |
| `token-range` | 12.2, test 5 | request | 2224 |
| `entry-refused` | the beginning of the leaf file has the form of R13.3 | request | 2225 |
| `proof-refused` | every test on the proof (sections 10 and 11) other than the comparison of the next token | request | 2226 |
| `reply-differs` | the next token in the proof equals the caller's | request | 2227 |
| `header-y` | the element of the round `REPLY` has the form of a token: e_1 = e_2 = 0 and e_0 below V | request | 2228 |
| `plan-link`, `plan-mask-row` | with the first segment exactly one oracle message is sent at the start (the masks of the request's rows on the table), with a free entry for each segment with claims on the weights and for the batching of their rows | request | 2229 |
| `plan-head` | a segment's first message holds a plain scalar only in the head's segment, and there exactly one | request | 2230 |
| `link-claim-count` | a segment with claims on the weights has at least one claim, as many as its plan says, and a point with as many coordinates as the committed matrix has column variables. "No byte of a proof file changes these numbers" | request | 2231 |

`key-refused`, `entry-refused` and `proof-refused` "each stand for all tests that the library
`blocks/` makes on that file, and `chain-refused` ... for its tests on a chain inside a sub-proof"
(F:2233-2235). In names and printed lines "entry" means a leaf file, "copy" a leaf table and
"reply" the next token (F:2235-2236).

### 4.4 The `internal-` names

Seven belong to the process that starts the stages and are in no file of names (F:2358-2361):
`internal-stage`, `internal-sums-line`, `internal-covered-line`, `internal-id-two-ways`,
`internal-result-line`, `internal-policy-not-given`, `internal-policy-kind`.

The 141 names under which a stage can end (F:2366-2404 = the `internal-` entries of NAMES):

`internal-W-length`, `internal-W-length-H`, `internal-af-W-length`, `internal-af-calls`,
`internal-af-padding-key`, `internal-call-`, `internal-fork-not-finished`,
`internal-header-length`, `internal-layout-words`, `internal-line-`, `internal-qa-layout`,
`internal-sc3-`, `internal-segment-`, `internal-table-`, `internal-tensor-`, `internal-L-index`,
`internal-L-row`, `internal-L-slot`, `internal-a-TX-place`, `internal-a-Ty`,
`internal-a-claim-count`, `internal-a-free-slot`, `internal-a-tree-list`,
`internal-batching-bare`, `internal-claim-count`, `internal-claim-factors`,
`internal-claim-unit`, `internal-coef-`, `internal-exception-parFor`, `internal-eq-index`,
`internal-g-claim-count`, `internal-g-free-slot`, `internal-gamma-rows`,
`internal-h-claim-count`, `internal-h-free-slot`, `internal-h-owner-TX`,
`internal-h-owner-shape`, `internal-h-tree-list`, `internal-nmlab`, `internal-shape-moe`,
`internal-slot-count`, `internal-stack`, `internal-t2-order`, `internal-t2f-TX-order`,
`internal-t2f-ZF-order`, `internal-t2f-functional-`, `internal-t2f-lists`, `internal-t2f-map`,
`internal-t2f-unit-`, `internal-t2f-untiled`, `internal-t2f-untyped-`, `internal-t2f-blocks`,
`internal-weight-matrix`, `internal-a-calls-booked`, `internal-a-owner-shape`,
`internal-a-table-index`, `internal-a-table-length`, `internal-fold-columns`,
`internal-g-calls-booked`, `internal-g-owner-shape`, `internal-h-calls-booked`,
`internal-t2f-table-outside`, `internal-t2f-tables-overlap`, `internal-a-owner-place-`,
`internal-af-rows-booked`, `internal-border-count`, `internal-f-bz-weights`, `internal-f-exist`,
`internal-f-fun-closed`, `internal-f-fun-open`, `internal-f-join-place`,
`internal-f-matrix-order`, `internal-f-order`, `internal-f-padding-key`,
`internal-f-table-index`, `internal-f-table-read`, `internal-f-tables-gap`,
`internal-f-tail-slot`, `internal-f-tie-weights`, `internal-f-read-weights`, `internal-f-zzcol`,
`internal-g-owner-place-`, `internal-g-rows-booked`, `internal-h-owner-place-`,
`internal-h-rows-booked`, `internal-sym-point`, `internal-f-fun-moved`, `internal-sym-rowvec`,
`internal-sym-weight`, `internal-root-behind-sd`, `internal-f-fold-array`, `internal-sym-shape`,
`internal-f-draws`, `internal-build-word`, `internal-naming-first`, `internal-statement-cover`,
`internal-statement-prescan`, `internal-statement-twice`, `internal-th`,
`internal-version-word`, `internal-f-door`, `internal-last-line`, `internal-refusal-name`,
`internal-par-digests`, `internal-a-merged-point`, `internal-forest-join`,
`internal-forest-place`, `internal-forest-point`, `internal-forest-pub`, `internal-psc-degree`,
`internal-psc-order`, `internal-claim-not-added-`, `internal-claim-values`,
`internal-forest-no-proof-read`, `internal-forest-padding-places`, `internal-g-join-place`,
`internal-h-join-place`, `internal-slot-order`, `internal-slot-unused`, `internal-g-forest`,
`internal-g-link`, `internal-g-merged-point`, `internal-g-routed-without-terms`,
`internal-g-table-index`, `internal-g-table-point`, `internal-h-forest`,
`internal-h-merged-point`, `internal-h-table-index`, `internal-slot-marks`,
`internal-slot-twice`, `internal-cp-cut`, `internal-round-name`, `internal-parameter-name`,
`internal-row-form`, `internal-shapes-order`, `internal-sealed-request`,
`internal-weight-limbs`, `internal-configured-twice`, `internal-work-two-ways`,
`internal-asked-bits`, `internal-plan-moment`.

### 4.5 Reasons are not names

The library gives a reason as a sentence, which the stage prints in its line before its last,
after `key:`, `entry:`, `proof:` or `chain:`; "no verdict depends on it". The program reads it
once, for a name: where the reason is `the proof is about another reply`, the stage ends under
`reply-differs` and not under `proof-refused` (F:2236-2239). Where the chain itself has no reason,
the words say where in the file's order the test failed, for example `first chain: the links`,
`shared chain: a proximity test`, `second chain: its end` (F:2243-2244).

The reasons, as printed (F:2246-2278): `file-too-short`; `file-of-another-kind`;
`version-unknown`; `the table's root`; `the copy's root`; `the record's answers`;
`the table's numbers are not a code`; `the table has too many rows`;
`a row has no room beside its pads`; `the leaves of the table's tree have no admitted salt`;
`the key names no configuration`; `the record has not one answer for each row and seed`;
`a table without a commitment`; `the chain's salt is missing`;
`a chain's run's value is the digest of zeros`; `an earlier chain of this proof was refused`;
`a value that the prover sends is missing or not in canonical form`;
`a value that the prover sends is missing`; `a nonce is missing`;
`a nonce does not give the proof of work that its round asks for`;
`an opening is cut short or holds a symbol that is not in canonical form`;
`an opening does not lead to its root`; `a vertex of a tree gets two values under one root`;
`an opening, or another answer to the verifier's queries, is cut short or not in canonical form`;
`the opened columns of the table do not lead to its root`;
`BASE: the masked message in the proof does not satisfy the linear claim`;
`BASE: the encoding of the masked message differs from the opened symbols at a listed position`;
`the seal's place`; `a chain of the key has refused`; `the public files are not admitted`;
`the proof was made on another stored copy of the table`; `the proof is about another reply`;
`the request's place in its batch`; `bytes are left over at the end of the proof`;
`a chain of the proof was refused`.

Notable rules behind them: a nonce is tested before anything is sampled from the round's answer
(F:2263); the `BASE` linear claim is tested before the stage's positions are sampled (F:2269);
the table has at most 2^40 rows (F:2254); the verifier's configuration's digest is not 32 zero
bytes (F:2255).

The call repeats a reason in its own line before the last only if the stage's line begins
`key: `, `entry: ` or `proof: `, and only if the sentence has no digit and no character other
than letters, blanks and `, . : ; ' ( ) -` (F:2239-2242, F:2992-2999; (src) CPP:2583-2596).

### 4.6 Names that are not rejection names

Condition names of 13.7 and 14.4, printed after `not the standard parameter form:` and ending a
call with `NOT-A-VERIFICATION`: `id-named`, `next-token`, `no-proof-of-work`, `exact-match`,
`policy-named`, `routed-experts`, `five-limbs`, `both-clamps`, `prompt-source`,
`placement-table`, `table-digests`, `no-range-words`, `three-bytes`, `ring-degree`, `one-shift`,
`one-placement`, `softmax-table`, `rotary-table`, `norm-shifts`, `two-codes` (F:1994-2005,
F:2833-2841; (src) VFC:709-726). Names of the prover's programs, not of `cp_verify`:
`prover-only-policy-kind` (F:1377), `cp-commit-first-form-alone` (F:4012).

## 5. Interface and results (section 14)

"Every printed word, option and name is in code marks, letter for letter" (F:2629-2630).

### 5.1 The whole call

    cp_verify <config folder> <ivk folder> <request file> <y file> <proof file> -id <64 hex digits> [-bits <asked>]
              [-no-proof-of-work] [-j <threads>] [-q] [-show-stages] [-next-token]
              [-policy <kind>,<C>,<theta>,<cap>,<s>,<sh>]

(F:2634-2636) "One call checks the key file `key.bin`, the leaf file that the proof file names,
and the proof file. The five arguments come first, in this order; the options follow them, in any
order." (F:2638-2639) An option before the paths is read as a path (VER:196).

| option | value | effect | line |
|---|---|---|---|
| `-id` | 64 hex digits, small or capital | the commitment ID the caller expects; each stage compares it; another ID ends `NO: model-statement`. Without it: at best `NOT-A-VERIFICATION` | F:2660 |
| `-bits` | 0 to 1000000; default 128 | the requested bits. Above 128: `NO: cp-bits-above-digest` before a file is read. Below 128: every test is made, at best `NOT-A-VERIFICATION` | F:2661 |
| `-no-proof-of-work` | none | if a round needs its proof of work for the parameter file's target (`sec`), at best `NOT-A-VERIFICATION`; changes no number and no test | F:2662 |
| `-j` | 1 to 256 | threads of the stage request; key and leaf take an eighth each, at least one. "It changes no result" | F:2663 |
| `-q` | none | leaves out most progress lines | F:2664 |
| `-show-stages` | none | prints the stages' output also where the call does not pass (never under `model-statement`) | F:2665 |
| `-next-token` | none | the proof must be about the next token alone: r = T - 1 and e = T | F:2666 |
| `-policy` | `<kind>,<C>,<theta>,<cap>,<s>,<sh>` | the acceptance policy the caller expects (2.5) | F:2667 |

### 5.2 Part-calls

    cp_verify -key  <config folder> <key.bin> [-id <64 hex digits>] [-bits <asked>] [-no-proof-of-work] [-j <threads>]
              [-q] [-show-stages]
    cp_verify -leaf <config folder> <key.bin> <entry file> [-id <64 hex digits>] [-bits <asked>] [-no-proof-of-work]
              [-j <threads>] [-q] [-show-stages]

(F:2853-2856) One stage alone; "for the committer's self-check and never says `YES`"; needs no
`-id`; `-next-token` and `-policy` are not admitted and the rejection `policy` is not made
(F:2858-2862). `-leaf` prints a line that begins `key: NOT CHECKED BY THIS CALL`; its result
counts only beside a `-key` that has passed on the same `key.bin`, configuration directory, bits
and build (F:2862-2865). Last line `PART PASSED: key` or `PART PASSED: leaf`, exit code 3
(F:2869). A part-call prints no line `commitment ID: `, `covered:`, `commitment: ` or `result-v1`
(F:2874-2875).

### 5.3 Planning calls

    cp_verify -plan id <config folder> <key.bin>
    cp_verify -plan request <policy.txt> <KL.bin> <asked> [-layout <layout.txt>] -prompt <request file> -reply <y file>
              [-shapes] [-fields] [-arrays] [-j <threads>] [-q]
    cp_verify -plan accounting <config folder> <asked>
    cp_verify -plan arrays <config folder> <asked>

(F:2879-2883)

- A planning call checks no proof and ends with the line `PLAN ONLY: no proof was checked`, exit
  code 4 (F:2885-2886).
- Files that a stage would reject in 13.4 are rejected under the same names, exit code 1; an
  unreadable file ends it with exit code 2; an `internal-` name ends it as `NO: internal-..`,
  exit code 1; for want of memory or of a thread `NOT CHECKED: internal-stage`, exit code 5; a
  bad command line exit code 2; unwritable output exit code 15. It does not take
  `-no-proof-of-work`. A guard of the library can end it by a signal, with no last line
  (F:2886-2896).
- `-plan id` prints `h_par=` and `commitment ID: ` with 64 hex digits, "for the one who publishes
  it"; it reads the beginning of `key.bin` for its form and checks nothing (F:2900-2905).
- `-plan request` makes the steps of 13.4, the tests of 12.2 and the error accounting of the
  three files together, and prints the plan: the groups of codes with their derived numbers, the
  accounting, each file's greatest length, the missed conditions of 14.4, a line
  `statement: <n> words, y at word <i>`, `h_par=`, `configuration=` and `dw=`. `-shapes` prints
  every round; `-fields` every field of every file; `-arrays` lists the arrays and ends
  (F:2906-2914).
- `-plan accounting` prints the same accounting and lengths for a synthetic request of T tokens 0
  with r = 0, e = T and y = 0 (F:2915-2916).
- `-plan arrays` lists the arrays that the segments commit to, one line `array:` each, from
  `policy.txt` and `KL.bin` alone (F:2917-2918).
- Other lines: `plan: the policy's kind is <kind>: every whole call under this parameter file
  ends NO: policy` (F:2919-2924); a line beginning `work:` if a round needs its proof of work
  (F:2925-2929); lines beginning `length:` for `key`, `entry`, `proof`, each with a greatest
  length after `at most` and an average (F:2930-2937); the two lines beginning
  `accounting: one-time files: ` (F:2938-2941).
- Only `-plan request` is given its parameter file by path; every other call reads the file named
  `policy.txt` in the configuration directory (FR:41-43).

### 5.4 The results

"The last line of standard output and the exit code go together. ... Of the results below, the
first that applies is the call's." (F:2671-2673)

| last line | exit code | when | line |
|---|---|---|---|
| the usage text, ending with a line that begins `cp_verify: this command line was not accepted: `, or the one line for a malformed `-id` or `-policy`, on standard error | 2 | a bad command line | F:2677 |
| `input-unreadable-<role>: <the file> cannot be read: <reason>`, on standard output | 2 | a file the caller names is missing, not a regular file, or cannot be read to its end | F:2678 |
| `NO: <name>` | 1 | a test failed, before the stages or in a stage | F:2679 |
| `NOT CHECKED: <name>` | 5 | nothing has been verified: the program or the machine failed, or a guard ended a stage or the call | F:2680 |
| `NOT-A-VERIFICATION` | 14 | no test that ran failed, but the call does not count | F:2681 |
| `WITHIN LIMITS: clipped-gap C=<C> theta=<theta> cap=<cap> s=<s> sh=<sh>` | 0 | 2.6 | F:2682 |
| `YES` | 0 | 2.6 | F:2683 |
| no last line | 15 | the answer could not be written to standard output; one sentence on standard error | F:2684 |
| `PART PASSED: key`, `PART PASSED: leaf` | 3 | a part-call found no fault | F:2869 |
| `PLAN ONLY: no proof was checked` | 4 | a planning call | F:2886 |

(src) the eight exit statuses: VFC:347-350. Status 12 (`STAGE PASSED WITH WORK`) is a stage's
status toward the parent, never a call's exit code (CPP:1263, VFC:769).

Order of precedence (OUT:266-280): a bad command line (2); an unreadable file (2) or a rejection
before the stages (1), whichever comes first; a rejection by a stage (1); `NOT CHECKED` (5);
`NOT-A-VERIFICATION` (14); an acceptance (0). Three exceptions: a few late internal checks run
only where the call would otherwise be accepted, so they come after `NOT-A-VERIFICATION`; exit
code 15 replaces any result that the call returns at its end; and the program itself can end in
`NOT CHECKED` outside the stages.

What keeps a call without a failed test from an acceptance (14.4, F:2790-2831):

1. a condition of 13.7 is missed, other than 3, 5, 6, 11 and 14 (where `cp_verify` rejects);
2. the program is a test build (its first printed line begins `TEST BUILD:`);
3. the call has `-next-token`, and r = T - 1 and e = T do not both hold (`next-token`);
4. the call has `-no-proof-of-work`, and a round needs its proof of work (`no-proof-of-work`).

"Cause 1 binds every verifier; causes 2 to 4 are this command's own, and a second verifier need
not have them." (F:2805-2806)

### 5.5 The output of a whole call

    ---- stage key ---- <n> thread(s), <seconds> s
    (the stage's lines)
    ---- stage leaf ---- ..
    ---- stage request ---- ..
    leaf number <k>
    (the stage's other lines)
    ---- the call ----
    accounting: ..
    stage <name>: not a verification: <causes>
    the call: not the standard parameter form: <cause>
    commitment ID: <the commitment ID>
    id: named by the caller and equal
    h_par=<64 hex digits>
    weight hiding: NOT CHECKED BY THIS CALL (it rests on how the commitment was made)
    covered: ..
    stage <name>: work: <bits> + <work> (..)
    commitment: ..
    proof of work: ..
    result-v1 ..
    YES

(F:2945-2964)

**When the stages' output is printed** (F:2966-2977): in the order of the stages, when all have
ended; without `-show-stages` only if the call can still end with a pass (no stage rejected,
failed or ended `NOT-A-VERIFICATION`; no parent guard failed; `-id` given; requested bits not
below 128; not a test build; cause 4 does not apply). So a call that ends `NO` or
`NOT-A-VERIFICATION` prints none of it.

**A stage's own lines** (F:2977-2988): the record of its accounting (lines beginning `plan-sums:`,
`plan-rests:`, `plan-near:`, `plan-worst:`, `plan-lists:`, `plan-round:`, `plan-union:`), a line
`work:` if it needed proof of work, a line `result:`, and one of `STAGE PASSED: <stage>`,
`STAGE PASSED WITH WORK: <stage>`, `NOT-A-VERIFICATION`, `NO: <name>`. Each stage prints
`computed commitment ID: <id>`. The stage request's first line is `leaf number <k>`; it prints a
line `seal`, a blank and 64 hex digits (the seal of the proof's first chain) and
`weight hiding: NOT CHECKED BY THIS RUN ..`.

The request stage's line `result:` has the fields `word=`, `ms=` (the commitment ID), `sec=`,
`t=`, `asked=`, `by=largest-round-error`, `T=`, `lim=-`, `C=`, `theta=`, `cap=`, `s=`, `sh=`,
`sT=`, `F=`, `leaves=` (the line `slots`), `place=` (the request's slot), `card=0`,
`judged=1 of 1`, `dj=` (the seal of the first chain), `build=`, `dw=`; key and leaf have `word=`,
`sec=`, `asked=`; every stage's line ends with `pow=`, `pows=`, `powc=` and a note in brackets
that ends `no security level is claimed` (F:3092-3103; (src) CPP:2524-2531, VFC:795-801).

**After a rejection by a stage** the call prints only the heading, the line
`refused by the stage <stage>` (with `: ` and the reason where repeated) and `NO: <name>`
(F:2990-2992). Whole output of the stored example with one bit flipped (OUT:98-102):

    ---- the call ----
    refused by the stage request: an opening does not lead to its root
    NO: proof-refused

**Under `model-statement`** the call prints three lines and nothing else, also with
`-show-stages`, and no heading (F:3001-3005; (src) CPP:2849-2851):

    id: these are not the files of the commitment that you named; nothing in them was checked
    id: take the commitment ID from your own record of where it was published, never from these files
    NO: model-statement

**Without `-id`** the line reads `id: not compared: the call named none`, and the word
`not-shown-without-id` is printed instead of the ID in the line `commitment ID: ` and wherever
the stages' output has it (whole call only) (F:3008-3012).

**Where the call ends `NOT CHECKED`**, the line before the last says how the verifier failed
(F:3007-3008).

**The four closing lines.** "A whole call that ends with `YES`, `WITHIN LIMITS` or
`NOT-A-VERIFICATION` ends with four lines, always in this order: the line `commitment: ..`, the
line `proof of work: ..` (14.3), the line `result-v1 ..` (14.8) and the last line. A whole call
that ends in another way has none of the first three." (F:3021-3024)

- `commitment: <n> closeness rounds of the one-time files rest on another source than the bound
  within a third of the distance; the table has a record: the binding of the weights rests on the
  theorem on codes (ePrint 2025/2055, Theorem 4.6), taken as given` (one line; with n = 1:
  `commitment: 1 closeness round of the one-time files rests ..`) (F:3025-3027; (src)
  CPP:2915-2916, VFC:510). n counts closeness rounds of the key file's and the leaf file's plans
  only; "By this page's reading of the source n is above 0 in every call" (F:3028-3039).
- `proof of work: none counted`, or `proof of work: up to <n> bits counted in <m> rounds; with it
  the least round has <a> bits, without it <b> bits` (`round` where m is 1). n is the largest of
  the fifteen numbers of the lines `work ..`; m rounds need their proof of work; a and b are cut
  to two decimals (F:2698-2707; (src) CPP:2908-2912). What decides between the two forms is an
  exact comparison of every round's error with 2^-sec (F:2709-2710).
- `result-v1 ..`: 5.6.

**`covered:`** is printed in a whole call that ends `YES`, `WITHIN LIMITS` or
`NOT-A-VERIFICATION`, also under `-q` (F:3069-3072). Fields in a fixed order (F:3073-3077):
`r=`, `e=`, `T=`, `C=`, `theta=`, `cap=`, `s=`, `sh=`, `positions=` (r to e - 1), `tokens=`
(r + 1 to min(e, T - 1), or `none` if r = T - 1), `y=` (`yes` if e = T, else `no`),
`next-token=` (`yes` if r = T - 1), `policy=` (the kind the parameter file sets, whatever
`-policy` names), `above-clip=`. (src) exact form, CPP:2997-3006:

    covered: r=<r> e=<e> T=<T> C=<C> theta=<theta> cap=<cap> s=<s> sh=<sh> positions=<r>..<e-1> tokens=<r+1>..<last>|none y=yes|no next-token=yes|no policy=<kind> above-clip=<n> (<a fixed sentence in brackets>)

Sample for r = 60, e = 64, T = 64 under exact match (VER:296):
`covered: r=60 e=64 T=64 C=256 theta=256 cap=0 s=16 sh=8 positions=60..63 tokens=61..63 y=yes
next-token=no policy=exact-match above-clip=0 (...)`.

**Other lines**: `accounting: ..` (the program's own error accounting; after
`accounting: THE ROUNDS:` its lines have `HOLD`, `HOLD WITH WORK` or `NO`; the last one in a
whole call or part-call is `accounting: asked of this call: <n> bits`) (F:3050-3062); the stages
key and leaf print `accounting: one-time files: the plan of a key: <n> closeness rounds rest on
the theorem on codes (ePrint 2025/2055, Thm 4.6), taken as given, <m> on the bound within a third
of the distance; the table has a record` (and `the plan of an entry`) (F:3042-3047); the line on
weight hiding is printed in every call that ends `YES`, `WITHIN LIMITS`, `PART PASSED` or
`NOT-A-VERIFICATION` (F:3066-3067), so "the words `NOT CHECKED` appear in every accepted call"
(OUT:130-131).

### 5.6 The line for programs: `result-v1`

Printed directly before the last line, only in a whole call and only at exit codes 0 and 14, also
under `-q`; "No other line of standard output begins with `result-v1`, at any result"
(F:3107-3108, F:3168-3171). Fields in the order of the table, one blank between them, no value
holds a blank (F:3110-3112). "The first word names the line's format. Any change to a field or to
the order requires another word." (F:3112-3114)

The line that `examples/accepted-proof` prints, ID and build left out (F:3118):

    result-v1 status=0 claim=exact-match id=<64 hex digits> bits=128 work=32 work-rounds=38 least-round=128.00 least-round-without-work=96.23 commitment-assumed-rounds=49 record=1 r=60 e=64 T=64 tokens=61..63 y=yes policy=exact-match C=256 theta=256 cap=0 s=16 sh=8 sT=4 F=24 above-clip=0 leaf=0 stages=key,leaf,request dw=8 build=<64 hex digits>

| field | value | what it is | F line |
|---|---|---|---|
| `status` | `0` or `14` | the exit code with which the call ends (15 can still follow) | 3122 |
| `claim` | `next-token`, `exact-match` or `policy` | `next-token`: r = T - 1; `exact-match`: checked tokens, each the top choice; `policy`: checked tokens within another policy's limits | 3123 |
| `id` | 64 lower-case hex digits, or `not-shown-without-id` | the ID passed with `-id` and formed by every stage | 3124 |
| `bits` | whole number | the requested bits | 3125 |
| `work` | 0 to 32 | 0 if every round meets `sec` without its proof of work; else the largest of the fifteen numbers of the lines `work ..` | 3126 |
| `work-rounds` | whole number | how many rounds need their proof of work; 0 exactly if `work=0` | 3127 |
| `least-round` | two decimals | a: 2^-a is the largest error of any round, proof of work counted | 3128 |
| `least-round-without-work` | two decimals | b: the same with proof of work left out | 3129 |
| `commitment-assumed-rounds` | whole number | the n of the line `commitment: ` | 3130 |
| `record` | `1` | a constant of the format | 3131 |
| `r`, `e`, `T` | whole numbers | the last two words of the request file, and its number of tokens | 3132 |
| `tokens` | `<first>..<last>` or `none` | r + 1 to min(e, T - 1); `none` if r = T - 1 | 3133 |
| `y` | `yes` or `no` | whether the answer is about the next token too (e = T) | 3134 |
| `policy` | `exact-match` or `clipped-gap` | the kind the parameter file sets | 3135 |
| `C`, `theta`, `cap`, `s`, `sh` | whole numbers | the policy's numbers as the stage request used them | 3136 |
| `sT`, `F` | whole numbers | two more lines of the policy | 3137 |
| `above-clip` | whole number | as in `covered:` (2.7) | 3138 |
| `leaf` | whole number | k | 3139 |
| `stages` | `key,leaf,request` | a constant | 3140 |
| `dw` | `8` | the number of 32-bit words of a digest | 3141 |
| `build` | 64 hex digits | a digest of the program's sources, set by the build script; "does not show which build ran" | 3142 |

(src) the format string, CPP:2922-2925 with CPP:2993-2995: `bits=%.0f`, `least-round=%.2f`,
`least-round-without-work=%.2f`, `record=1` and `stages=key,leaf,request` are literal.

Rules:

- "With `status=0` and `claim=next-token` or `claim=exact-match` the last line is `YES`. With
  `status=0` and `claim=policy` the last line is `WITHIN LIMITS: `, the word of `policy=`, and
  `C=` to `sh=` with the same values. With `status=14` the last line is `NOT-A-VERIFICATION`, and
  the other fields are filled as at `status=0`." (F:3144-3147)
- At `status=14` the fields `claim`, `work`, `work-rounds`, `least-round-without-work` and
  `policy` have not passed the parent's last guards; no guard compares `least-round`
  (F:3174-3180).
- A printed figure is "a floating-point logarithm of an error, cut after two decimals and never
  rounded up" and decides nothing; a program tests `work=0` (F:3162-3166).
- How a program parses: split standard output on line feeds only; require exactly one line that
  begins `result-v1 `, which must be the second-to-last line; match the line as a whole; if any
  line begins `TEST BUILD:`, accept nothing (OUT:188-191).
- The line shows r and e and nothing else of the request (F:3185-3187).

### 5.7 Which lines are the stable contract

The page declares no list of stable lines. What it fixes (the rest is inference):

| item | basis | status |
|---|---|---|
| exit codes 0, 1, 2, 3, 4, 5, 14, 15 with their last lines | the table of 14.3 (F:2675-2684); the source asserts that 14 is in READMEs and tests (VFC:492) | fixed |
| the last line: `YES`, `WITHIN LIMITS: clipped-gap C=.. theta=.. cap=.. s=.. sh=..`, `NO: <name>`, `NOT CHECKED: <name>`, `NOT-A-VERIFICATION`, `PART PASSED: key`, `PART PASSED: leaf`, `PLAN ONLY: no proof was checked` | F:2675-2684, F:2869, F:2886 | fixed |
| `result-v1 ..` | versioned by its first word (F:3112-3114) | fixed; the only line with a stated versioning rule |
| the four closing lines and their order | "always in this order" (F:3021-3023) | fixed |
| `commitment: ..` and `proof of work: ..` | given letter for letter (F:2698-2703, F:3025-3027); the acceptance rule tells a client to read them (VER:245-273) | fixed in form |
| `covered:` | "Its fields have a fixed order" (F:3073); "a line for human readers" (OUT:53) | field order fixed; the sentence in brackets is not described |
| `commitment ID: `, `id: `, `h_par=`, the line on weight hiding | found "by the words with which it begins, never by counting lines" (F:3062-3063) | line beginnings fixed |
| rejection names | printed words, not hashed; a second verifier "need not use the same names" (F:1586-1588) | `cp_verify`'s own |
| reasons, stage output, `accounting:` text, progress lines, usage text | "no verdict depends on it" (F:2237); stage output "is for finding out which test failed" (F:2665) | informational |

## 6. What an acceptance states (section 15), and section 16 in brief

### 6.1 Section 15

- "An acceptance means that every test of section 13 passed, on the files and under the
  commitment ID that the caller named, and that every condition of 13.7 holds. This is so for
  every verifier." (F:3191-3192)
- For `cp_verify` an acceptance is one of the two results with exit code 0. `WITHIN LIMITS: ..`
  "is not a `YES`, since it bounds the checked tokens' costs and does not say that each is the
  top choice of its position" (F:3193-3197).
- Neither result means that every round meets 128 bits without its proof of work: up to 32 of a
  round's bits can be proof of work; that proof of work counts toward the target "is itself an
  assumption for these hash chains" (F:3197-3204).
- Neither result means that every round's error rests on a proved bound: closeness counts can
  rest on the theorem on codes, "which is taken as given" (F:3204-3209).
- "The unit of the 128 bits, and of every printed figure, is one key file's, one leaf file's and
  one request's proof, and not a batch's"; "The 128 bits are the target with which each round's
  error is compared by itself; the rounds' errors are not added." (F:3216-3220)
- "No printed figure is a security level." (F:3227-3228) At `target_full_f2` the compiled-bound
  figure is 126.21 bits with proof of work counted and 96.23 without (F:3222-3223).
- What an accepted proof covers, for a client: the positions r to e - 1 of the request file and
  no others; the tokens before the range are taken as the request file gives them
  (F:4459-4468, VER:394-396). Under exact match a `YES` "is meant to show that each checked token
  is the top choice of the committed integer model at its position" (VER:360-362).
- The eight-point acceptance rule of a client (own verifier, own files, own ID, the verdict, the
  line `covered:`, proof of work, the line `commitment:`, the end of the reply) is at
  VER:216-278; `cp_verify` knows no end tokens, so "a reply that was cut short verifies as a
  shorter reply" (F:4469-4470).

### 6.2 Section 16 (duties that no verifier can see)

"No verifier can tell how a committer or a prover made its private randomness, and nothing in
this section follows from an acceptance." (F:3233-3234) It lists duties of committer and prover
(fresh, uniform randomness; a lasting counter of opened columns per stored table; the least
nonce; zeros in unfilled entries; and so on, F:3265-3390) and, in 16.1, the ten conditions on
hiding (`main-rows`, `mask-rows`, `mask-room`, `fold-room`, `table`, `padding-entries`,
`range-checks`, `salt`, `leaves`, `batch`; F:3511-3694).

What a verifier takes from it:

- `cp_verify` rejects a configuration that misses one of the ten: the printed sentence begins
  `parameters-not-admitted: hiding: `, then the condition's name and a colon, and where two
  numbers are compared it ends `<have> where <need> are needed` (F:3736-3738).
- Every verifier asks three parts: part (a) of condition 3 (for every segment g,
  ell_mask(`link`, 1) >= n_g + S; `plan-mask-row` in `cp_verify`), part (d) of condition 3
  (ell_mask(`folded`, 1) >= 1 + S in the split case; cannot be missed with S = 1), and the fourth
  line of condition 6 (i >= m0 2^(w_T - b) + 3 S) (F:3538-3562, F:3614, F:3622-3628).
- "Who else asks each of the ten" (F:3756-3801): conditions 1, 2, 5, 7 and parts (a), (b) of 9
  are the committer's and prover's alone; 3 (b), (c), (e), 4, 6 (first three lines), 8, 9 (c) and
  10 a verifier that derives its numbers by 8.4 has from the derivation or from the parser.
- The parser comes first for two: a miss of condition 8 ends under `parameter-range (policy)`,
  of part (c) of condition 9 under `parameter-own-code (policy)` (F:3474-3476).
- An acceptance says nothing about hiding; a commitment made under `-public-weights` cannot be
  told from any other (F:3396-3410, F:4339-4346).

## 7. Limits of the page (section 17)

"The items of 17.1 to 17.3 were found by reading the programs' source; only the one on a file's
length (17.2, item 2) was also tried in runs." (F:3855-3856) "That it does not name a rule or a
section does not mean that the rule or section was compared with the programs." (F:3858-3860)

### 7.1 What the page does not define (17.1)

| item | what is left open | line |
|---|---|---|
| 1 | the content of a segment's sub-proof: section 11 is written from the source, has no numbered rule, "was compared with no proof file: no second verifier written from this page has decided on a proof of the programs" | F:3864-3870 |
| 2 | three facts no numbered rule fixes: the values of the leaf classes in `the link`, `the test on the table` and `ranges`; the order in which the codes of a file's proximity tests enter `codes`; the lengths of the four parts of a `BASE` message. The first two are hashed | F:3871-3875 |
| 3 | sizes and plans: "No numbered rule covers what is derived from the parameter file". Told only in part: how the shapes of a segment's oracle messages follow from the model's lines, and the errors of the rounds. "So this page does not decide whether a plan meets its target or needs its proof of work; a second verifier takes the plan, the codes and the shapes as inputs". No first query contains a round's error | F:3876-3885 |
| 3 | the library enforces that a stored table has passed its one-time test "inside one process only"; that all three stages passed on the same bytes "is `cp_verify`'s own logic" | F:3885-3907 |
| 4 | tests on the public files: most single conditions that end in `parameters-not-admitted` are not given, nor part of what is rejected in `ranges`. The no-overflow conditions are written for a bound of 2^60 (field 1's need) | F:3908-3914 |
| 5 | the model: what a line of the parameter file or a word of the scale file means, how tensors become the committed integers | F:3915-3917 |
| 6 | other forms of the parameters than `prof` 20, `NE` above 0, 32 digest lines; parameters in which W's base code is not Omega's | F:3918-3921 |
| 7 | field 1: R12.11 gives a code's evaluation points for field 2 alone; no rule gives the points for code lengths above 2^32 | F:3922-3927 |
| 8 | the four public tables, bit for bit | F:3928-3932 |
| 9 | the layout file and the scale file: R4.9 fixes only that the parameter file comes first; the order layout file, scale file is the programs'. What a sign or a number beyond 64 bits gives in the layout file is left to the C library: "a verifier that admits the plain encoding alone can only reject more" | F:3933-3936 |
| 10 | private randomness | F:3937-3943 |
| 11 | a parser for the items of a first query: "the programs build these items and never read them back" | F:3944-3945 |

### 7.2 Where page and programs are known to differ (17.2)

The last column is this note's reading of what an independent verifier does (inference).

| item | the page | the programs | for an independent verifier |
|---|---|---|---|
| 1 (F:3949-3966) | R0.3: two answers | a third result `NOT CHECKED` when a guard of the library ends a stage or a stage ends under `internal-`: the cases of R2.7, R5.7, R5.3, R7.12, R7.13, R7.16, R7.17, R8.5, R12.14, R13.16, R13.5 and R14.9, the tests on the matrix's units under R13.14, and every misfit between a run and its plan. Also exit codes 14, 2 and 15 | "A verifier with two answers rejects in all of them." Follow the page; compare verdicts as accept / not accept |
| 2 (F:3967-3976) | no guard may depend on a proof's bytes | "Nobody has shown that no file can reach a guard". Known to end `NOT CHECKED`: the rare sampled values of 13.9; public files with more than 4096 stretches of padding in `ranges`; a file of some gigabytes | reject |
| 3 (F:3977-3982) | R0.4 and R14.3: data read out of items | the sub-proofs take call lists, tables and padding from the public files; no item is placed after `binding tree` | follow the programs: the hashed bytes have no such item |
| 4 (F:3983-3988) | R7.14: one session is all files that one verdict reads | three processes, each with its own record of values; no vertex's value is compared between the files | either: "The two differ only on files that show a collision of the hash" |
| 5 (F:3989-3992) | binding tree's depth at most 48 (R14.6); 0 to 64 proof-of-work bits (R5.2); a nonce of 1 to 8 bytes (R8.2) | depth at most 8; parser at most 58 bits and fewer than `sec`, `cp_verify` at most 32; a nonce is always 8 bytes | follow the programs' narrower bounds (they reject more) |
| 6 (F:3993-3998) | R7.3, R15.2, R2.3 | tested elsewhere or slightly otherwise (frame parser admits 15 digits; the bound of R2.3 is tested before the nonce is added) | "No file that `cp_verify` admits shows any of these differences" |
| 7 (F:3999-4001) | whoever forms `request` makes five digests; four more are lines of the file | the programs make all nine, the four tables' among them | a verifier that takes the tables as data takes the item's words from the lines, and checks K(72) (F:1234-1238) |
| 8 (F:4002-4014) | rules for the value 0 of two mask words; one pending row; a table of exponentials; listed positions; a later leaf table | never taken: both words are always 1; `pending rows` is NG + 1, at least 2 (`plan-link`); sT other than sh - 4 ends `NO: policy`; the parser takes `listed` at 0 alone; every parameter file has `salt 40` | these branches can be left out, provided the public files that would need them are rejected as `cp_verify` rejects them |
| 9 (F:4015-4030) | R0.5: one home for each fact | the number of answers is held more than twice, a salt's length three times; the programs derive all from one line. "No rule of this page says what a verifier does where they differ" | derive from the one line; with plan and shapes as inputs, equality is a condition on the inputs |
| 10 (F:4031-4038) | R7.17 (c) and R13.13 are worded more exactly than their short forms | agree at s = 1, the one value the parser takes | follow the page |
| 11 (F:4039-4047) | two fields, `H811` and `H821` | field 2 alone; `H811` is rejected under `version-unknown (policy)` | field 2 alone |
| 12 (F:4048-4062) | R15.6: the three digests under 73 are of the file's own lines, each whole | `cp_verify` forms each text again from what it parsed; a file without a line `call` has no test of its own (it is rejected by `policy-call-list`) | equal under the tests of `policy-call-line`; "That they leave none is this page's reading of the source and is not proved" |

**Compared with no file of the programs and with no second implementation** (F:4064-4078): 8.4's
errors at the two example parameter files; the claims of section 11; the placement of 11.5
beyond its number of rows; the rows of 13.9; the record beyond the honest toy files; whatever
holds only outside the split case; whatever holds only with listed positions; in a chain of
segments, a message kept for more than two segments and a group with h above 0; the meaning of
the words of a lookup, k_lo and the words on the high bits. "That `cp_prove` and `cp_verify` form
the same 177 words (R15.1) in every case that both admit is known from reading their sources."

### 7.3 The scripts (17.3)

- `format_rules.py` has sections 2 to 6, one known answer for section 7, and the encodings and
  rounds of sections 9, 10 and 12; "It has nothing of sections 8, 11 and 13: no sizes, no
  sub-proof of a segment, no test on content" (F:4082-4087).
- `format-vectors.txt` "shows what the script computes, not that the programs compute the same";
  for the commitment ID it "has no case whose numbers fit together" (F:4092-4106).
- `read_key.py`, `read_entry.py`, `read_proof.py` walk a file (queries, proof of work, sampling,
  openings, no byte left) and "make none of the tests on content (13.9)" (F:4108-4110). They
  derive no plan: each takes the bytes of every chain's parameters from files that tools of the
  programs write; for a proof of `cp_prove`, `verifier/tests/first_queries_tool.cpp`
  (F:4129-4132).
- `read_proof.py` has read the tests' two pinned configurations and, reportedly, the stored
  full-size proof (F:4120-4124).

17.4 is not in use (F:4142).

### 7.4 Limits of the programs that bear on a re-implementation (17.5, selection)

| item | content | line |
|---|---|---|
| 1 | the accounting's numbers are the program's own estimate, not a security level | F:4164-4188 |
| 7 | numbers that a plan takes on a routine's word: for some rounds a number from which the error was counted is checked by nothing at the run | F:4247-4262 |
| 9 | no whole list of exact comparisons exists for a soundness statement; section 18's lists "need not be whole" | F:4271-4276 |
| 11 | the library is not an interface: false claims have been accepted in test programs that call its routines directly | F:4288-4309 |
| 12 | `cp_verify` admits parameter files under which the provers make no files: it takes 1 to 20 column variables (`w-shape-lk`), the provers 4 to 18; "nobody has traced whether a `YES` can be reached there" | F:4310-4328 |
| 13 | a leaf file has no authentication of its own | F:4329-4331 |
| 21 | one test on a plan is too strict (all rounds that name the same two codes must name one integer m) | F:4416-4421 |
| 22 | the no-overflow conditions are stricter than field 2 needs | F:4422-4425 |
| 25 | the sub-proofs in `cp_verify` run a second implementation of the smallness test, the lookups and the masked sumcheck; for the key file's proof of ranges `cp_verify` runs the library's own lookup | F:4451-4458 |
| 30 | every example configuration has sT = 4 and sh = 8 | F:4498-4502 |
| 31 | files are opened by name; key file, leaf file and proof file are read whole before their lengths are tested | F:4503-4508 |

## 8. For a formal definition (section 18)

Section 18 "adds no duty of a verifier that derives its numbers from the public files (8.4, the
first way). For a verifier that takes plan, codes and shapes as inputs (the second way), its last
item lists what that verifier asks of its inputs" (F:4549-4552). It does not give a functional
decomposition of the verifier; it gives modelling notes, the contract of the second way, and the
names of the C++ routines that hold each block's conditions.

**Modelling notes** (F:4555-4578):

- no hash of the format is on a string whose first byte is not 0 or 1, and none is made under the
  number 177 (R2.5);
- a hash with 64 bytes of output counts as two queries, so each block of a round's answer is a
  query of its own;
- a verifier's message is a total function of a fixed number of blocks (R6.11): the caps on
  attempts are six for an element of F and two for an element of E that is not 0;
- some public inputs are answers of the oracle (the item `configuration`, a table's root and
  stored answers, a binding tree's root, a seal, the commitment ID): "A model must not fix these
  bytes before O is chosen";
- the nine digests in `request` are values of the second hash function, "which is not O".

**The plan can be taken as an input** (F:4579-4588): in its canonical bytes. Two questions then
lie outside the verifier's definition: whether the plan's numbers are those that section 8
derives, and whether a soundness statement can be made for them. "By R0.2 it never comes from a
key file, a leaf file or a proof file. A plan that the provider hands over would let the provider
choose the errors, so the caller derives it, or has it derived by a program that it trusts like
its verifier, from its own copy of the public files. The same holds of the codes and of the
shapes".

**What is then assumed of the inputs** (F:4589-4605): such a verifier "runs neither the parser
nor steps 3 to 6 and 8 of 8.4, item 23". Two honest forms of a statement: (1) one hypothesis:
plan, codes and shapes of all chains of the three files are what 8.4 gives on one copy of public
files that 8.4 does not reject; (2) explicit conditions, in the lists below. In the source the
conditions are in routines that return nothing or a sentence: `lin_fault`, `index_fault`,
`foldeq_fault`, `link_fault`, `iopp_fault`, `req_fault`, `req_layout_fault`, `wf_fault`,
`key_fault`. Read as a block structure (inference): the test on the table (`lin`), a folded row
(`foldeq`, `index`), the link (`link`), a proximity test (`iopp`), a chain of segments (`req`,
`req_layout`), the proof of ranges (`wf`), a key file (`key`).

The lists:

1. **Parts of the ten conditions on hiding** that such a verifier must ask (F:4607-4650): the
   fourth line of condition 6 ((matrix rows) 2^k_lo at most l - 3 s); condition 10 (the error of
   `LIN point` has the factor 2^depth); condition 4 (the mask message has at least 2 k + 1 - h
   entries at every stage but the last and for every group but the last); condition 3, parts (a)
   to (e), each by the count of free entries; condition 6, first three lines; condition 9, part
   (c) (W's base code is Omega's). "The first two belong among the conditions of a soundness
   statement. The other four are conditions of room".
2. **What else the routines ask, and that carries soundness** (F:4652-4694): every oracle message
   gets an out-of-domain sample (number of answers at least 1), except the fresh mask of a fold
   and the masking word of the last step; some lookup with one digit of weight 1 covers every
   row of the matrix, no digit has the weight 0, no lookup has 2^w keys or more, the padding key
   is below 2^d, d + w is below 64; 3 s < l in a stored table's shape; the first stage of each
   test is the group that it tests; the six words of the tables' shape are the same in
   `the link` and in `the test on the table` of a key file and of a proof; Omega has no mask
   rows, and a split's mask message has mask rows alone; the stages of every proximity test
   close (at least two; 2^k l is the l of the stage before; 2^h l' is at least
   2 l'_0 + r_0 + 2 r'_0 + s; s is at most l'; h is at most k; the last stage has k = 0; a mask
   code is not longer than its base code); a key file's binding tree has depth 0.
3. **Further conditions of room** (F:4696-4705): what a segment's closing carries fits one main
   row; S is below 2^l and 2^lz; the conditions on a block of the layout; a code's length a is at
   most 32.
4. **Conditions stated here alone** (F:4707-4764), per routine (`foldeq_fault`, `lin_fault`,
   `link_fault`, `iopp_fault`, `req_fault`, `key_fault`), and the row of a pad (s at most the
   number of entries of a mask row's message or of a main row over E, 3 s at most that of a main
   row over F).
5. **That plan and shapes fit each other** (F:4766-4790): one round that samples positions for
   each stage of each test; the `LOC` of the stored table samples the shape's number of columns;
   `LINK` samples nu_0 + nu_j positions. Conditions on the plan's own form: the seventh of the
   eight words is 1; at most one entry `RECORD`, as the first entry, only where R13.15 says; the
   second word of an entry `SEAL` (its proof-of-work bits) is 0; the first of an entry's eleven
   words is 1.
6. **That the errors belong to the inputs** (F:4792-4814): every round's error was computed for
   the codes, groups, stored table, rows, combinations and number of requests on which the
   verifier runs; "The hashed bytes do not show it".
7. **What ties the inputs of one chain or file to another's** (F:4816-5049): "A key file has
   three chains, a leaf file one and a proof file three, and an acceptance rests on all seven".
   The ties: three items that two chains of one file both hold (`codes`,
   `the test on the table`, `table`: byte for byte the same); the seals and the binding tree's
   root ("A verifier computes all three and takes none of them as an input"); the depth is in
   one chain, its factor in another; one configuration in all seven chains; one setting; the key
   file's six public values (`configuration`, `codes`, `the test on the table`,
   `index-mask message`, `ranges`, `binding tree`); one matrix and one shape of the tables in
   the three files; the matrix of the segments' claims; the width of a weight; the same tables,
   and files that were accepted; the distances; what a second chain takes from the two others.
   "The ties on a statement's items (seals, roots, tables) are duties of every verifier".
8. **Four things beside the list** (F:5051-5069): a verifier on the second way reads the
   parameter file all the same, for the item `request` and for the segments' sub-proofs; words
   172 to 176 of `request` are B of `sec` and w, b, n, m of `table`, and "nothing compares the
   five words with the shapes"; one comparison every verifier makes on the bytes of files: a
   vertex has one value under one root, whichever chain or file the root came with (R7.14).

A rejected chain's seal is the digest of zeros, known to a malicious prover beforehand, "so a
chain whose statement holds such a seal is rejected from its start" (F:4860-4863).

## 9. A minimal conformance contract for an independent verifier (proposal)

All of this section is a proposal (inference), built on the facts cited.

**Inputs.** The same as a whole call: configuration directory, public key directory, request
file, token file, proof file, `-id`, optional `-policy` (F:2634-2636). Leave `-bits` out: 128 is
the only value under which a call can accept (F:1920-1921).

**O1 — the verdict (must agree on every input).**

| `cp_verify` | the independent verifier |
|---|---|
| exit code 0, last line `YES` | accept, kind `YES` |
| exit code 0, last line `WITHIN LIMITS: clipped-gap C=.. theta=.. cap=.. s=.. sh=..` | accept, kind `WITHIN LIMITS`, the same five numbers |
| exit code 1 (`NO`), 5 (`NOT CHECKED`), 14 (`NOT-A-VERIFICATION`) | not accepted |
| exit code 2 or 15 | no verdict (outside the comparison) |

Basis: R0.3 and "a verifier with two answers rejects" at each of the three (F:1632-1633,
F:1900-1902, F:2354-2355). Never compare on exit code 0 alone: it has two last lines
(F:2671-2672).

**O2 — the rejection name (should agree on single-fault inputs).** The page frees a second
verifier from `cp_verify`'s names and order (F:1586-1588), so this is a testing aid, not a duty.
To agree on names the verifier must reproduce: the order of 3.1 and 3.2; the stage order key,
leaf, request (F:1887-1888); the order of tests inside a stage, for which the source is the only
exact text ("roughly in the order of a run", F:2056-2057). A workable level: exact agreement on
`cp-bits-above-digest`, `policy`, `KL-length`, `version-unknown (policy)`, `cp-key-length`,
`cp-key-head`, `statement-required`, `statement-range`, `token-range`, `cp-proof-length`,
`cp-proof-head`, `cp-entry-missing`, `model-statement`, `key-refused`, `entry-refused`,
`proof-refused`, `reply-differs`; agreement up to the family for public-file names; a sub-proof's
prefix dropped, as the Lean verifier does (LTREES:58-59).

**O3 — on an acceptance, the fields that are functions of the inputs alone.** From `result-v1`:
`status`, `claim`, `id`, `bits`, `record`, `r`, `e`, `T`, `tokens`, `y`, `policy`, `C`, `theta`,
`cap`, `s`, `sh`, `sT`, `F`, `above-clip`, `leaf`, `stages`, `dw` (F:3120-3142). From
`covered:`: the line up to the blank before its bracket (CPP:2997-3001). The computed commitment
ID (equal to `-id` by O1).

**Legitimately implementation-specific.**

- The fields that need the error accounting: `work`, `work-rounds`, `least-round`,
  `least-round-without-work`, `commitment-assumed-rounds`, and the lines `proof of work:`,
  `commitment:`, `accounting:` (the page does not define the accounting: F:3876-3883). They can
  agree only if the accounting is ported.
- `build=` (a digest of `cp_verify`'s own sources, F:3142).
- Three processes, threads, `-j`, `-q`, `-show-stages`, timings, headings, progress lines, the
  stages' output and their lines `result:` (F:1830-1831, F:2663-2665).
- The classes `NOT CHECKED` and `NOT-A-VERIFICATION`, exit codes 2, 3, 4, 5, 14, 15, part-calls,
  planning calls, the usage text, the text after `cannot be read:`, the reasons.
- The causes that are "this command's own": test build, `-next-token`, `-no-proof-of-work`
  (F:2805-2806).
- How the four public tables are obtained (computed or taken as data), provided K(72; table) is
  checked against the 32 lines (F:1235-1238).
- The layout file's lenient encodings: admitting the plain encoding alone "can only reject more"
  (F:3935-3936), so O1 can differ on such files only as `cp_verify` accept against reject.
- Bounds of kind (b) and the hiding conditions of kind (c) other than the three parts
  (F:1596-1617): a verifier that leaves them out "accepts under some configurations under which
  `cp_verify` rejects". For O1 to agree on altered public files, either port them or keep such
  files out of the test set.

**Where O1 is known to be probabilistic or machine-dependent.** The nine sampled-value events
(`NO: coin-zero` or `NOT CHECKED`, chance about 2^-109 per full-size proof, F:2503-2507);
`table-digest-<name>` on a machine whose floating-point library differs (OUT:345); files of some
gigabytes (F:3974-3976).

**Ready test material named by the pages.** `examples/accepted-proof` with the `result-v1` line
of F:3118 and the closing lines of VER:291-304; the same proof with one bit flipped, whole output
at OUT:98-102; 57 known answers of K and TK in `verifier/tests/hash_vectors.txt` (F:1544-1550);
the Lean verifier's names (LTREES:41-59).

## 10. Open questions and ambiguities

1. **First way or second way.** Port the derivation of sizes, plans and round errors (section 8,
   no numbered rules) into Bend, or take plan, codes and shapes as trusted inputs made by a tool
   from the caller's own public files? The page expects the second of a second verifier
   (F:3881-3883) and then section 18's hypotheses apply; `security-bits`, condition 2 of 13.7 and
   the proof-of-work fields cannot then be decided by the verifier itself (inference).
2. **The four public tables.** They are in no file (F:3980-3982). Where does a U32-only verifier
   get them: an extra trusted input checked by K(72), or a port of the floating-point formulas?
   The rule allows the first (F:1235-1238). The fifth table (the head's, by an integer
   recurrence) is defined in 11.4, outside this scope.
3. **Two answers or five classes.** R0.3 asks two; `cp_verify` has five. Which does the Bend
   verifier expose, and is `NOT-A-VERIFICATION` (missed conditions of 13.7) reported apart from
   `NO`?
4. **How exact must name agreement be.** The order of tests inside a stage is given only
   "roughly" (F:2056-2057); exact agreement needs the C++ source as the reference.
5. **Tests named without a formula** (F:1621-1622): among them `policy-call-list` ("present in
   this form of the model", "has the call's kind"), the single conditions behind
   `parameters-not-admitted` (F:3912-3914), `plan-layout` ("fits the codes"), most `hid-` and
   `forest-` formulas. Sections 8 and 11 or the source must supply them.
6. **Kind (c).** Port all ten conditions on hiding for parity with `cp_verify` on altered public
   files, or only the three parts that every verifier asks (F:1601-1617)?
7. **The layout file.** Reproduce `sscanf`'s leniency (signs, leading zeros, no blank around the
   letter, numbers beyond 64 bits "left to the C library", F:1788-1794) or admit the plain
   encoding alone?
8. **The call lines' text** (17.2, item 12). Hash the file's bytes (R15.6) or the re-formed
   text? They are held to be equal on every admitted file, unproved (F:4056-4057).
9. **`security-bits`, third part.** "some round of the plan has an error above 0"; the page "does
   not say whether a file that has passed the earlier tests can miss that part" (F:2218).
10. **R7.14 across files.** One record of vertex values for the whole call (the rule) or one per
    file (the programs)? They differ only on a hash collision (F:3983-3988).
11. **Which CLI surface is in scope.** `-bits`, `-next-token`, `-no-proof-of-work`, the part-calls
    and the planning calls are `cp_verify`'s own; none is needed for O1.
12. **Inference to confirm.** With e < T the proof's `REPLY` element must be 0, since the caller's
    y is 0 and the comparison is made in every call (1.8). Stated nowhere in one sentence.
13. **Inference to confirm.** R of 12.5 and n of 14.3 are the same number (1.2); the page uses
    both letters (F:1389-1390 against F:1964).
14. **Parity detail.** The length test before the stages is made for `lt` up to 20 (F:2086),
    while every stage rejects `lt` above 16 (`shape-words`, F:2111): for 17 to 20 a wrong length
    wins over `shape-words`.
15. **The Lean verifier as a second reference.** It keeps the C++ names for comparison
    (LTREES:41-42) and covers one format and one size (VER:485-488). Whether it is a better model
    for a functional decomposition than section 18 was not examined here.
