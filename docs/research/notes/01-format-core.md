# 01 — Format core: FORMAT.md sections 1–7, `format_rules.py`, `format-vectors.txt`

> Status: frozen
> Recovered working notes, 2026-11-23. Upstream excerpts from FlashProve, Copyright 2026 Anthropic PBC, Apache-2.0.

Source: FlashProve 0.16.0-rc.26, commit 9e2bdd8, directory `docs/format/`. Purpose: implementation-grade digest for a from-scratch verifier (field 2, version word `H821`).

**Citation aliases.** `F:n` = `docs/format/FORMAT.md:n` · `py:n` = `docs/format/format_rules.py:n` · `vec:n` = `docs/format/format-vectors.txt:n` · `README:n` = `docs/format/README.md:n`.

**Markers.** *[derived]* = follows by plain arithmetic from the cited text but is not written there. *[inference]* = my reading; may be wrong. *[checked]* = confirmed numerically (0.2). Unmarked claims are stated by the cited lines.

**Notation.** `word(x)` = 8 bytes little-endian; `‖` = concatenation; `0^n` = n zero bytes; `p = 2^64 − 2^32 + 1 = 0xFFFFFFFF00000001`.

### 0.1 What was read

| file | lines | status |
|---|---|---|
| `README.md` | 1–89 | read in full |
| `FORMAT.md` | 1–1105 (preamble, sections 1–7) | read in full |
| `format_rules.py` | 1–1023 | read in full |
| `format-vectors.txt` | 1–227 | read in full |
| `FORMAT.md` | 1183–1304 (R15.1–R15.7), 1401–1449 (head of 12.6) | read only to pin the second hash function; outside the assigned scope |

Nothing else of the repository was read, apart from one grep of FORMAT.md for the headings of sections 12–18 and the first line of each item of 17.2 (to give line pointers in section 12). Everything that sections 1–7 point to but define elsewhere is listed in section 12.

### 0.2 What was executed (read-only; upstream tree unchanged afterwards)

- `python3 -I -B docs/format/format_rules.py` (Python 3.15.2) reproduces `format-vectors.txt` byte for byte: 227 lines = 26 `#` lines + 201 known answers. *[checked]*
- A scratch check (not kept as a file) confirmed against the reference script and the vectors: H computed from the compression function alone with the initial state of 3.1; the label built from 32-bit limbs; the 32-bit-limb rotations and canonical test of section 11; the dry walk of 10.6 against `walk` (600 random lists, depth ≤ 6) and R7.9's bound; the word-stream reading of 5.1 for w = 0 and w > 0 against vec:22–29. *[checked]*

---

## 1. Objects and vocabulary

FORMAT.md states its own authority: on bytes, hashed strings, order and tests it "takes precedence over every other page of the repository" (F:16–17). Unnumbered text binds like a numbered rule "wherever it says what a verifier hashes, derives or rejects" (F:39–41). "A verifier rejects .." is a duty of every verifier; MUST / MUST NOT mark duties of a committer, prover or operator "whose breach no verifier can see" (F:44–45). Names in code marks are literal bytes of the format because they are hashed (F:45–47).

### 1.1 Glossary

| term | meaning | cite |
|---|---|---|
| byte / word | 8 bits / integer in [0, 2^64), 8 bytes lowest first | R1.1 F:96–97 |
| F, E | base field Z/p; extension F[X]/(X^3 − c) | R1.2 F:98–100; R1.4 F:105–108 |
| digest | any 32 bytes | R1.5 F:109 |
| text; string of bytes | length word, then the bytes; names are ASCII | R1.6 F:114–115 |
| list; pair | count word then values; first part then second | R1.7 F:116–118 |
| H | the one hash: BLAKE2b with a 16-byte label in front of the hashed bytes | F:130–131; R2.1 F:139 |
| hash's label | first 16 bytes of the hashed string: `word(number + 2^16 tree + 2^32 W + 2^56 s8)`, `word(index)` | R2.1 F:142–146 |
| number / tree / index / start | H's four arguments; *start* is fed as BLAKE2b salt and personalization | R2.1–R2.2 F:139–155 |
| second hash function (K, TK) | fixed function on BLAKE2b's compression function, used inside one item only | F:131–132; R3.5 F:244–248; R15.3 F:1211 |
| public files; configuration | parameter file, layout file, scale file (`policy.txt`, `layout.txt`, `KL.bin`); together a configuration | F:63 |
| configuration's digest | H(169, 0, 2, …) of the public files; item `configuration` | F:64; R4.9 F:372 |
| stored table; anchor; leaf table | weights encoded row by row, columns are leaves of a Merkle tree; first of a commitment = anchor; a further one with the same rows under fresh randomness = leaf table, number k from 0 | F:65; F:264–272 |
| stored table's name | root ‖ configuration's digest ‖ six words = 112 bytes | R4.10 F:385–391 |
| record (of a stored table); stored answers | the list of the stored answers to the table's own out-of-domain sample, the same number for each row | F:268–269 |
| out-of-domain sample; seed; answer (to it) | seeds are sampled, "each a point and a factor"; the committer/prover gives answers, elements of E | F:265–267; R6.9 F:539 |
| commitment ID | H(179, …) of configuration's digest, anchor's name, record's seeds and answers; "given to the verifier by its caller"; `published_id` in the script | F:69; R4.11 F:400 |
| key file / leaf file / proof file | `key.bin` begins `CPIK`; `leaf/<k>.bin` begins `CPEN`; proof file begins `CPPF` | F:66, F:67, F:72 |
| link | the tie between the anchor and a leaf table; the chain of a leaf file | F:68 |
| request; next token | the caller's request file and token file | F:70 |
| acceptance policy | seven lines of the parameter file (12.5) | F:71 |
| batch; slot | requests that share one opening of a leaf table; a request's slot = place of its leaf in the batch's binding tree | F:73 |
| binding tree | a batch's tree; leaves under 173, vertices under 178 | R7.18 F:788–792 |
| segment; sub-proof | one step of a request's walk through the model, with its sub-proof; rounds of a proof's first chain | F:75 |
| caller / client / provider | caller runs the verifier (as a rule the client); provider supplies the public key directory and the proof file | F:77–80 |
| chain | one interactive protocol made non-interactive by Fiat–Shamir | F:253–254 |
| chain's label | integer that says which protocol (and in which kind of file); below 2^32 except the label 2^32 of R4.8 | F:254–257 |
| first query; first value rho_0 | the hash that gives the chain's first value; what is among the parameters or in the statement "is said to be in the first query" | F:258–260; R4.6 F:330 |
| parameters; statement | two lists of named items; parameters are "what is fixed before a request is known" | R4.1 F:277–278 |
| item (named) | name (text), length word of the value, value bytes | R4.1 F:278–280 |
| item (of a chain in a file) | unnamed, unlengthed piece of a chain's bytes | R4.1 F:280–281; R8.1 F:869 |
| plan; entry | eight words plus entries; an entry = round's name (text) and eleven words | R4.3 F:292–308 |
| `RECORD` entry | a plan entry that is not a round of its chain (a stored table's own out-of-domain sample); "the chain's rounds pass over it" | R4.3 F:309–313 |
| parameters' digest | H(169, 0, 1, none; parameters' bytes) | R4.4 F:314 |
| random bytes; run's value | 32 bytes, cases (a)/(b)/(c); run's value = H(172, 0, label, none; parameters' digest, random bytes) | R4.5 F:315–319 |
| run; commit run | one commit run for a key file or leaf file, or one batch with its proofs; a commit run builds one stored table / key file / leaf file | R4.5 F:320–323 |
| record field | a field of the first query that no chain fills (length word 0) | R4.6 F:337–338 |
| round; prover's message; verifier's message | rounds numbered 1, 2, ..; each prover's message is followed by a verifier's message (possibly empty) | R5.1 F:441–442 |
| kind | 1..7, what the verifier's message consists of | R5.2 F:453–456 |
| call C_i(j) | 64-byte hash number 162 of round i, counter j | R5.2 F:448–450 |
| answer (of a round); block | sequence of 32-byte blocks B_0, B_1, ..: halves of the calls | R5.4 F:466–467 |
| test block; nonce; w | proof-of-work: low w bits of the first word of the test block are 0 | R5.5 F:476–477 |
| seal | digest sampled in a round of kind 6; "A seal is in no file." | R6.8 F:535–538 |
| draws; list | positions in the order sampled, repeats kept; the set of sampled positions in increasing order | R6.6 F:523–524 |
| oracle message | a message the prover does not send in full; rows that are code words | F:575–576 |
| tree; part; group | a tree holds the oracle messages (or parts) sent in one prover's message and read at the same lists; what it holds of one oracle message is a part; a group = oracle messages under one proximity test | F:577–580 |
| main rows; mask rows | length 2^a, read at x; length 2^b (b ≤ a), read at the short position of x | F:582–584 |
| shape (of a tree) | a, b, per-part element counts of main and mask rows per column, stored or not, salt length | F:586–590 |
| column; short position | list of W field elements at position x; x mod 2^b | R7.1 F:594–598; R7.2 F:601 |
| fill; salt (of a leaf) | zero padding that is hashed and in no file; s bytes per leaf | R7.3 F:608–621 |
| stored tree | the tree of a stored table: number 174, start = configuration's digest, tree's number 0 | R7.4 F:626–628 |
| vertex (d, i); place | depth d, place i in its level; root (0, 0); leaf of position x is (a, x) | R7.6 F:647–649 |
| opening; given digests; walk | columns and salts at the list, then sibling digests in the walk's order | R7.8 F:661–664; R7.9 F:665 |
| record of values | per-root map from 2^depth + place to the one admitted value, within a session | R7.14 F:692–701 |
| session | "one run of a verifier that ends in one verdict: all chains of a file, and all files that one verdict reads" | R7.14 F:703–704 |
| leaf class; notice | a number in an oracle message's notice (R12.3) that decides tree sharing | R7.12 F:721–722 |
| chain's list of trees; tree's place; tree's number | place = index in the reading chain's list; number = the place it got in the list of the chain that sent it (goes into leaf labels) | R7.13 F:737–751 |
| continue; adopt | a chain begins with an earlier chain's whole list; a chain takes one tree of another chain | R7.13 F:740–747 |
| one-time / shared / second chain; link's chain; first chain | the seven chains of the three files | F:982–990; F:1012–1014; F:1026–1031; F:1072–1080 |
| toy run | a small run of the library `blocks/` on synthetic data; its configuration is one public file | R4.9 F:377–380; README:84 |

### 1.2 Homonyms that an implementer must keep apart

| word | senses | cite |
|---|---|---|
| label | chain's label (integer argument) vs hash's label (16 bytes) | F:254; F:146 |
| answer | round's answer (blocks) vs answer to an out-of-domain sample (element of E) vs stored answers (a record) | F:466; F:266; F:268 |
| record | stored table's record vs record of values (R7.14) vs record field (R4.6) vs plan entry `RECORD` vs the file name `record.f2.txt` | F:268; F:700–701; F:337; F:310; F:888 |
| item | named item (R4.1) vs item of a chain in a file (R8.1) | F:280–281 |
| place | a vertex's place in its level vs a tree's place in a chain's list | F:738–739 |
| number | H's number vs a tree's number vs the leaf table's number in a proof head | F:205; F:749; F:1036 |
| salt | BLAKE2b's field "salt" (= start[0:16]) vs a leaf's salt (part of *bytes*) | F:160 |
| W | words of a leaf's content (R2.1) vs the oracle message W of R14.4 (e) | F:147–148; F:779–780 |
| row | row of a table / code word vs "a linear equation on what oracle messages commit to" | F:306–307 |
| link | prose: tie between anchor and leaf table; in `group link`, `stages link`, `links' identifiers`, `the chain of links`: a request's segment | F:47–52 |
| leaf | leaf of a tree vs leaf table / leaf file ("entry" in rejection names) | F:67 |
| word | 64 bits everywhere, but 32 bits inside R15.x / 12.6 | F:96; F:1409 |
| F | the field vs BLAKE2b's compression function in 12.6 | F:1419 |

---

## 2. Bytes and elements

Principle: the same rules hold for hashed strings and files; every object has exactly one encoding (R0.1), so "hashing the encoding of a parsed object and accepting only canonical encodings come to the same thing" (F:84–87; R1.9 F:120).

### 2.1 Encodings

| object | bytes | cite |
|---|---|---|
| word | 8 bytes, lowest byte first. "Nothing in the format is encoded highest byte first." | R1.1 F:96–97 |
| element of F | the word that is its least non-negative residue | R1.3 F:101 |
| element of E, e_0 + e_1 X + e_2 X^2 | e_0, e_1, e_2 in this order: 24 bytes | R1.4 F:107–108 |
| digest | its 32 bytes, no length before them. As four words: word i = bytes 8i..8i+7 (little-endian) | R1.5 F:109–111 |
| digest as the whole value of an item | the item's length word 32, then the 32 bytes (no second length) | R1.5 F:111–112; R4.1 |
| stored table's root inside its item | string of bytes: word 32, then 32 bytes | R1.5 F:112–113; R4.6 F:344–345 |
| text; string of bytes | length as a word, then the bytes as they are | R1.6 F:114–115 |
| list | count of values as a word, then each value by its own rule. "A string of bytes is not a list of integers" | R1.7 F:116–117 |
| pair | first part, then second | R1.7 F:117–118 |
| integer; truth value (0 or 1); enumeration member | one word | R1.8 F:119 |

Reference encoders: `u64` py:58–59, `string` py:62–63, `text` py:66–67 (ASCII), `ext` py:70–71, `item` py:75–76.

### 2.2 Integers that are not 8-byte words (each by a rule of its own, F:87–92)

| integer | width | cite |
|---|---|---|
| version word in a file's head | 4 bytes (`H821`) | R13.1 F:974–976; F:88–89 |
| a proof file's number | 4 bytes, lowest first | R14.2 F:1035–1036 |
| a nonce in a file | the plan's number of bytes of a nonce (1 to 8), low bytes, lowest first, other bytes 0 | R8.2 F:881 |
| a listed position in a file | the plan's number of bytes of a listed position, lowest first | R8.2 F:882 |
| words of the item `request`, of the request file, of the token file, of `KL.bin` | 32 bits | F:90–91; R15.1 F:1196 |
| four numbers in the hash's label | share one word: number, tree, W, s8 | R2.1 F:142; F:91 |

Public files are not encoded by section 2: "Their bytes are hashed as they are in the file (R4.9)" (F:92–94).

### 2.3 What a reader rejects (canonicality)

- 8 bytes whose word is not below p, as an element of F (R1.3 F:101–102). Field 2 *[derived, checked]*: reject iff high 32 bits = 0xFFFFFFFF and low 32 bits ≠ 0. Known answers: `00000000ffffffff` → 18446744069414584320 = p − 1 accepted; `01000000ffffffff` (= p) and `ffffffffffffffff` rejected (vec:61–64).
- An element of E if one of its three coordinates is rejected (R1.4 F:108).
- A truth value that is not 0 or 1; a member of an enumeration that is not one of its numbers; a length greater than the number of bytes left; a name with a byte outside 0x20 to 0x7E (R1.9 F:120–123).
- A list: the length counts values, each of at least one byte, "so the same test on the length holds; a list also fails where the bytes run out" (R1.9 F:123–125).
- "The types of R4.2 have the same duty." (F:126).
- A digest is never rejected: "any 32 bytes are a digest" (F:859–860).
- The encoding test is not the sampling map of R6.3 (F:102–104). In field 2 both are the test `w < p`; they differ only in field 1 *[derived from F:512–514]*.

### 2.4 The fields

- Field 2: p = 2^64 − 2^32 + 1; field 1: p = 2^61 − 1. "A program is built for one field; the programs of this repository can be built for field 2 alone (from the programs' source). Field 2 is the reference." (R1.2 F:98–100; `PRIME` py:29.)
- E = F[X] / (X^3 − c), c = 2 in field 2 (c = 5 in field 1). 3 divides p − 1 and c^((p−1)/3) ≠ 1, so the polynomial is irreducible (R1.4 F:105–107; asserted py:797–798).
- Multiplication rule *[derived from X^3 = 2; not written in sections 1–7 and not implemented in `format_rules.py`, which has no arithmetic in E]*: for a = (a0, a1, a2), b = (b0, b1, b2),
  - c0 = a0·b0 + 2·(a1·b2 + a2·b1)
  - c1 = a0·b1 + a1·b0 + 2·a2·b2
  - c2 = a0·b2 + a1·b1 + a2·b0
- Constants of E used by sections 1–7: zero is (0, 0, 0) and "the element is 1" is (1, 0, 0) (R6.5 F:519–520; py:176–178).
- Sections 1–7 need no arithmetic in F or E: elements are parsed, compared with 0, re-encoded and hashed *[inference from the whole scope]*.

### 2.5 The version word

As a parameter item's value: one word "whose four low bytes are, from the lowest, the ASCII characters `H`, `8`, the field's digit and the hash's digit `1`, and whose other bytes are 0": `H821` = 0x31323848 for field 2 (R4.3 F:288–291; py:89–90; bytes `4838323100000000` in vec:15). In a file's head: the four bytes `H821` (R13.1 F:975–976). The programs serve `H821` alone (F:291).

---

## 3. The hash

### 3.1 H: exact BLAKE2b parameterization

Definition (R2.1 F:139–146): every hash of the format is H(number, tree, index, start; bytes) = BLAKE2b "exactly as it is specified, in its sequential mode and without a key" of the string

    word(number + 2^16·tree + 2^32·W + 2^56·s8) ‖ word(index) ‖ bytes

"with *start* as its salt and personalization". W and s8 are 0 except under the three leaf numbers 164, 173, 174, where W = number of words of the leaf's content and s8 = number of words of its salt (F:147–148).

Parameter block P, 64 bytes (R2.2 F:152–155):

| bytes of P | content |
|---|---|
| 0 | digest length: 32; under the number 162: 64 |
| 1 | key length: 0 |
| 2, 3 | fanout 1, depth 1 |
| 4–31 | 0 |
| 32–47 | BLAKE2b's "salt" = bytes 0–15 of start |
| 48–63 | BLAKE2b's "personalization" = bytes 16–31 of start |

"The last-node flag is never set." (F:155). Reference one-liner (F:158; py:39–49):

    hashlib.blake2b(struct.pack("<QQ", number + (tree << 16) + (W << 32) + (s8 << 56), index) + bytes,
                    digest_size=32 or 64, salt=start[:16], person=start[16:]).digest()

Facts for an implementation from the compression function *[derived from R2.2; checked against hashlib for 11 lengths including exact multiples of 128]*:

- Initial state h = IV xor P read as eight little-endian 64-bit words: h[0] = IV[0] xor 0x01010020 = `0x6a09e667f2bdc928` (32-byte digest) or IV[0] xor 0x01010040 = `0x6a09e667f2bdc948` (64-byte digest, number 162); h[1..3] = IV[1..3]; h[4+i] = IV[4+i] xor LE64(start[8i .. 8i+8]) for i = 0..3. With start "none" (32 zero bytes) h[4..7] = IV[4..7].
- The 32-byte digest is the first four state words, not a truncation of a 64-byte digest (h[0] differs).
- The hashed string is never empty (16-byte label), so there is always at least one block; a final block that is exactly 128 bytes is compressed once with the last-block flag and the counter = total length.
- Byte view of the label's first word *[derived; visible in vec:4]*: bytes 0–1 number, bytes 2–3 tree, bytes 4–6 W, byte 7 s8; under 162 bytes 2–7 are the chain's label (48 bits). Bytes 8–15 are index.
- RFC 7693 "prints only the block's first four bytes" (F:150–151): salt and personalization are in the BLAKE2 paper, section 2.8 (F:148–150). An implementation written from the RFC alone lacks them.

Argument bounds (R2.3 F:161–166): number is one of thirteen (below); tree < 2^16, under 162 < 2^48, and 0 where R3.1 leaves the cell empty; index < 2^63; under a leaf's number 1 ≤ W < 2^24 and s8 is 5 to 8; *bytes* has at most 2^32 − 144 bytes; start is a digest under the numbers to which R3.1 gives one and 32 zero bytes ("none") under the others. *[derived]* The whole hashed string therefore has at most 2^32 − 128 bytes, so BLAKE2b's byte counter stays below 2^32.

Rejections tied to these bounds (R2.7 F:191–198): a verifier rejects parameters, a statement, a round's message or a leaf's bytes that would make a hashed string longer than R2.3 admits; "a chain of 2^63 rounds and a tree in which 2^a + position reaches 2^63"; public files that together are too long (input of R4.9); a record whose seeds and answers would make the commitment ID's input too long.

Reserved (R2.5 F:183–185): no hash is made under 177. Cost (R2.6 F:186–190): ceil(n/128) compressions for n > 0 bytes; a vertex (80 bytes) costs one; call j of a round costs one if the prover's message has at most 96 bytes; a program that keeps the state after the message's whole blocks pays one compression per further call j, two if the message has 104 bytes modulo 128.

The "oracle's string" (R2.4 F:167–182) is a proof device, not something to compute: one byte for the half (0x00; 0x01 for the second 32 bytes of a 64-byte digest), then P, then the label, then bytes; at least 81 bytes. `oracle_string` py:52–54; vec:4–5 show P and the label in hex and are a cheap test of both layouts.

### 3.2 The uses (R3.1, F:205–228)

"An empty cell means 0 for *tree* and 32 zero bytes for *start*." (F:205–206.) The script's sets: `NUMBERS` py:33, `START` py:32, `LEAVES` py:36.

| number (hex) | use | tree | index | start | bytes | digest | does a verifier's test depend on it |
|---|---|---|---|---|---|---|---|
| 160 (0xA0) | a chain's first value | 0 | the chain's label | none | R4.6 | 32 | yes |
| 162 (0xA2) | a call of a round's query | the chain's label | the round, 1, 2, .. | the chain's value before the round | R5.2 | 64 | yes |
| 164 (0xA4) | a leaf of a tree made in a run | the tree's number | 2^a + position | the run's value | R7.3 | 32 | yes |
| 166 (0xA6) | a vertex from its two children | 0 | 0 | the configuration's digest | left digest, right digest | 32 | yes |
| 168 (0xA8) | the digest of a statement | 0 | which writer | none | its bytes | 32 | no (F:206–211) |
| 169 (0xA9) | the digest of parameters | 0 | 0: a parameter file's text; 1: the bytes of R4.3; 2: the configuration (R4.9) | none | their bytes | 32 | index 1 and 2 yes; index 0 "enters no test and no other hash" (F:209–211) |
| 171 (0xAB) | synthetic randomness of tests and toy runs | 0 | a counter | the test's seed | none | 32 | no |
| 172 (0xAC) | a run's value | 0 | the chain's label | none | R4.5 | 32 | yes |
| 173 (0xAD) | a leaf of a batch's binding tree | 0 | 2^depth + place | the configuration's digest | R7.18 | 32 | yes |
| 174 (0xAE) | a leaf of a stored tree | 0 (R7.4) | 2^a + position | the configuration's digest | R7.3 | 32 | yes |
| 176 (0xB0) | the digest of named inputs (committer's / prover's private generator) | 0 | 0 | none | not defined on the page | 32 | no ("no verifier computes it") |
| 177 | reserved (R2.5) | | | | | | never |
| 178 (0xB2) | a vertex of a batch's binding tree | 0 | 0 | the configuration's digest | left digest, right digest | 32 | yes |
| 179 (0xB3) | the commitment ID | 0 | 0 | none | R4.11 | 32 | yes *[inference: the caller gives it (F:69); where it is compared is 13.5, outside this scope]* |

Further rules: a number gets no second meaning; 161, 163, 165, 167, 170, 175 are never given a use; numbers below 160, and 240 and 241, are not numbers of H; the second hash function has numbers of its own, 10, 11, 72, 73 (R3.2 F:230–231). "A leaf's string is never a vertex's: the numbers differ." (R3.4 F:243). "A verifier of this format makes no hash but H", with the one exception R15.3 (R3.5 F:244–246). R3.6 is not in use (F:249). Where the public parameters are bound: R3.3 F:232–242.

### 3.3 Input layout of every use a verifier needs

Offsets are in the BLAKE2b input (label included). All integers little-endian.

**(a) Configuration's digest** (R4.9 F:372–375; `configuration_digest` py:93–94). 32-byte digest, start none.

    0   8  word(169)
    8   8  word(2)
    16  8  word(number of public files)
    ..     for each file, in order: word(its length), its bytes

"The parameter file comes first. The programs of this repository take three files: the parameter file, the layout file and the scale file, in this order" (F:373–375). Known answer for one file `toy\n`: vec:115.

**(b) Parameters' digest** (R4.4 F:314; py:109–110): `word(169) ‖ word(1) ‖ parameters' bytes` (4.2 below). Known answer: vec:15 → vec:16.

**(c) Run's value** (R4.5 F:318–319; py:113–114): 80 bytes, one compression.

    0   8   word(172)
    8   8   word(chain's label)
    16  32  parameters' digest
    48  32  the chain's random bytes

**(d) First value rho_0** (R4.6 F:330–338; py:117–120).

    0     8   word(160)
    8     8   word(chain's label)
    16    32  parameters' digest          (32 zero bytes in the chain of R4.8)
    48    8   word(length of the statement's bytes)
    56    L   the statement's bytes
    56+L  8   word(0)                     record field's length; "always the word 0, and no byte of the field follows"
    64+L  8   word(1) in cases (a), (b);  word(0) in case (c), and the string ends here
    72+L  32  the run's value             cases (a), (b) only

**(e) Call j of round i** (R5.2 F:448–450; `Chain.call` py:133–135). 64-byte digest; salt = rho_(i−1)[0:16], personalization = rho_(i−1)[16:32].

    0     8   word(162 + 2^16·label)      label < 2^48
    8     8   word(i)                     i = 1, 2, ..
    16    M   the prover's message        M is a multiple of 8
    16+M  8   word(kind + 2^8·w + 2^16·j) j < 2^48
    24+M  8   word(nonce)

Known answers: vec:12 (label 2^32, round 3, message pattern(8), kind 4, w 8, j 1, nonce 5), vec:13 (label 0, no message, kind 1).

**(f) Leaf of a run's tree (164) or of a stored tree (174)** (R7.3–R7.4 F:608–637; `leaf_bytes` py:223–228, `leaf` py:231–233). Start = run's value (164) or configuration's digest (174).

    0     8   word(number + 2^16·tree + 2^32·W + 2^56·(s/8))
    8     8   word(2^a + x)
    16    8W  the column: W elements of F
    ..    f   the fill: f zero bytes (6.3)
    ..    s   the salt

**(g) Leaf of a binding tree (173)** (R7.18 F:788–792; py:236–238): as (f) with number 173, tree 0, index 2^depth + place, start = configuration's digest, column = the seal's 32 bytes read as four words (W = 4), fill empty, then the salt.

**(h) Vertex (166) and binding-tree vertex (178)** (R7.7 F:650–654; py:241–247): 80 bytes, one compression; start = configuration's digest.

    0   8   word(166)  or  word(178)
    8   8   word(0)
    16  32  left child's value
    48  32  right child's value

Known answers: vec:10 (166), vec:11 (178).

**(i) Commitment ID** (R4.11 F:400–408; `published_id` py:101–106): start none.

    word(179) ‖ word(0)
    ‖ configuration's digest (32)
    ‖ word(112) ‖ the anchor's name (112)
    ‖ word(s·(c+1)) ‖ for each of the s seeds: its c point coordinates, then its factor (24 bytes each)
    ‖ word(number of answers) ‖ the record's answers, 24 bytes each, by row and within a row by answer
    ‖ word(0)

"That last word closes the string. It is an empty list … A second implementation must not leave it out." (F:405–407.) The seeds' list has no word c of its own (F:407–408). The configuration's digest is in the input twice (by itself and as bytes 32–63 of the name), on purpose (F:413–415). Known answers: vec:140–141.

### 3.4 Domain separation and literal strings

- Separation is by the 16-byte label and by *start*; no ASCII string is ever used as BLAKE2b's personalization *[derived from R2.1–R2.2]*. "the three uses under 169 differ in the index, so no two uses ever hash the same string" (F:132–133).
- Literal strings enter hashed bytes only as names, encoded as text (length word + ASCII). Seen in this scope: item names `the format's version` (F:288; ASCII apostrophe 0x27, vec:15), `configuration` (F:298), `table` (F:343), `the first table`, `the further table`, `stored copy` (F:65), `the seal of an earlier chain` (F:359), `the binding tree's root` (F:329), `binding tree` (F:73), `request`, `the request file's words` (F:70), `the link` (F:68), `links' identifiers` (F:49), `the chain of links` (F:52), `the test on the table` (F:780), `ranges` (py:787); round names (plan entries) `RECORD` (F:310), `LINK`, `LINK point`, `LINK phi` (F:68), `REPLY` (F:70), `PSC Y` (F:506), and from the script `PSC epsilon`, `PSC round`, `PSC values`, `LINE` (py:429–434), `LKP`, `JOIN`, `ZERO` (py:439–447), `BAT`, `FOLD epsilon`, `FOLD round`, `SEND seed`, `CS`, `BASE lambda`, `BASE` (py:454–458), `SEND answer`, `BAT-sigma`, `SEAL`, `LIN point`, `LOC`, `LIN zeta`, `SPLIT` (py:466–479). The authoritative lists are in sections 9–11 and R14.11 (outside this scope).
- File magics (not hashed, compared): `CPIK`, `CPEN`, `CPPF`, then `H821` (F:975–976, F:1035–1036).

### 3.5 The second hash function K and TK (R15.3; defined outside sections 1–7)

Sections 1–7 only announce it (F:131–132; R3.2 F:230–231; R3.5 F:244–248). Normative text: R15.3 F:1240–1252 and 12.6 F:1421–1449. Reference: `blake2b_init_param` py:574–579, `blake2b_F` py:605–622, `older_K` py:625–636, `older_TK` py:639–647. "In this part a word has 32 bits" (F:1409).

**K(num; w)**, num < 2^32, w a list of n 32-bit words, n < 2^32 (F:1243–1250):

1. State = BLAKE2b's IV "with 0x01010040 xored into its first word" (digest length 64, no key, fanout 1, depth 1, no salt, no personalization) (F:1244–1245; F:1425–1426; py:629).
2. Cut w into blocks of 32 words, "at least one" (also when n = 0); fill the last with zero words (F:1245–1246; F:1431–1432; py:628–632).
3. Two 32-bit words make one 64-bit word, the low one first: m[i] = w[2i] + 2^32·w[2i+1] (F:1242–1243; py:633).
4. Block j (from 0) is one call of the compression function. Low 64 bits of the counter t = bytes fed up to and including this block: 128·(j+1), and 4·n in the last call. High 64 bits of t = num + 2^32·n in every call. The flag is set in the last call alone (F:1246–1248; py:634–635).
5. Digest = "the first eight words of the last state: the first four words of 64 bits, each low half first" (F:1248–1250; py:636).

**TK(w)**, w of at least eight words (F:1250–1252; F:1439–1449; py:639–647): cut w into pieces of 128 words (the last may be shorter), replace each by K(10; piece) with n = that piece's own length; while more than eight words are left, do the same to the list of digests under the number 11. "TK of eight words is K(10; w), not w." (F:1447.)

Where it is used: only in the item `request` (nine digests: five computed by whoever forms the item, four are lines of the parameter file, which the programs also compute and compare) (R3.5 F:246–248; R15.3 F:1211–1214). The digests: K(73; words of the text of the `call` lines), the same for `callA` and for `callH`, TK(scale file's bytes as words), TK(request file's words), and K(72; table) for four public tables (R15.6 F:1272–1286). "The words of a text are its ASCII bytes, four to a word, the first byte lowest; the last word is filled up with zero bytes." (R15.4 F:1253–1254; `text_words` py:655–658.) Numbers in use: 10, 11, 72, 73 (F:230–231).

How it differs from H: it puts its own words in the counter's high half (F:1218–1219), which H never does (H's high half is 0 *[derived]*). Anchor: K(0; no word) "is the first 32 bytes of BLAKE2b-512 of the empty string" (vec:199). Known answers: vec:194–208.

### 3.6 Proof of work

Defined in R5.5 (F:476–479), see 4.6. There is no separate hash for it: the test reads the first word of block B_0 of the round's own call C_i(0).

---

## 4. Chains (Fiat–Shamir transcripts)

### 4.1 Shape of a chain

A chain has a label (an integer); "Everything that is fixed before the prover speaks enters the chain's first value"; "Then each message of the prover is hashed together with the chain's current value, and the hash gives the next value and the verifier's message" (F:253–262). Each of the seven chains of a key file, a leaf file and a proof file has a label of its own (R13.4, R14.3, R14.9, R14.10: outside this scope); these labels are below 2^32 and the one label from 2^32 on is that of R4.8 (F:255–257).

### 4.2 The parameters' bytes (R4.3, F:287–313)

In this order (`parameters_head` py:89–90, `plan_bytes` py:79–86):

1. The item `the format's version`: value = the version word (8 bytes).
2. The plan: eight words, then its entries. "The plan is not an item: no name and no length come before it." (F:292–293.)
3. The item `configuration` (value = configuration's digest, 32 bytes), then the other parameter items "in the order in which the protocol names them" (F:298–299).

The plan's eight words (F:293–297):

| # | word |
|---|---|
| 0 | the field (1 or 2) |
| 1 | the hash (1) |
| 2 | number of bytes of a leaf's salt |
| 3 | number of bytes of a nonce in a file |
| 4 | number of bytes of a listed position (0: none is listed) |
| 5 | number of answers to each out-of-domain sample |
| 6 | whether a sumcheck's message leaves out the coefficient that the check fixes; 1 in every plan of this format |
| 7 | number of entries |

An entry = a text (the round's name) and eleven words (F:301–307):

| # | word | script name (py:80–81) |
|---|---|---|
| 0 | how many rounds in a row are like this one; "is 1 in every plan of a chain" | count |
| 1 | the proof-of-work bits | work_bits |
| 2 | how many bytes of the prover's message enter the query | message_bytes |
| 3 | how many roots are among them | roots |
| 4 | how many answers to out-of-domain samples are among them | answers |
| 5 | how many elements of E are sampled | draw_E |
| 6 | how many of these must not be 0 | draw_nonzero |
| 7 | how many positions are sampled | draw_positions |
| 8 | k, where positions are sampled from [0, 2^k) | log_n |
| 9 | how many matrix entries are sampled | draw_trits |
| 10 | for a round that batches rows, how many rows | rows |

"The kind of a round (R5.2) is not among the words: it follows from the round's name, so the list of the names with their kinds is part of the format (R14.11)." (F:308–309.) A plan can hold one entry named `RECORD` that is not a round of its chain; it is encoded like any entry and "the chain's rounds pass over it" (R13.15 says where) (F:309–313).

Worked bytes (vec:15): `1400000000000000` ‖ `the format's version` (20 bytes) ‖ `0800000000000000` ‖ `4838323100000000` ‖ plan words 2, 1, 40, 8, 0, 1, 1, 6 ‖ `0e00000000000000` ‖ `toy: challenge` ‖ eleven words 1, 0, 48, 0, 0, 1, 0, 0, 0, 0, 0 ‖ … ‖ `0d00000000000000` ‖ `configuration` ‖ `2000000000000000` ‖ 32-byte digest ‖ the next item. The toy plan is py:813–815, the parameters py:818.

### 4.3 Items and the statement

- An item = name (text) ‖ word(length of the value's bytes) ‖ the value's bytes (R4.1 F:278–280; py:75–76). A text value is itself length-prefixed inside the value: item(`toy: name`, text(`abc`)) has value length 11 (vec:17).
- The value's bytes are the canonical bytes of its type; composite types "are the fields that change what a verifier does, in a fixed order" (sections 9, 10, 12) (R4.2 F:282–284). Two hashed facts are fixed by no numbered rule: "the values of some leaf classes, and the order in which codes enter `codes` (17.1, item 2)" (F:284–286).
- Stored tables: root and record of every stored table of which a chain speaks are among the statement's items, "by value, before its other items, one item for each table" (F:340–342). Name `table` in the chains of a key file and of a proof file (F:343–344), `the first table` for the anchor in a leaf file's link (F:996–997). Value = root as a string of bytes (word 32 and the 32 bytes), then the record as a list of its answers (count word, then elements of E), "by row and within a row by answer" (F:344–346). Known answer: vec:142 (value length 0x48 = 8 + 32 + 8 + 24).
- "A verifier never opens under a root that it has from elsewhere": the root under which openings of a stored table are checked is the one in this item (F:353–355). The record's seeds are in no item and no file; whoever needs them computes them (F:346–348).
- Seals: a chain that builds on earlier chains of the same session has one item `the seal of an earlier chain` for each, in a protocol-fixed order; value = the seal's 32 bytes after the item's own length word 32 (R4.7 F:358–361; F:957–962). A request's second chain has two: its own first chain's seal, then the shared chain's (F:360–361).

### 4.4 Random bytes and the run's value (R4.5, F:315–329)

| case | where the 32 random bytes come from | in the file |
|---|---|---|
| (a) | the prover samples them in private | "the first 32 bytes of the chain in its file" |
| (b) | 32 bytes that are in this chain's first query as an item | not in the file |
| (c) | there are none; "such a chain sends no root" | — |

Run's value = H(172, 0, label, none; the parameters' digest, the random bytes) in cases (a) and (b). "A verifier rejects a proof in which a chain's run's value is 32 zero bytes." (F:323–324.) In a batch the two chains of a request have case (a); the shared chain has case (b), its 32 bytes being the item `the binding tree's root` of its statement (F:327–329). Per-file assignment: table in 7.5.

### 4.5 Three derived objects

- **Record seeds** (R4.8 F:362–368; `record_seeds` py:216–219): a chain of its own with label 2^32, 32 zero bytes instead of the parameters' digest, the table's name as its statement, an empty record field, no random bytes. One round, empty message, kind 3, no proof of work. From that round's answer: as many seeds as a row has stored answers (the fifth of the name's six words), each = c coordinates (elements of E by R6.4) and then one element of E by R6.5. So rho_0 = H(160, 0, 2^32, none; 0^32, word(112), name, word(0), word(0)) *[derived]* and the one call is H(162, 2^32, 1, rho_0; word(3 + 2^16·j), word(0)) *[derived]*. Known answers: vec:36–37.
- **Stored table's name** (R4.10 F:385–391; `table_name` py:97–98): root (32) ‖ configuration's digest (32) ‖ six words: a (rows have length 2^a); number of entries of a row's message, pads among them; number of entries of a row's random tail; v (2^v rows); number of stored answers per row; number of bytes of a leaf's salt. 112 bytes. c = "the least integer with 2^c not below the number of entries of a message" (F:394–396). The name does not say whether the table is the anchor or a leaf table (F:396). Known answer: vec:139.
- **Commitment ID**: layout 3.3 (i).

### 4.6 A round (R5.1–R5.7)

- Call: C_i(j) = H(162, label, i, rho_(i−1); the prover's message, word(kind + 2^8·w + 2^16·j), word(nonce)), 64 bytes (R5.2 F:448–450). The prover's message = "all that the prover has sent in this round and that enters the chain, in the order sent, each item by section 2. Its length is a multiple of 8." (F:452–453.)
- Kinds (F:453–456; constants py:124): 1 elements of E (`ALGEBRAIC`); 2 the element that joins a hiding polynomial to a claim (`EPSILON`); 3 the seeds of out-of-domain samples (`SEED`); 4 positions (`POSITIONS`); 5 entries of a matrix over {−1, 0, 1} (`BITS`); 6 a seal (`SEAL`); 7 nothing (`EMPTY`).
- w = the round's proof-of-work bits, 0 to 64, from the plan ("the programs admit fewer: 17.2, item 5"); j below 2^48 (F:456–457).
- In a round with w = 0 the nonce is 0 and no file holds it; rounds of kind 7 and of kind 6 have w = 0 (R5.3 F:459–461).
- Answer = blocks B_0, B_1, .. of 32 bytes: B_(2j) is the first half of C_i(j), B_(2j+1) its second half (R5.4 F:466–467):

| | w = 0 | w > 0 |
|---|---|---|
| the test block | none | B_0 |
| rho_i, the chain's next value | B_0 | B_1 |
| the blocks of the verifier's message, in order | B_1, B_2, .. | B_2, B_3, .. |

- Proof-of-work test (R5.5 F:476–479): "The low w bits of the first word of the test block are 0; at w = 64 the whole word is 0. Nothing else of the test block is read. If the test fails, the verifier rejects the proof, and nothing is sampled from that answer." The first word = bytes 0–7 of C_i(0), little-endian (`passes` py:142–144). Known answer: vec:25–27 (least nonce 116 at w = 8; test block begins with the byte 00).
- State: only rho (32 bytes) and the round counter. *[derived from R5.4]* rho_i = C_i(0)[0:32] when w = 0 and C_i(0)[32:64] when w > 0; with w = 0 the verifier's message starts at byte 32 of C_i(0); with w > 0 it starts at byte 0 of C_i(1). (`query` py:146–153, `block` py:137–140.)
- Rounds numbered 1, 2, ..; every round makes its query; after the last round the prover sends nothing into the chain, openings can follow; "a round of kind 7 closes" a protocol whose last prover's message has no verifier's message after it; "every byte that the prover sends into the chain (R8.2) enters some query" (R5.1 F:441–447).
- A function that implements the section rejects (R5.7 F:487–489): a prover's message that is not whole words; a nonce other than 0 at w = 0; proof of work in a round of kind 7; w above 64; a kind outside 1 to 7; a chain's value that does not have 32 bytes; a label from 2^48 on. A seal with w > 0 is "not a plan of the format"; R5.7 does not test it; a verifier that takes plans as inputs "tests it and rejects" (R5.3 F:460–465).
- Nothing of a chain's hash values is in a file: no rho_i, no block (R5.6 F:480). What a file contributes: prover's messages, random bytes in case (a), nonces; and to a first value: a stored table's root and stored answers, the number in a proof file's head (item `stored copy`), and a slot's word, salt and path (F:480–486).

Known answers for a whole toy chain, field 2: vec:15–35 (parameters' bytes → digest → run's value → rho_0 → six rounds).

---

## 5. Sampling a verifier's message

### 5.1 The sequence of words (R6.1, F:499–502)

The verifier's message is sampled from "the four words of its first block, then those of its second, and so on". "Each sampled value takes the next words of the sequence. No word is used twice, and none is skipped." What is left after the round's last sampled value is dropped. Words are little-endian 64-bit (R1.5 F:109–111; `word` py:161–164).

Equivalent stream view *[derived; checked against vec:22–29]*: read C_i(0) ‖ C_i(1) ‖ C_i(2) ‖ … as 64-bit little-endian words, eight per call; skip the first 4 words when w = 0 and the first 8 when w > 0; the rest is the sequence. Word n of the sequence is word (n + off) mod 8 of call (n + off) div 8, with off = 4 or 8.

### 5.2 The order of a round's sampled values (R6.2, F:503–511; R6.10 F:550–551)

| kind | what is sampled, in order | words at most (R6.11) |
|---|---|---|
| 1 | the elements of E, one after the other; "either each of them must be non-zero (R6.5), or each may be 0 (R6.4)" | 36 or 18 each |
| 2 | "exactly one element, which may be 0" (R6.4) | 18 |
| 3 | the seeds, one after the other, each whole (R6.9) | s·(18·v + 36) |
| 4 | the positions first, at least one; then, "If the plan's entry has an element of E as well, it is sampled after them, by R6.4" | positions + 18 |
| 5 | the matrix entries (R6.7) | ceil(n / 32) |
| 6 | the seal (R6.8) | 4 |
| 7 | nothing | 0 |

"An entry that has other sampled values than those of its kind is not an entry of the format." (F:510–511.) The only sampled values that must not be 0 are the challenge of the round `PSC Y` and a seed's factor (F:505–507).

### 5.3 Elements

- Attempt at an element of F, field 2: "take the word; the attempt fails if it is not below p". "A word is never reduced modulo p." (R6.3 F:512–514; `element_of_word` py:196–200.) Known answers: vec:71–74.
- Element of F: at most six attempts on the next words; the result of the first attempt that does not fail, "and the words after that attempt stay in the sequence". "If all six fail, the element is 0, and the six words are used up." (R6.4 F:515–517; `base` py:166–171; `TRIES = 6` py:125.) Known answers: vec:82–86.
- Element of E: three elements of F sampled one after the other, as e_0, e_1, e_2 (R6.4 F:517–518; py:175).
- Element of E that is not 0: at most two elements of E by R6.4; the first that is not 0; "If both are 0, the element is 1" = (1, 0, 0) (R6.5 F:519–520; py:173–178; `TRIES_NONZERO = 2` py:125).

### 5.4 Positions (R6.6, F:521–529)

A position in [0, 2^k), k < 64, is "the low k bits of the next word" (one whole word per position; `position` py:180–181). Positions are sampled one after the other and can repeat; their number is the plan's. Two things are passed on: the **draws** (order sampled, repeats kept) and the **list** (the set, increasing). "An opening follows the list: a position that is sampled twice is opened once. Every row that stands for a read follows the draws". One round's draws can belong to several trees, each with its own list (R7.19). Known answer: vec:28 (five positions in [0, 2^10) after a round with w = 8).

### 5.5 Matrix entries over {−1, 0, 1} (R6.7, F:530–534)

"Each run of 32 entries takes one fresh word, and entry j of the run reads bits 2 j and 2 j + 1 of it, counted from the lowest. The entry is 0 if bit 2 j is 0; otherwise it is 1 if bit 2 j + 1 is 0, and −1 if it is 1. What is left of the last word is dropped." All n entries of a round are sampled together; the runs of 32 are counted from the round's first entry. (`trits` py:183–190.) Known answer: vec:33 (forty entries).

### 5.6 Seal and seeds

- Seal (R6.8 F:535–538): a chain that other chains build on ends with a round of kind 6; the seal is "the next four words of that round's sequence, which are the first block of its message"; nothing is sent or sampled on the chain afterwards; a seal is in no file. *[derived from R5.3 + R5.4]* Since a kind-6 round has w = 0, seal = C_i(0)[32:64] and rho_i = C_i(0)[0:32] for the seal round i. (`seal_digest` py:192–193; vec:34–35.) In the three files that round's prover's message is empty (F:958–959); the toy vector uses a non-empty one (py:851).
- Seed of an out-of-domain sample with a point of v coordinates: "v elements of E by R6.4 and then one element by R6.5, the factor". A round of kind 3 samples s seeds, each whole; s = the plan's sixth word; all have the same v; its entry has s·(v+1) elements, of which s must not be 0 (R6.9 F:539–543). Oracle messages of one prover's message share the seeds: "v is the largest number of coordinates that one of them needs, and each reads the first coordinates of a point. Answer number i of each message belongs to seed number i." (F:546–549.) *[derived]* v = (entry word 5) / (entry word 6) − 1. Known answer: vec:31.

### 5.7 Bound and edge cases

- At most K words per round: 18 for each element of E by R6.4, 36 for each by R6.5, 1 for each position, ceil(n/32) for n matrix entries, 4 for a seal; the verifier's message is a total function of its first ceil(K/4) blocks; "a program may compute a block only when a sampled value needs it" (R6.11 F:552–556; `words_at_most` py:212–213; vec:93 = 18; 36; 72; 23; 2; 4).
- "a failed attempt shifts the later ones along the sequence" (F:560–561): the word consumed by value n depends on earlier failures, so values must be sampled strictly in order.
- Six failed attempts give 0 (not a rejection); two zero elements give 1 (not a rejection) (R6.4, R6.5). "May be 0" is a rule on sampling alone; some zero values lead to no acceptance elsewhere (13.9, `coin-zero`) (F:507–509).
- A position consumes a whole word even when k is small; the unread bits are dropped (R6.1 F:501–502). *[inference from py:180–181]* k = 0 still consumes one word and yields 0.
- The last word of a run of matrix entries is consumed whole even if only a few entries read it (R6.7).
- If the proof-of-work test fails nothing is sampled (R5.5).

---

## 6. Trees and openings

### 6.1 Columns and leaves

- Column at position x, 0 ≤ x < 2^a: first the symbols at x of all main rows, "part by part in the order of the parts and row by row within a part"; after them the symbols at the short position of x of all mask rows, in the same order. "A symbol over E counts as its three coordinates in order." So a column is a list of W elements of F, W fixed by the tree's shape. The order is *not* part by part (first part's main, first part's mask, …) (R7.1 F:594–600).
- Short position of x among rows of length 2^b: x mod 2^b (R7.2 F:601; `short_position` py:260–261). A mask row's symbol is in 2^(a−b) columns (F:598).
- Leaf's bytes = the column (8 bytes per element) ‖ the fill ‖ the salt (R7.3 F:608–609).
- Salt: s bytes, the same for all leaves of a tree, "a multiple of 8, at least 40 and at most 64"; s is the third of the plan's eight words (one parameter line `salt` sets it for every tree, stored trees and the binding tree too); a plan that breaks the bounds is not a plan of the format (F:610–614). Each leaf has its own salt (prover's MUST, F:609–610).
- Fill (F:616–618): "it is empty if ((16 + 8 W) mod 128) + s <= 128. Otherwise it is the zero bytes that bring 16 + 8 W + (the fill's length) to the next multiple of 128." The 16 is the hash's label. "The fill is hashed and is in no file." (F:618–619.) Note the case (16 + 8W) mod 128 = 0: the fill is empty *[derived; vec:103: W = 14]*. Known answers for W = 3, 9, 10, 11, 14, 16, 25, 26 with s = 40: salt begins at byte 24, 72, 112, 112, 112, 128, 200, 240 of the leaf's bytes (vec:95–110).
- The label of a leaf holds W and s/8, so two shapes never give one string (F:619–621; vec:111).
- Leaf's digest = H(number, tree, 2^a + x, start; the leaf's bytes) with W and s/8 in the label (R7.4 F:622–623):

| tree | number | tree argument | start | cite |
|---|---|---|---|---|
| made in a run | 164 | the tree's number (R7.13) | the run's value of the chain that sends the tree's root, "even where a later chain reads the tree" | F:623–624 |
| stored tree (of a stored table) | 174 | 0, "whichever table it is" | the configuration's digest | F:626–628 |
| binding tree | 173 | 0 | the configuration's digest | F:788–790 |

- The tree of a stored table: one part, no mask rows; depth = the a of the table's shape; the column has one symbol of F for each row of the table, row 0 first, so W = 2^v; salt length = the shape's sixth word ("from the programs' source") (F:634–637). All stored tables under one configuration share labels and start; they differ by symbols, salts and roots, and a verifier tells them apart "by the roots, which are in its first query" (F:629–632).

### 6.2 Vertices and shape

- "All trees are binary and perfect." Depth a. Vertex (d, i), 0 ≤ i < 2^d, has children (d+1, 2i) and (d+1, 2i+1); root (0, 0); the leaf of position x is (a, x) and its value is the leaf's digest (R7.6 F:647–649). There are no trees of non-power-of-two size: a "leaf beside an inner vertex, a top layer that is cut off, or a vertex with four children would get a number of its own" (F:655–657).
- Inner vertex = H(166, 0, 0, the configuration's digest; left child's value, right child's value); 80 hashed bytes; "It holds nothing of the tree, of the vertex's place or of the run." Binding tree: 178 instead of 166 (R7.7 F:650–654). "All that binds a tree to its run, its number and its positions is in the leaves." (F:654–655.)
- A tree of depth 0 has one leaf and its root is that leaf's digest; a tree's depth is at most 48 (R7.16 F:716–717).

### 6.3 The opening and the walk

- A tree is opened at a list x_1 < x_2 < .. < x_m of at least one position. Opening's bytes, "without any length": for each x_j in order, the column and its salt (no fill); then the given digests, 32 bytes each, in the order of R7.9. Size m·(8W + s) + 32·g (R7.8 F:661–664).
- The walk (R7.9 F:665–673): level by level from depth a up to depth 1, left to right within a level. The level's vertices are those above an opened leaf, by increasing place. "If a vertex has an even place and the next of the level's vertices is its sibling, the two give their parent's value, nothing is given, and the walk goes on after the sibling. Otherwise the sibling's value is the next given digest, and the vertex and that digest give their parent's value. In both cases the child with the even place is the left one". The parents, in the order made, are the next level's vertices. After depth 1 one vertex is left, the root.
- So the given digests are ordered "by level, the deepest level first, and not path by path"; their number g follows from a and the list alone: "a verifier runs the walk once without values to count them before it reads" (F:675–677). Bound: for t positions with 2^e ≤ t < 2^(e+1), g ≤ t·(a − e − 1) + 2^(e+1) − t (F:677–678) *[checked]*. Example: depth 3, list 0, 5, 7 → given (3, 1), (3, 4), (3, 6), (2, 1) (F:678–679). More: vec:117–124. Reference: `walk` py:271–292.

### 6.4 What the verifier recomputes and compares (R7.10, F:680–687)

- Reads the columns by its own shape and rejects a symbol by R1.3.
- "places the fill itself and hashes every opened leaf itself".
- Start, tree's number and position in that hash "follow from its own plan and run, never from the file".
- Makes the walk, with left and right from the bits of the places, and rejects "unless the walk uses every given digest, lacks none and ends in the root that was sent or, for a stored tree, in the root that is in the chain's first query (R4.6)".
- "takes no index, count or direction from the file" (one exception: a request's slot in the binding tree, R7.18).
- Rejects a file that ends before the opening's last byte.
- Does not compare mask symbols at two opened positions with one short position; each position's mask symbols are read from its own column (R7.11 F:688–691).

### 6.5 One value at a vertex (R7.14, F:692–712)

A verifier rejects if a vertex gets two different values under one root, computed or given. The record of values is keyed by the root's 32 bytes within a session ("one record for every root that is read in a session, whichever tree, chain or file the root came with"); within a record a value is keyed by 2^depth + place; a leaf is a vertex and its value is its digest; "The root's own value is not entered"; only what an accepted opening shows is entered (F:692–701). "Where every root is read at one list there is nothing to compare, and a verifier need keep no record." (F:705–706.) "no bound depends on it" (F:710–711). Reference: `OneValue` py:329–337, `Session` py:340–349; vec:133–137 (two honest openings: 22 values entered, 14 vertices in the record). Within a leaf file alone each stored tree is opened at one list; in a session of all three files the anchor's tree is opened in the key file's shared chain and again in the link, and the leaf table's tree in the link and again in the proof file's shared chain (R7.19 F:819–824).

### 6.6 Smaller trees, shared trees, numbering

- A tree of depth b < k in a group read at a list over [0, 2^k) is opened "at the set of the short positions (R7.2) of the list, in increasing order, each once" (R7.15 F:713–715; F:947–948).
- Which oracle messages share a tree (R7.12 F:721–729; `lay_trees` py:295–312): each oracle message has a leaf class (a number in its notice, R12.3). Two passes over the oracle messages of one prover's message, each in the order of sending. Pass 1, those with main rows: join the first tree of this prover's message with the same leaf class and main rows of the same length, else start a new tree. Pass 2, those without main rows: join the first tree with the same leaf class, else start a new tree of mask rows alone. Within a tree the parts are in the order of sending, whichever pass they joined in. Known answers: vec:126–128.
- A chain's list of trees (R7.13 F:737–754; `number_trees` py:315–326): place = index from 0. The list grows by (a) continuing at most one earlier chain of the session (begin with its whole list); (b) each tree the chain sends takes the next place, the trees of one prover's message in the order in which R7.12 starts them; (c) a tree adopted from another chain takes the next place at the moment of adoption. A tree's number (in its leaves' labels) = the place it got in the list of the chain that *sent* it; an adopted tree keeps its own number and its own start (the sender's run's value). At most 2^16 places. Known answers: vec:129–131.
- Layout rules on protocols (R7.5 F:638–643; R7.17 F:755–784) are conditions on public shapes: "a breach is an error of a program and never of a proof"; prover and verifier "stop, without a verdict" (F:769–776).

### 6.7 A batch's binding tree (R7.18, F:788–801)

Tree's number 0; leaves under 173, vertices under 178; start = configuration's digest for both. A request's slot = the place of its leaf. Leaf content = the seal of the request's first chain, 32 bytes counted as four words (W = 4), then the salt; the fill is empty. An untaken slot's leaf digest is 32 uniform bytes (prover's rule only). A file shows one leaf by its slot, its salt and its path (R14.7, R13.6); "A verifier computes the root from them and compares it with nothing: the root becomes an item of the shared chain's first query and is used instead of that chain's random bytes (R4.5, case (b))." Reference: `binding_leaf` py:236–238, `binding_root` py:250–257 (siblings from the leaf upward; an odd place makes the running node the right child); vec:112, vec:187–190.

### 6.8 A round whose draws are divided among several trees (R7.19, F:805–817)

The first n_1 draws go to one tree, the next n_2 to the next, …; each n_i ≥ 1; the numbers are in a parameter item of the step; the plan's entry has their sum as its number of positions "and one logarithm of the range for all". In the round `LINK` of a leaf file the item is `the link` with words nu_0 and nu_j: the first nu_0 draws are the anchor's, the last nu_j the leaf table's. Each tree's list is made from that tree's draws alone (sorted, each once); a position among the draws of two trees is in both lists and both trees are opened there. Where the plan lists positions, the round has one list: the set of all its draws, sorted, each once, right after the nonce and before all openings.

### 6.9 "Easy to get wrong" (F:826–844)

1. Given digests come after all columns and salts, level by level from the leaves up, left to right; their number is in no file.
2. A column has the main symbols of all parts first, then the mask symbols of all parts; parts in order of sending; the fill is hashed, never written, and counts the 16 label bytes.
3. Openings of a chain's own trees are ordered by place in the reading chain's list; stored trees have no place and are opened before them, in the order of the statement's items that hold their roots; a leaf's label has the tree's number (place in the sender's list) and starts from the sender's run's value.
4. An opening follows the list; whatever is done once per sampled position follows the draws.
5. The binding tree's root is computed and never compared.

---

## 7. A chain in a file; the three files

### 7.1 Ground rules (F:855–865)

All integers lowest byte first; element of F 8 bytes, of E 24 bytes, rejected if a coordinate is not below p; a digest (so a root) is 32 bytes with no length and any 32 bytes are a digest. "No file has a length, a count or an offset." The verifier first derives the plan of every chain from the public files (section 8), then "takes the planned items off the file one after the other". An opening's length depends on the sampled positions, so a file's length cannot be tested before the chains are run. "All chains of a file are read from one stream of bytes: after the first rejection nothing more is read, and the verdict is a rejection (from the programs' source)."

### 7.2 The items of a chain (R8.1–R8.2, F:869–892)

A chain's bytes are its items "in the order of the protocol, without lengths, names or separators"; every length follows from the plan, the shapes and the sampled positions; a verifier rejects a file that ends before the last item, and a file with a byte after it (R8.1 F:869–872).

| item | bytes | enters a query |
|---|---|---|
| the random bytes, case (a) of R4.5, as the chain's first item | 32 | through the run's value |
| an answer to an out-of-domain sample | 24 | yes, as part of the prover's message |
| an element of F; of E; a word | 8; 24; 8 | yes |
| a root | 32 | yes |
| the nonce of a round with w > 0, after the round's message | the plan's number of bytes of a nonce, "1 to 8 even where no round has proof of work"; low bytes of the nonce, lowest first, other bytes 0 | as the last word of its own round's calls, and of no other |
| after a round that samples positions, if the plan's number of bytes of a listed position is not 0: the list, increasing, each position once | that many bytes per position, lowest first | no; the verifier compares it with the list it has derived and rejects if it differs |
| an opening (R7.8) | m·(8W + s) + 32·g | no; it is checked against its root |

(F:875–883.) The three widths (salt, nonce, listed position) are the third, fourth and fifth plan words; parameter lines `salt` and `listed` set the first and third; "a nonce has 8 bytes in the three files of this section"; `record.f2.txt` has a salt of 40 bytes, no listed positions, and proof of work only in rounds that sample positions (F:885–889). A round with w = 0 has no nonce in the file (F:890–891). Nothing else of a chain is in a file: no value, no block, no seal (F:891–892).

### 7.3 Order within a prover's message

- After a round of kind 3 the prover's next message begins with all answers to out-of-domain samples the seeds ask for, oracle message by oracle message in the order sent, each as answer 1, 2, ..; an oracle message whose notice has q answers sends one answer for each of the first q seeds; with plans derived by 8.4 every q is 0 or s; the number of these answers is the fifth of the next round's eleven entry words (R8.3 F:900–916).
- In a round of kind 2 the sum of the hiding polynomial is the last item of the prover's message (R8.4 F:917–918).
- A root is in the message of a round of kind 1 to 5 (R8.5 F:919–920).
- The roots of one prover's message are in the order of their trees' numbers, one for each tree that R7.12 makes (R8.6 F:921–922).
- How a message is cut into items is part of the format (which 8 bytes are an element, and so can be rejected). In the three files no prover's message has a plain word: "all its bytes outside a root belong to elements, and each element is tested for its canonical form". The plan's entry gives lengths alone; the list of items round by round belongs to each protocol (sections 9–11) (R8.8 F:923–929).

### 7.4 After a round that samples positions (R8.7 F:933–942; R8.10 F:943–944)

In this order: the round's nonce, if it has proof of work; the listed positions, if the plan lists them; the openings of stored trees that the round reads, "in the order of the statement's items that hold their roots"; the openings of the chain's own trees read at this list, "by increasing place in the reading chain's list of trees", not by the numbers in their leaves' labels; then the items of the next prover's message. With divided draws, "this list" is for each tree the list of its own draws and the listed positions are one list for the whole round. A plan with listed-position width n > 0 and k > 8n is not a plan of the format. The number of listed positions is the length of the list, not the number of draws, so the verifier derives the list first (F:946–947). Which trees a round opens: R13.12 (F:948–949).

### 7.5 Several chains; the seven chains

Chains follow one another in a file with other items between them; the trailing-byte rejection "is made once, at the end of the file" (R8.9 F:953–955). A verifier that has rejected anything in a chain rejects every chain that has that chain's seal; a file is accepted only if no chain has rejected, every chain has run all the rounds of its plan, and no byte is left (F:964–967).

| file | chain | random bytes in the file | ends in a seal | its list of trees begins |
|---|---|---|---|---|
| key file | one-time chain | yes | yes | empty |
| key file | shared chain | no | yes | empty |
| key file | second chain | yes | no | with the one-time chain's list |
| leaf file | link's chain | yes | no | empty |
| proof file | first chain | yes | yes | empty |
| proof file | shared chain | no | yes | empty |
| proof file | second chain | yes | no | with the first chain's list |

(F:1072–1080.) A second chain continues the one-time / first chain and adopts one tree of the shared chain (F:1005; F:1068–1070).

### 7.6 Key file (`key.bin`), R13.1–R13.2 (F:974–1005)

| part | bytes |
|---|---|
| the head: `CPIK` then `H821` | 8 |
| the anchor's root | 32 |
| the stored answers of its record, by row and within a row by answer | 24 each; "Their number is in no file" = 2^v × (answers per row, fifth word of R4.10) (F:1000–1001) |
| the one-time chain: its 32 random bytes, then its rounds | by its plan |
| the slot: the word 0, then the salt of a leaf of the binding tree | 8 + salt bytes |
| the shared chain: its rounds, without random bytes | by its plan |
| the second chain: its 32 random bytes, then its rounds | by its plan |

"A verifier rejects a file of another kind or version before it reads on." (F:976.) No part has its own length; a verifier rejects a file in which a byte is left over (F:978–980). Root and stored answers are items of the file, not messages of a chain; the verifier reads them first and puts them into the statement of every chain that speaks of the table (item `table`): the one-time chain (which opens no column) and the shared chain; the second chain has them only through the two seals (F:992–996). The slot is that of a batch of one, a binding tree of depth 0, "so a verifier rejects a word other than 0" (F:1003–1004).

### 7.7 Leaf file (`leaf/<k>.bin`), R13.3 (F:1012–1020)

Head (`CPEN` then `H821`, 8 bytes); the leaf table's root, 32 bytes; the stored answers of the leaf table's record, as in R13.2; the link's chain: its 32 random bytes, then its rounds. "The file ends with the chain." The link's chain has no seal. Its statement has both tables' items; the anchor's root and stored answers are those the verifier kept from the key file, under the name `the first table` (F:996–997; F:1016–1017). The round `LINK` samples the positions of both tables at once; after the nonce (and the listed positions, if any) come the anchor's opening at the list of the first nu_0 draws, then the leaf table's opening at the list of the last nu_j draws (F:1018–1020).

### 7.8 Proof file, R14.1–R14.2 (F:1026–1070)

| # | part | bytes |
|---|---|---|
| 1 | the head: `CPPF`, `H821`, a number in four bytes lowest first | 12 |
| 2 | the request's first chain: 32 random bytes, then its rounds | by its plan |
| 3 | the request's slot in its batch: one word (the slot); the salt of that slot's leaf; as many digests as the binding tree's depth, "the sibling of the leaf first" | 8 + salt bytes + 32·depth |
| 4 | the batch's shared chain: its rounds, without random bytes | by its plan |
| 5 | the request's second chain: 32 random bytes, then its rounds | by its plan |

- The head's number is "the number under which the leaf table is kept on which the proof was made"; the same number is the item `stored copy` of the first chain's statement; "A verifier rejects a number other than the one under which it holds the table that it reads." (F:1036–1041.) The programs take k from the head, open `leaf/<k>.bin` (k in decimal), reject if there is no such file, check the proof against the root in that leaf file "and never against the root in the key file", and in the same call check that leaf file's link and the key file (F:1043–1050). Known answer: vec:182 = `435050464838323101000000`.
- The slot's word is rejected unless it is below 2^depth; the salt's length is the second word of the item `binding tree` (R14.6); depth = least d with 2^d not below the parameter line `slots` (6 for 64, so a slot has 8 + 40 + 6·32 = 240 bytes under `record.f2.txt`) (F:1055–1060). "The slot's word is the only position that a verifier takes from a file." (F:1060.)
- The slot stands between the first chain and the shared chain because the first chain's seal, the salt and the path give `the binding tree's root`, which the shared chain's first query needs and which replaces that chain's random bytes (F:1062–1066).
- The shared chain's bytes are the same in the files of all requests of a batch (F:1034).

### 7.9 What a verifier does with each kind of bytes (F:1084–1094)

| bytes | what a verifier does |
|---|---|
| the head's bytes | compares them with its own values |
| elements of F or E: scalars, answers to out-of-domain samples, stored answers, columns | rejects unless every coordinate is below p |
| digests: roots, given digests, a slot's path | reads any value |
| a nonce | tests the round's proof of work with it, before anything is sampled from the round's answer |
| listed positions | compares them with the list that it derives |
| salts and a chain's random bytes | reads any value; rejects a chain whose run's value is 32 zero bytes |
| the word of a slot | rejects unless it is below 2^depth |

"At every item a verifier rejects a file that ends too early." (F:1094.)

### 7.10 "Easy to get wrong" (F:1096–1104)

1. The shared chain has no random bytes in the file; the other chains begin with 32.
2. In a key file and in a leaf file the root and the record's stored answers come before the chain's random bytes.
3. After a round that samples positions: nonce, listed positions, stored trees' openings, the chain's own trees by place, next message.
4. The test that no byte is left is made once, after the last chain of the file.
5. A seal is in no file, and neither is the binding tree's root.

---

## 8. Rule index (every rule ID defined in FORMAT.md lines 1–1105: 86 rules)

Order is the order of the text; note R7.14–R7.16 stand before R7.12–R7.13, R8.8 before R8.7, R8.10 before R8.9. Rule numbers do not follow sections (table F:23–34).

| ID | one-line statement | line |
|---|---|---|
| R1.1 | byte = 8 bits; word in [0, 2^64) = 8 bytes lowest first; nothing is big-endian | F:96 |
| R1.2 | F = Z/p; field 1 p = 2^61 − 1, field 2 p = 2^64 − 2^32 + 1; field 2 is the reference | F:98 |
| R1.3 | element of F = word of its least residue; reject a word not below p; not the sampling map of R6.3 | F:101 |
| R1.4 | E = F[X]/(X^3 − c), c = 5 / 2; encoded e_0, e_1, e_2 (24 bytes); reject if a coordinate is rejected | F:105 |
| R1.5 | digest = any 32 bytes, no length; word i = bytes 8i..8i+7; two rules add a length | F:109 |
| R1.6 | text / string of bytes = length word then bytes; names are ASCII | F:114 |
| R1.7 | list = count word then values; byte string is not a list; pair = first then second | F:116 |
| R1.8 | integer, truth value, enumeration member = one word | F:119 |
| R1.9 | same encodings for hashes and files; the read-back rejections | F:120 |
| R2.1 | H(number, tree, index, start; bytes) = BLAKE2b of label ‖ bytes; W, s8 only under 164, 173, 174 | F:139 |
| R2.2 | parameter block: digest length 32 (64 under 162), no key, fanout 1, depth 1, salt = start[0:16], personalization = start[16:32] | F:152 |
| R2.3 | bounds on number, tree, index, W, s8, bytes, start | F:161 |
| R2.4 | the oracle's strings: half ‖ P ‖ label ‖ bytes, and their image | F:167 |
| R2.5 | reserved: first byte not 0/1; the number 177 | F:183 |
| R2.6 | ceil(n/128) compressions; costs of a vertex and of a round's calls | F:186 |
| R2.7 | reject inputs that make a hashed string too long; 2^63 rounds; 2^a + position reaching 2^63 | F:191 |
| R3.1 | the thirteen numbers and their arguments | F:205 |
| R3.2 | no number gets a second meaning; unused numbers; the second hash has 10, 11, 72, 73 | F:230 |
| R3.3 | where the public parameters are bound into hashes | F:232 |
| R3.4 | a leaf's string is never a vertex's | F:243 |
| R3.5 | a verifier makes no hash but H; one exception, R15.3 | F:244 |
| R3.6 | not in use | F:249 |
| R4.1 | parameters and statement are lists of items; item = name, value length, value bytes | F:277 |
| R4.2 | a value's bytes are the canonical bytes of its type | F:282 |
| R4.3 | parameters' bytes: version item, plan (8 words + entries of text and 11 words), `configuration`, other items; `RECORD` entry | F:287 |
| R4.4 | parameters' digest = H(169, 0, 1, none; parameters' bytes) | F:314 |
| R4.5 | 32 random bytes, cases (a)/(b)/(c); run's value = H(172, 0, label, none; …); reject an all-zero run's value | F:315 |
| R4.6 | first value rho_0 = H(160, 0, label, none; …); record field always empty; a stored table's item | F:330 |
| R4.7 | one item `the seal of an earlier chain` per earlier chain, in a fixed order | F:358 |
| R4.8 | the seeds of a stored table's record: own chain, label 2^32, zero parameters' digest, name as statement, one kind-3 round | F:362 |
| R4.9 | configuration's digest = H(169, 0, 2, none; file count, files with lengths); item `configuration` | F:372 |
| R4.10 | stored table's name = root ‖ configuration's digest ‖ six words (112 bytes); c | F:385 |
| R4.11 | commitment ID = H(179, 0, 0, none; …; word 0) | F:400 |
| R4.12 | committer's rule: the same randomness is never used under two roots (MUST; no verifier sees it) | F:421 |
| R5.1 | rounds numbered from 1; each prover's message is followed by a verifier's message; kind 7 closes | F:441 |
| R5.2 | call j of round i; the kinds 1–7; w 0..64; j < 2^48 | F:448 |
| R5.3 | w = 0: nonce 0, in no file; kinds 6 and 7 have w = 0 | F:459 |
| R5.4 | the answer's blocks: test block, rho_i, message blocks, by w | F:466 |
| R5.5 | proof-of-work test on the low w bits of the test block's first word | F:476 |
| R5.6 | no hash value is in a file; which file bytes enter which hash | F:480 |
| R5.7 | rejections of a function that implements section 4.2 | F:487 |
| R6.1 | the sequence of words; none used twice, none skipped; the rest dropped | F:499 |
| R6.2 | the order of a round's sampled values, by kind | F:503 |
| R6.3 | an attempt at an element of F; never reduced modulo p | F:512 |
| R6.4 | element of F: at most six attempts, else 0; element of E: three elements of F | F:515 |
| R6.5 | non-zero element of E: at most two tries, else 1 | F:519 |
| R6.6 | position = low k bits of the next word; draws and list | F:521 |
| R6.7 | n matrix entries over {−1, 0, 1}: two bits each, 32 per word | F:530 |
| R6.8 | a seal = the next four words of a kind-6 round; in no file | F:535 |
| R6.9 | a seed = v elements of E and a non-zero factor; s seeds per kind-3 round | F:539 |
| R6.10 | kind 4: positions first, then the element if the entry has one | F:550 |
| R6.11 | at most K words; a total function of ceil(K/4) blocks | F:552 |
| R7.1 | the column: main symbols of all parts, then mask symbols of all parts | F:594 |
| R7.2 | short position = x mod 2^b | F:601 |
| R7.3 | leaf's bytes = column ‖ fill ‖ salt; salt 40..64 bytes, multiple of 8; the fill rule | F:608 |
| R7.4 | leaf's digest; 164 + run's value for a run's tree; 174 + configuration's digest + tree 0 for a stored tree | F:622 |
| R7.5 | which tree holds a mask row's copies (condition on protocols) | F:638 |
| R7.6 | trees are binary and perfect; vertex (d, i); root (0, 0) | F:647 |
| R7.7 | inner vertex = H(166, 0, 0, configuration's digest; left, right); 178 in a binding tree | F:650 |
| R7.8 | an opening's bytes: columns and salts in list order, then the given digests | F:661 |
| R7.9 | the walk; order and number of the given digests | F:665 |
| R7.10 | what the verifier does with an opening, and what it never takes from the file | F:680 |
| R7.11 | mask symbols at one short position are not compared | F:688 |
| R7.14 | one value at a vertex; the record of values per root; the session | F:692 |
| R7.15 | a shorter tree is opened at the short positions of the list | F:713 |
| R7.16 | a tree of depth 0; depth at most 48 | F:716 |
| R7.12 | which oracle messages share a tree: two passes by leaf class and length | F:721 |
| R7.13 | a chain's list of trees; continue, send, adopt; a tree's number; at most 2^16 places | F:737 |
| R7.17 | four layout rules (a)–(d) that keep R7.5's first clause | F:755 |
| R7.18 | a batch's binding tree: 173 / 178, tree 0, content = a seal (W = 4); root computed, never compared | F:788 |
| R7.19 | a round whose draws are divided among several trees | F:805 |
| R8.1 | a chain's bytes in a file: items without lengths, names or separators; reject a short file or a trailing byte | F:869 |
| R8.2 | the kinds of items and whether they enter a query | F:873 |
| R8.3 | after a kind-3 round the next message begins with the answers to the out-of-domain samples | F:900 |
| R8.4 | kind 2: the hiding polynomial's sum is the message's last item | F:917 |
| R8.5 | a root is in the message of a round of kind 1 to 5 | F:919 |
| R8.6 | the roots of one message are in the order of their trees' numbers | F:921 |
| R8.8 | how a message is cut into items is part of the format | F:923 |
| R8.7 | order after a round that samples positions: nonce, listed positions, stored trees, own trees by place | F:933 |
| R8.10 | listed-position width n > 0 with k > 8n is not a plan | F:943 |
| R8.9 | several chains in a file; the trailing-byte test is made once | F:953 |
| R13.1 | head of a key file (`CPIK`) and of a leaf file (`CPEN`): kind and `H821`, 8 bytes | F:974 |
| R13.2 | a key file, in order | F:978 |
| R13.3 | a leaf file, in order | F:1012 |
| R14.1 | a proof file, in order | F:1026 |
| R14.2 | a proof file's head: `CPPF`, `H821`, a 4-byte number = the leaf table's number | F:1035 |

Rules that sections 1–7 cite but do not define: R0.1, R0.2 (13.1); R12.3, R12.6, R12.10, R12.11, R12.15; R13.4–R13.15, R13.19; R14.3, R14.4, R14.6–R14.11; R15.1, R15.3, R15.6 (see section 12).

---

## 9. Reference-implementation map

### 9.1 `format_rules.py`

What it is (py:7–23; README:33): "The rules R1.x to R8.x and R12.x to R15.x of FORMAT.md as a program"; standard library only (`hashlib`, `struct`, py:25–26); every hash is one `hashlib.blake2b` call except K, which needs the compression function written out. "Chains and sampling serve both fields; proof_head, point and symbol serve field 2 alone." It has no sizes and plans (section 8), no sub-proof (section 11), no content tests (section 13). "The functions for R15.x were written from the programs' source and not from the rules."

| function / constant | lines | rule(s) | note |
|---|---|---|---|
| `MASK`, `PRIME` | py:28–29 | R1.2 | both fields' primes |
| `START`, `NUMBERS`, `LEAVES` | py:32–36 | R3.1 | which numbers take a start; the 13 numbers; the leaf numbers |
| `H` | py:39–45 | R2.1–R2.3 | asserts the bounds of R2.3 |
| `label` | py:48–49 | R2.1 | the 16 bytes |
| `oracle_string` | py:52–54 | R2.4 | half ‖ P ‖ label ‖ data |
| `u64`, `string`, `text`, `ext` | py:58–71 | R1.1, R1.6, R1.4 | encoders only; no decoder / canonical check exists in the script |
| `item` | py:75–76 | R4.1 | |
| `plan_bytes` | py:79–86 | R4.3 | entry tuple of 12: name + 11 words |
| `parameters_head` | py:89–90 | R4.3 | version item ‖ plan |
| `configuration_digest` | py:93–94 | R4.9 | |
| `table_name` | py:97–98 | R4.10 | |
| `published_id` | py:101–106 | R4.11 | the commitment ID |
| `parameters_digest` | py:109–110 | R4.4 | |
| `run_value` | py:113–114 | R4.5 | argument `parameters` is the parameters' *digest* (use: py:826) |
| `first_value` | py:117–120 | R4.6 | same naming trap (use: py:828, py:217) |
| kind constants, `TRIES`, `TRIES_NONZERO` | py:124–125 | R5.2, R6.4, R6.5 | 1..7; 6; 2 |
| `Chain.__init__` | py:129–131 | — | state: rho, round, field, label |
| `Chain.call` | py:133–135 | R5.2 | asserts three of R5.7's tests |
| `Chain.block` | py:137–140 | R5.4 | block b = half b mod 2 of call b div 2 |
| `Chain.passes` | py:142–144 | R5.5 | |
| `Chain.query` | py:146–153 | R5.4, R5.5 | returns False and leaves the chain unchanged if the test fails |
| `Chain.least_nonce` | py:155–159 | — | prover's search |
| `Chain.word` | py:161–164 | R6.1 | |
| `Chain.base`, `Chain.element` | py:166–178 | R6.4, R6.5 | |
| `Chain.position` | py:180–181 | R6.6 | |
| `Chain.trits` | py:183–190 | R6.7 | |
| `Chain.seal_digest` | py:192–193 | R6.8 | |
| `element_of_word` | py:196–200 | R6.3 | |
| `base_from_words` | py:203–209 | R6.4 | on a given word list, for the vectors |
| `words_at_most` | py:212–213 | R6.11 | |
| `record_seeds` | py:216–219 | R4.8, R6.9 | |
| `leaf_bytes` | py:223–228 | R7.3 | asserts the salt bounds |
| `leaf` | py:231–233 | R7.4 | numbers 164 and 174 only |
| `binding_leaf`, `binding_vertex`, `binding_root` | py:236–257 | R7.18, R14.7 | |
| `vertex` | py:241–242 | R7.7 | |
| `short_position` | py:260–261 | R7.2 | |
| `build` | py:264–268 | R7.6, R7.7 | whole tree; a prover's / test helper |
| `walk` | py:271–292 | R7.9 (R7.14 hook) | returns the root; the caller compares |
| `lay_trees` | py:295–312 | R7.12 | |
| `number_trees` | py:315–326 | R7.13 | |
| `OneValue`, `Session` | py:329–349 | R7.14 | no rollback of a rejected opening |
| `NO_CODE` … `choices_bytes`, `stages_bytes` | py:353–373 | R12.x | type encoders (outside this scope) |
| `chain_of_links_bytes` | py:376–383 | R12.12–R12.14 | |
| `shape_bytes`, `table_shape_bytes` | py:386–392 | R12.3, R4.10 | |
| `link_bytes` | py:395–397 | R13.9 | |
| `test_on_the_table_bytes` | py:400–407 | R13.13 | |
| `ranges_bytes` | py:414–423 | R13.14 | |
| `psc_rounds`, `product_tree_rounds`, `lookup_rounds`, `test_rounds`, `key_rounds` | py:426–479 | R13.16–R13.19 | round lists of a key file |
| `layout_bytes` | py:482–491 | R14.5 | |
| `proof_head` | py:494–496 | R14.2 | `CPPF` ‖ `H821` ‖ 4-byte number |
| `proof_statement` | py:499–503 | R14.3 | items `table`, `stored copy`, `request`, `the request file's words` |
| `first_chain_tail` | py:506–509 | R14.4 | |
| `rotr64`, `blake2b_IV`, `blake2b_sigma` | py:547–571 | RFC 7693 | sigma has 12 rows (rows 10, 11 repeat 0, 1) |
| `blake2b_init_param` | py:574–579 | R15.3 | IV xor P, P = [outlen, keylen, 1, 1] ‖ 60 zero bytes |
| `G`, `ROUND`, `blake2b_F` | py:582–622 | RFC 7693 3.2 | t has 128 bits; `last` inverts v[14] |
| `older_K`, `older_TK` | py:625–647 | R15.3 | K and TK |
| `words32`, `text_words`, `CALLH_IF_NONE` | py:650–661 | R15.4, R15.6 | |
| `statement_words` | py:664–690 | R15.5–R15.7 | the item `request`, 177 words |
| `rounds_text`, `_log_up`, `_block` | py:693–702 | — | helpers |
| `link_groups`, `links_rounds` | py:705–746 | R12.16, R12.17 | |
| `ROOT_32`, `point`, `symbol` | py:749–764 | R12.11 | field 2; the only modular multiplications in the script |
| `pattern` | py:768–769 | — | byte i = (a·i + b) mod 251, default a = 7, b = 3 |
| `toy_run` | py:772–793 | R13.x | values of a toy key/leaf run "typed by hand" |
| `main` | py:796–1019 | — | prints the known answers |

Differences between the script and the rules that matter when it is used as an oracle:

- `Chain.call` checks only "whole words", "nonce 0 at w = 0" and "no proof of work in kind 7" (py:134); R5.7's other rejections (w above 64, kind outside 1..7) are not asserted there.
- `walk` neither compares with a root nor undoes entries of a rejected opening (py:271–292; R7.14 F:699–700).
- There is no reader in this file: no canonical test of R1.3 on parsed bytes, no file parsing (the `read_*.py` scripts do that; not read).

### 9.2 `format-vectors.txt`

Form: 227 lines; 26 begin with `#` (2 header lines, 24 group headings); 201 are known answers `label = value` *[checked by count]*. Split a line at its **last** ` = `: labels contain ` = ` themselves (vec:4, vec:210, vec:211). Labels are not unique (the same label recurs under different headings and for both fields, e.g. `rho_0` at vec:19 and vec:41; the indented `  its leaf under 164: …` eight times), so key a vector by line number or by (heading, label). Values: lower-case hex for bytes; decimal integers; `-` for "rejected" / "the attempt fails"; `yes` / `no`; several values joined by `; `. `pattern(n)`: byte i is (7i + 3) mod 251; "pattern(n) with a i + b": byte i is (a·i + b) mod 251 (vec:1). The labels use other words than FORMAT.md: drawn = sampled; behind = after; bits of work = proof-of-work bits; links = segments; look-up = lookup; the published ID = the commitment ID; the stored copy / the copy = the leaf table; "sections 5 and 6 of the rules" = sections 4 and 5 of FORMAT.md (vec:2).

| group heading | lines | answers | content | reusable for |
|---|---|---|---|---|
| `# R2.x and R3.x` | vec:4–13 | 10 | two oracle strings; H(168) on no byte, pattern(128), pattern(129) with index 2^33 + 5; a leaf-labelled H(164) (W = 3, s8 = 5); a vertex (166); a binding vertex (178); two 64-byte H(162) (one with tree 2^32, kind 4, w 8, j 1, nonce 5) | BLAKE2b / H: label packing, salt + personalization, 32 and 64 bytes, one and two blocks |
| `# R4.x: a toy plan of six rounds, field 2` | vec:15–20 | 6 | parameters' bytes; parameters' digest; statement's bytes; run's value (label 7); rho_0; rho_0 without random bytes | encoders, R4.3–R4.6; a long multi-block hash |
| `# sections 5 and 6 of the rules: R5.x and R6.x` (field 2) | vec:22–37 | 16 | six rounds of kinds 1, 7, 4, 3, 5, 6: each rho_i; an element; least nonce 116, test block, five positions and an element; a seed; forty entries; the seal; a record seed's point and factor | round calls, proof of work, all sampling kinds, R4.8 |
| the same two groups, field 1 | vec:39–42, vec:44–59 | 4 + 16 | as above for field 1 (no bytes printed) | not needed for `H821` |
| `# R1.x: eight bytes as the encoding of an element of F` | vec:61–69 | 9 | 4 field-2 cases (0, p − 1, p, 2^64 − 1), 5 field-1 cases | canonical test |
| `# R6.x: a word and its attempt` | vec:71–80 | 10 | 4 field-2, 6 field-1 | R6.3 |
| `# R6.x: an element of F from a given sequence of words` | vec:82–91 | 10 | 0, 1, 5, 6, 7 failing words then the word 5, per field: element; words used | R6.4 retry limit |
| `# R6.x: the most words of a verifier's message` | vec:93 | 1 | 18; 36; 72; 23; 2; 4 | R6.11 |
| `# R7.x: a leaf's bytes` | vec:95–113 | 19 | eight column sizes: length and salt offset, and the leaf digest under 164 (tree 5, a = 3, position 6); two shapes with one string differ; a binding leaf; a leaf under 174 | fill rule, leaf hashing |
| `# R7.x: a tree with two main rows … and one mask row` | vec:115–124 | 10 | configuration's digest of `toy\n`; the root; for four draw sets the given digests as (depth, place), the opening's length and its H(168) digest | vertices, walk order, opening layout |
| `# R7.x: which oracle messages share a tree` | vec:126–131 | 6 | three `lay_trees` cases; three `number_trees` cases | R7.12, R7.13 |
| `# R7.x: one value at a vertex` | vec:133–137 | 5 | counts and three admit / refuse cases | R7.14 |
| `# R4.x: a stored table's name` | vec:139–142 | 4 | a name (112 bytes); two commitment IDs; the item `table` | R4.10, R4.11, R4.6 |
| `# R8.x: a whole chain in a file, field 2` | vec:144–148 | 5 | parameters' digest; root; nonce 51, draws 1 5 6 5, given digests; file length 440; the file's bytes | end-to-end: random bytes ‖ root ‖ answer ‖ element ‖ nonce ‖ opening |
| the same, field 1 | vec:150–154 | 5 | | not needed |
| `# R12.x: synthetic values of the first types` | vec:156–160 | 5 | codes, notices, stages, choices | later sections |
| `# R12.x: a chain of segments` | vec:162–164 | 3 | | later sections |
| `# R13.x: three items …` | vec:166–168 | 3 | `the link`, `the test on the table`, `ranges` | later sections |
| `# R13.x: the rounds of that run's key file` | vec:170–172, vec:174–180 | 3 + 7 | round counts and SHA-256 of the round lists (711 / 34 / 13 rounds), and seven variants | later sections (needs SHA-256 to compare) |
| `# R14.x: a proof file` | vec:182–192 | 11 | proof head; first chain's statement; two layouts; item `binding tree`; four binding roots (depth 2, places 0–3); two round-list hashes | head, R14.3 items, binding path |
| `# R15.x: the second hash function` | vec:194–208 | 15 | K(73; words(0)), K(73; words(1)), K(10; words(32)), K(10; words(33)), K(11; words(128)), K(0; no word), TK of 8, 128, 129, 1024, 1025, 16385 words, the words of a text, two K(73; text) | K / TK; words(n): word i = (2654435761·(i + 1)) mod 2^32, digest printed as its eight words' bytes, lowest first (vec:193) |
| `# R12.x: a code's points and symbols, field 2` | vec:210–227 | 18 | w = 7^(5(2^32 − 1)); three points; sixteen (point; symbol) pairs | field multiplication / exponentiation (later sections) |

Of the 201 answers, 41 are field-1 only (vec:39–42, 44–59, 65–69, 75–80, 87–91, 150–154) *[derived]*; 160 are usable for a field-2 verifier.

Replay notes:

- A dependency chain that needs only H and sampling: vec:15 → vec:16 (H 169/1); with pattern(32) "5 i + 1" → vec:18 (H 172, label 7); with vec:17 → vec:19 and vec:20 (H 160); then the rounds of py:832–853 → vec:22–35.
- vec:36–37 need the name built by `table_name(pattern(32, 13, 4), configuration_digest([b"toy\n"]), 10, 3, 40, 9, 1, 40)` and two coordinates (py:854).
- vec:144–148: the parameters' bytes are not printed; rebuild them as `parameters_head(2, plan_bytes(2, 40, 8, 0, 1, 1, plan)) + item("configuration", conf)` with the three entries of py:932–933 (`toy file: seed`, `toy file: answer`, `toy file: positions`), label 9, empty statement, random bytes pattern(32, 5, 1), kinds 3, 7, 4, tree number 0, columns (100 + x, 200 + x, 300 + (x mod 2)), salts pattern(40, 3, 9 + x) (py:886–887, py:934–954).
- Proof-of-work vectors give the *least* nonce (vec:25, vec:146); a verifier only needs to test the given nonce.

---

## 10. Pseudocode for the primitives of sections 2–7

`u64` values are abstract here; section 11 gives their 32-bit forms. `REJECT` ends verification with a rejection. `read(n)` takes the next n bytes of the file and REJECTs if fewer are left (F:1094).

### 10.1 Encodings (R1.x, R4.1)

    word(x)          = the 8 bytes of x, lowest first
    text(s)          = word(len(s)) ‖ s                      # ASCII
    bytestr(b)       = word(len(b)) ‖ b
    item(name, v)    = text(name) ‖ word(len(v)) ‖ v
    enc_E(e)         = word(e0) ‖ word(e1) ‖ word(e2)
    read_F()         : w = LE64(read(8)); if w >= p: REJECT; return w
    read_E()         : return (read_F(), read_F(), read_F())

### 10.2 BLAKE2b's compression function (RFC 7693 3.2; py:547–622)

    IV = 6a09e667f3bcc908 bb67ae8584caa73b 3c6ef372fe94f82b a54ff53a5f1d36f1
         510e527fade682d1 9b05688c2b3e6c1f 1f83d9abfb41bd6b 5be0cd19137e2179
    SIGMA[0] =  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
    SIGMA[1] = 14 10  4  8  9 15 13  6  1 12  0  2 11  7  5  3
    SIGMA[2] = 11  8 12  0  5  2 15 13 10 14  3  6  7  1  9  4
    SIGMA[3] =  7  9  3  1 13 12 11 14  2  6  5 10  4  0 15  8
    SIGMA[4] =  9  0  5  7  2  4 10 15 14  1 11 12  6  8  3 13
    SIGMA[5] =  2 12  6 10  0 11  8  3  4 13  7  5 15 14  1  9
    SIGMA[6] = 12  5  1 15 14 13  4 10  0  7  6  3  9  2  8 11
    SIGMA[7] = 13 11  7 14 12  1  3  9  5  0 15  4  8  6  2 10
    SIGMA[8] =  6 15 14  9 11  3  0  8 12  2 13  7  1  4 10  5
    SIGMA[9] = 10  2  8  4  7  6  1  5 15 11  9 14  3 12 13  0

    G(v, a, b, c, d, x, y):
        v[a] = v[a] + v[b] + x  (mod 2^64);  v[d] = rotr64(v[d] xor v[a], 32)
        v[c] = v[c] + v[d]      (mod 2^64);  v[b] = rotr64(v[b] xor v[c], 24)
        v[a] = v[a] + v[b] + y  (mod 2^64);  v[d] = rotr64(v[d] xor v[a], 16)
        v[c] = v[c] + v[d]      (mod 2^64);  v[b] = rotr64(v[b] xor v[c], 63)

    F(h[0..7], m[0..15], t_lo, t_hi, last):
        v[0..7] = h;  v[8..15] = IV
        v[12] ^= t_lo;  v[13] ^= t_hi
        if last: v[14] ^= ffffffffffffffff
        for r = 0 .. 11:
            s = SIGMA[r mod 10]
            G(v, 0, 4,  8, 12, m[s[0]],  m[s[1]]);   G(v, 1, 5,  9, 13, m[s[2]],  m[s[3]])
            G(v, 2, 6, 10, 14, m[s[4]],  m[s[5]]);   G(v, 3, 7, 11, 15, m[s[6]],  m[s[7]])
            G(v, 0, 5, 10, 15, m[s[8]],  m[s[9]]);   G(v, 1, 6, 11, 12, m[s[10]], m[s[11]])
            G(v, 2, 7,  8, 13, m[s[12]], m[s[13]]);  G(v, 3, 4,  9, 14, m[s[14]], m[s[15]])
        return h[i] xor v[i] xor v[i+8]   for i = 0 .. 7

### 10.3 H (R2.1–R2.2) *[checked against hashlib]*

    H(number, tree, index, start, data, W = 0, s8 = 0):
        out   = 64 if number == 162 else 32
        start = 0^32 if start is none
        msg   = word(number + 2^16*tree + 2^32*W + 2^56*s8) ‖ word(index) ‖ data
        h[0]  = IV[0] xor 0x01010000 xor out
        h[1..3] = IV[1..3]
        h[4+i]  = IV[4+i] xor LE64(start[8i .. 8i+8])          i = 0 .. 3
        n = len(msg);  B = ceil(n / 128)                        # n >= 16, so B >= 1
        for k = 0 .. B-1:
            block = msg[128k .. 128k+128], zero-padded to 128 bytes
            m[i]  = LE64(block[8i .. 8i+8])                     i = 0 .. 15
            if k < B-1: h = F(h, m, 128*(k+1), 0, false)
            else:       h = F(h, m, n,          0, true)
        return word(h[0]) ‖ … ‖ word(h[out/8 - 1])

### 10.4 Digests of section 4

    config_digest(files)                 = H(169, 0, 2, none, word(#files) ‖ for each f: word(len f) ‖ f)
    params_digest(params_bytes)          = H(169, 0, 1, none, params_bytes)
    run_value(label, pd, random32)       = H(172, 0, label, none, pd ‖ random32);  REJECT if it is 0^32
    first_value(label, pd, S, run)       = H(160, 0, label, none,
                                             pd ‖ word(len S) ‖ S ‖ word(0) ‖ (word(1) ‖ run  if run is given  else  word(0)))
    table_name(root, conf, a, entries, tail, v, answers, salt_bytes)
                                         = root ‖ conf ‖ word(a) ‖ word(entries) ‖ word(tail) ‖ word(v) ‖ word(answers) ‖ word(salt_bytes)
    record_seeds(name):                  # R4.8; s = fifth word of the name; c = least c with 2^c >= entries
        chain = (label = 2^32, rho = first_value(2^32, 0^32, name, none), i = 0)
        round(chain, msg = empty, kind = 3, w = 0, nonce = 0)
        return [ ( [sample_E() for c times], sample_E_nonzero() )  for s times ]
    commitment_id(conf, name, seeds, answers)
                                         = H(179, 0, 0, none, conf ‖ word(112) ‖ name
                                             ‖ word(s*(c+1)) ‖ for each seed: its c coordinates ‖ its factor
                                             ‖ word(#answers) ‖ the answers ‖ word(0))

### 10.5 A round, and the sequence of words (R5.2–R5.5, R6.1)

    call(chain, i, rho, msg, kind, w, nonce, j)
        = H(162, chain.label, i, rho, msg ‖ word(kind + 2^8*w + 2^16*j) ‖ word(nonce))        # 64 bytes

    round(chain, msg, kind, w, nonce):
        require len(msg) mod 8 == 0 and 1 <= kind <= 7 and w <= 64
        require (w > 0 or nonce == 0) and (kind != 7 or w == 0) and (kind != 6 or w == 0)
        i  = chain.i + 1
        C0 = call(chain, i, chain.rho, msg, kind, w, nonce, 0)
        if w > 0 and (LE64(C0[0..8]) mod 2^w) != 0: REJECT              # w = 64: the whole word is 0
        stream = (prev = chain.rho, i, msg, kind, w, nonce, off = 4 if w == 0 else 8, taken = 0)
        chain.rho = C0[0..32] if w == 0 else C0[32..64]
        chain.i   = i

    next_word(stream):
        g = stream.off + stream.taken;  stream.taken += 1
        C = call(chain, stream.i, stream.prev, stream.msg, stream.kind, stream.w, stream.nonce, g div 8)   # cache per j
        return LE64(C[8*(g mod 8) .. 8*(g mod 8) + 8])

### 10.6 Sampling (R6.2–R6.10), field 2

    sample_F():            repeat 6 times: w = next_word(); if w < p: return w
                           return 0
    sample_E():            return (sample_F(), sample_F(), sample_F())
    sample_E_nonzero():    repeat 2 times: e = sample_E(); if e != (0, 0, 0): return e
                           return (1, 0, 0)
    sample_position(k):    return next_word() mod 2^k
    sample_trits(n):       for t = 0 .. n-1:
                               if t mod 32 == 0: w = next_word()
                               j = t mod 32
                               out[t] = 0 if bit(w, 2j) == 0 else (1 if bit(w, 2j+1) == 0 else -1)
    sample_seal():         return word(next_word()) ‖ word(next_word()) ‖ word(next_word()) ‖ word(next_word())
    sample_seed(v):        return ([sample_E() for v times], sample_E_nonzero())

    by kind, from the entry (E = word 5, NZ = word 6, P = word 7, k = word 8, T = word 9):
        1: E elements, all by sample_E_nonzero if NZ > 0 else all by sample_E
        2: one sample_E
        3: s = NZ seeds with v = E / s - 1 coordinates each
        4: draws = [sample_position(k) for P times]; list = sorted set of draws; then sample_E if E == 1
        5: sample_trits(T)
        6: seal = sample_seal()
        7: nothing

### 10.7 Leaves, vertices, the walk, an opening (R7.3–R7.10, R7.15)

    leaf_bytes(column, salt):                                   # W = len(column), s = len(salt)
        data = word(column[0]) ‖ … ‖ word(column[W-1])
        r = (16 + 8*W) mod 128
        if r + s > 128: data = data ‖ 0^(128 - r)
        return data ‖ salt
    leaf_digest(number, tree, a, x, start, column, salt)
        = H(number, tree, 2^a + x, start, leaf_bytes(column, salt), W = len(column), s8 = len(salt)/8)
    vertex(conf, L, R)          = H(166, 0, 0, conf, L ‖ R)
    binding_vertex(conf, L, R)  = H(178, 0, 0, conf, L ‖ R)

    count_given(a, xs):                                         # dry walk; xs increasing   [checked]
        g = 0; now = xs
        for d = a down to 1:
            nxt = []; v = 0
            while v < len(now):
                i = now[v]
                if i even and v+1 < len(now) and now[v+1] == i+1: v += 2
                else: g += 1; v += 1
                append (i div 2) to nxt
            now = nxt
        return g

    open_tree(T, L, k):          # T: number (164 or 174), tree, a, W, s, start, root; L: the round's list over [0, 2^k)
        xs = L if T.a >= k else sorted set { x mod 2^T.a : x in L }
        for x in xs: column = [read_F() for W times]; salt = read(s)
                     value[x] = leaf_digest(T.number, T.tree, T.a, x, T.start, column, salt)
        now = [(x, value[x]) for x in xs]
        for d = T.a down to 1:
            nxt = []; v = 0
            while v < len(now):
                (i, val) = now[v];  enter(T.root, d, i, val)
                if i even and v+1 < len(now) and now[v+1].place == i+1:
                    enter(T.root, d, i+1, now[v+1].value)
                    append (i div 2, vertex(conf, val, now[v+1].value)) to nxt;  v += 2
                else:
                    sib = read(32);  enter(T.root, d, i xor 1, sib)
                    append (i div 2, vertex(conf, sib, val) if i odd else vertex(conf, val, sib)) to nxt;  v += 1
            now = nxt
        if now[0].value != T.root: REJECT
        return the columns

    enter(root, d, i, value):    # R7.14; table keyed by (root's 32 bytes, 2^d + i)
        if the key holds another value: REJECT;  else store value

### 10.8 The binding tree's root (R7.18; path order from F:1057–1058 and py:250–257)

    binding_root(depth, slot, conf, seal, salt, path[0 .. depth-1]):    # path[0] = the sibling of the leaf
        if slot >= 2^depth: REJECT
        node = H(173, 0, 2^depth + slot, conf, seal ‖ salt, W = 4, s8 = len(salt)/8)
        for sib in path: node = binding_vertex(conf, sib, node) if slot odd else binding_vertex(conf, node, sib);  slot = slot div 2
        return node                                                     # compared with nothing

### 10.9 Reading one chain from a file (R8.1–R8.10 with R4.5, R5.x) — skeleton

    read_chain(label, plan, params_bytes, statement_bytes, case):
        pd  = params_digest(params_bytes)
        run = none
        if case == (a): run = run_value(label, pd, read(32))
        if case == (b): run = run_value(label, pd, the 32 bytes named by the protocol)
        chain = (label, rho = first_value(label, pd, statement_bytes, run), i = 0)
        for each entry e of the plan that is a round of this chain (skip `RECORD`):
            msg = read(e.message_bytes)      # cut into items by the protocol; every element by read_F, roots raw (R8.8)
            nonce = 0
            if e.w > 0: nonce = little-endian integer of read(plan.nonce_bytes)
            round(chain, msg, kind_of(e.name), e.w, nonce)
            sample by kind (10.6)
            if e.positions > 0:
                if plan.position_bytes > 0:
                    for x in list (increasing): if little-endian integer of read(plan.position_bytes) != x: REJECT
                for each stored tree this round reads, in the order of the statement's items: open_tree(...)
                for each of the chain's own trees read at this list, by increasing place:   open_tree(...)
        return chain          # its seal, if the last round has kind 6

### 10.10 The three files — skeleton (R13.1–R13.3, R14.1–R14.2)

    key file:    require read(4) == "CPIK" and read(4) == "H821"
                 root = read(32);  answers = [read_E() for 2^v * answers_per_row times]
                 one-time chain (case a) -> seal_1
                 slot: require LE64(read(8)) == 0;  salt = read(salt_bytes)      # binding tree of depth 0
                 shared chain (case b)   -> seal_2
                 second chain (case a)
                 require no byte left
    leaf file:   require read(4) == "CPEN" and read(4) == "H821"
                 root = read(32);  answers = …;  link's chain (case a);  require no byte left
    proof file:  require read(4) == "CPPF" and read(4) == "H821";  k = LE32(read(4))   # must be the held table's number
                 first chain (case a) -> seal_1
                 slot = LE64(read(8)) (REJECT unless < 2^depth);  salt = read(salt_bytes);  path = depth × read(32)
                 shared chain (case b, 32 bytes = binding_root(...)) -> seal_2
                 second chain (case a; statement has seal_1 then seal_2)
                 require no byte left

### 10.11 K and TK (R15.3) on 32-bit words

    K(num, w[0 .. n-1]):
        h = IV;  h[0] ^= 0x01010040
        B = max(1, ceil(n / 32))
        for b = 0 .. B-1:
            blk = w[32b .. 32b+32], zero-padded to 32 words
            m[i] = blk[2i] + 2^32 * blk[2i+1]                 i = 0 .. 15
            t_lo = 128*(b+1) if b < B-1 else 4*n
            h = F(h, m, t_lo, num + 2^32 * n, b == B-1)
        return [low32(h[0]), high32(h[0]), low32(h[1]), high32(h[1]), low32(h[2]), high32(h[2]), low32(h[3]), high32(h[3])]
    TK(w):                                                     # len(w) >= 8
        num = 10
        loop: w = concatenation of K(num, piece) over the pieces of 128 words of w
              if len(w) == 8: return w
              num = 11

---

## 11. 64-bit pressure points (target has 32-bit integers only)

Recipes are for a 64-bit value kept as (hi, lo), each 32 bits. *[checked]* marks recipes verified numerically (0.2).

| # | where | what is needed | 32-bit form |
|---|---|---|---|
| 1 | every "word" (R1.1): lengths, counts, plan words, enumerations | 64-bit little-endian encode / decode | bytes 0–3 = lo, bytes 4–7 = hi |
| 2 | canonical test of an element of F (R1.3) and the sampling attempt (R6.3) | 64-bit compare with p | `w >= p` iff hi = 0xFFFFFFFF and lo ≠ 0 *[checked]* |
| 3 | BLAKE2b's G (every use of H, and K) | 64-bit addition modulo 2^64 of three terms | add lo halves, carry into hi; twice |
| 4 | BLAKE2b's G | rotr64 by 32, 24, 16, 63 | 32: swap halves. 24: lo' = (lo >> 24) or (hi << 8), hi' = (hi >> 24) or (lo << 8). 16: lo' = (lo >> 16) or (hi << 16), hi' = (hi >> 16) or (lo << 16). 63: hi' = (hi << 1) or (lo >> 31), lo' = (lo << 1) or (hi >> 31) *[checked]* |
| 5 | BLAKE2b's state | 64-bit xor; IV and h[0] constants as two halves | per half |
| 6 | BLAKE2b's counter t (128 bits in RFC 7693) | H: the string has at most 2^32 − 128 bytes, so t fits in one 32-bit limb and the other three are 0 *[derived from R2.3]*. K: t's low 64 bits = bytes fed (up to 4n < 2^34: two limbs); high 64 bits = num + 2^32·n = limbs (lo = num, hi = n) | xor into v[12], v[13] |
| 7 | BLAKE2b's last-block flag | v[14] xor all ones | invert both halves |
| 8 | the hash's label, first word (R2.1) | fields at bit offsets 16, 32, 56 | lo = number or (tree mod 2^16) << 16; hi = W or (s8 << 24) for a leaf; under 162: hi = label >> 16 *[checked]* |
| 9 | the chain label 2^32 of R4.8 | does not fit 32 bits | index word of 160 = (hi 1, lo 0); first label word of 162 = (hi 0x00010000, lo 162) *[derived; vec:12 has this label]* |
| 10 | a leaf's index 2^a + x (R7.4), a ≤ 48 | up to 49 bits | hi limb needed once a ≥ 32 |
| 11 | a round's index i (R5.2), below 2^63 | 64-bit word in the label | fits 32 bits in practice (toy key file: 711 rounds, vec:170) |
| 12 | the call's word kind + 2^8·w + 2^16·j, j < 2^48 (R5.2) | packing | lo = kind or (w << 8) or ((j mod 2^16) << 16); hi = j >> 16 |
| 13 | the nonce (R8.2): up to 8 bytes in a file, a word in the hash | 64-bit value | read low bytes into lo then hi |
| 14 | proof-of-work test (R5.5), w in 0..64 | low w bits of a 64-bit word | w ≤ 32: lo mod 2^w = 0 (w = 32: lo = 0); w > 32: lo = 0 and hi mod 2^(w−32) = 0. A shift by 32 must not be computed in 32 bits |
| 15 | a position (R6.6), k < 64 | low k bits of a word | k ≤ 32: from lo; k > 32: (hi mod 2^(k−32), lo). In practice k ≤ 48 (R7.16) |
| 16 | matrix entries (R6.7) | bit pairs 2j, 2j + 1 of a 64-bit word, j = 0..31 | j < 16 from lo, j ≥ 16 from hi |
| 17 | sorting and de-duplicating positions (R6.6), listed positions (R8.2), short positions (R7.2) | compare / mask of positions | 64-bit compare only if k > 32 |
| 18 | record-of-values key 2^depth + place (R7.14) | up to 49 bits | pair (depth, place) is an equivalent key *[inference]* |
| 19 | sizes: opening = m·(8W + s) + 32g bytes (R7.8); W < 2^24 (R2.3) | products of sizes | guard against 32-bit overflow |
| 20 | seals, digests, a seal "as four words" in a binding leaf (R7.18) | none | treat as raw bytes: word(LE64(x)) = x |
| 21 | field and extension-field arithmetic (128-bit products, reduction modulo p) | **not needed by sections 1–7** *[inference]*: elements are parsed, compared with 0 and hashed | needed by later sections; in the script only `point` / `symbol` (py:749–764, R12.11) and the assertion py:797–798 multiply modulo p |
| 22 | 4-byte integers: version word and a proof's number in a head (R13.1, R14.2); all words of K / TK and of the item `request` (R15.1) | native 32-bit | K's message words pair up as m[i] = (hi = w[2i+1], lo = w[2i]) with no conversion |

---

## 12. Open questions, ambiguities, things not determined

Defined outside sections 1–7 (needed before the primitives above can be driven):

1. The seven chains' label values (R13.4, R14.3, R14.9, R14.10; F:255–256).
2. The table of round names with their kinds (R14.11; F:308–309), and how plans and shapes are derived from the public files (section 8; F:860–862).
3. What each round's prover's message consists of, item by item, including where roots stand inside a message (sections 9–11; R8.8 F:928–929). Sections 1–7 fix only: answers first after a kind-3 round (R8.3), the hiding polynomial's sum last in kind 2 (R8.4), roots in tree-number order (R8.6).
4. Which trees a round opens (R13.12; F:948–949), the notices and leaf classes that drive R7.12 (R12.3), and which chains adopt which tree (R13.7, R14.10).
5. The names and order of the statement and parameter items of each chain (sections 9, 10, 12), including the item that holds a key file's binding-tree root (R13.6; F:484–485).
6. Whether and where a verifier compares the commitment ID (13.5; F:69). Section 4 only defines its bytes.
7. The second hash function's normative text is R15.3 / 12.6, outside this scope. I read F:1183–1304 and F:1401–1449 only; the rest of 12.6 (the list of digests, how the four tables are made) was not analysed.

Ambiguities and observations inside the scope:

8. Multiplication in E is not written out in sections 1–7; only the modulus X^3 − c is (R1.4). The rule in 2.4 is derived, not quoted.
9. R7.14's session: the rule says all files that one verdict reads; what the programs do is in 17.2, item 4 (pointer at F:704; the item begins at F:3983), which I did not read. Whether a second verifier must keep records across the key file, the leaf file and the proof file (R7.19 F:822–824 says there is something to compare there) or may keep none ("no bound depends on it", F:710–711) needs a decision by the lead after reading 17.2, item 4.
10. R7.14 says a rejected opening "leaves the record as it found it" (F:699–700). For a verifier that stops at the first rejection (F:864–865) this never matters *[inference]*; the reference `walk` has no rollback.
11. Proof-of-work bits: the format admits 0 to 64, "the programs admit fewer: 17.2, item 5" (F:456–457). The actual bound was not read; item 5 begins at F:3989 ("*Narrower bounds.* The binding tree's depth is at most 48 by R14.6 and at most 8 in `cp_verify`" is its first line).
12. "How the programs end" in the cases of R2.7 and R5.7 is 17.2, item 1 (pointers at F:201, F:489–490; the item begins at F:3949 and its first line says `cp_verify` can end with `NOT CHECKED`): not read; it may be a third result or a process abort rather than a rejection.
13. R5.3: a seal round with w > 0 is "not a plan of the format" but is not among R5.7's rejections; a verifier that derives plans by section 8 "meets none" (F:461–465). Whether to test it is a design choice; 10.5 tests it.
14. The key file's binding leaf: sections 6–7 say the slot is the word 0 plus a salt and the tree has depth 0 (F:988, F:1003–1004), and for a proof file that "the first chain's seal, the salt and the path give `the binding tree's root`" (F:1062–1063). That the key file's leaf content is the one-time chain's seal is my *inference* by analogy; R13.6 decides.
15. R1.9's rejection of "a name with a byte outside 0x20 to 0x7E": no file of section 7 holds a name (R8.1), so for a verifier of the three files this seems to bind only parsers of hashed strings or of public files *[inference]*.
16. R6.6 says k < 64; the case k = 0 is not mentioned. The reference consumes one word and yields 0 (py:180–181).
17. In kind 4, R6.10 speaks of "an element of E" (singular) after the positions; whether an entry may ask for more than one is not stated. 10.6 assumes at most one *[inference]*.
18. In kind 1, "either each of them must be non-zero, or each may be 0" (F:504–505): so entry word 6 is 0 or equals word 5 *[derived]*; a mixed entry is presumably "not an entry of the format".
19. The `RECORD` entry sits in a plan's bytes but is not a round: an implementation that builds the parameters' bytes must include it while the round loop skips it (F:309–313). Its position and words are R13.15 (outside scope).
20. Field 1 (`H811`) is part of the format but "the programs of this repository serve `H821` alone" (F:291); a field-2 verifier rejects any other version in a head (R13.1 F:976). Whether a plan's first two words (field, hash) are ever read from anywhere but the verifier's own derivation is section 8's matter.
21. `format_rules.py` contains no decoder: R1.9's read-back rejections and R7.10's reading of an opening have no executable reference in this file (the `read_*.py` scripts were not read).
22. The vectors give no negative end-to-end case (a file that must be rejected); rejection behaviour is covered only by the element-level lines vec:61–69 and the R7.14 lines vec:135–136.
