# 08 — Golden corpus and the `cp_verify` oracle

> Status: frozen
> Recovered working notes, 2026-11-23. Upstream excerpts from FlashProve, Copyright 2026 Anthropic PBC, Apache-2.0.

Source: FlashProve 0.16.0-rc.26, commit `9e2bdd8` (read-only checkout). All `path:LINE` citations are relative to the upstream root. "Measured" means I ran it on this machine (macOS Darwin 25.6 arm64, 16 cores, 48 GiB, Apple clang 21.0.0, Python 3.15.2) in a private copy; raw logs are under `<scratchpad>/oracle-build/out/`. Statements tagged **[inference]** are mine, not upstream's.

## Verdict in five lines

- `verifier/build.sh` does **not** run on macOS (exit 2; GNU-only `stat -c`, `find -perm /022`, `readlink -z`, `mv -T`; default compiler flag `-fno-ipa-modref`; ELF-only linker flags).
- A **native macOS arm64 build works with no source change and no shim**: one direct `clang++` call on `verifier/src/cp_verify.cpp` with the script's own `--clang` flags minus `-Wl,-z,relro,-z,now,-z,noexecstack`. 19 s to compile.
- That binary prints the documented source digest (`build=93afdaf5…9595`), accepts all four stored proofs with the exact four closing lines the READMEs print, rejects 79 + 10 + 10 + 23 upstream-defined altered sets under the expected names, and reproduces 1,219 stored planner lines that the upstream (Linux) build printed.
- Measured: small proofs 0.63–0.65 s / ~200 MiB; full-size 8.0–8.1 s / ~3.9 GiB (default one thread), 6.4 s with `-j 8`.
- It is still not the reference build (upstream's figures and tests use g++ 13 on Linux; `--clang` was only ever tried with clang 18.1.3). Treat it as a fast local oracle and anchor goldens on a Linux g++ build in CI.

---

# Part A — inventory

## 1. Stored proofs

Common facts:

- All stored proofs are for synthetic weights at the default setting; none was made by the released programs; the released `cp_verify` accepts each (`examples/README.md:6-8`).
- Every stored-proof directory has the same layout (`examples/README.md:33-34`): `config/` (`policy.txt` parameter file, `KL.bin` quantization scales, `layout.txt`), `ivk/` (`key.bin`, `leaf/0.bin`), `example.req`, `example.y`, `example.proof`, `ID.txt`, `SHA256SUMS` (`examples/accepted-proof/README.md:40-48`).
- Request file: T token ids, then r and e, as 32-bit little-endian words; the proof is about tokens r+1 to e counted from 0 (`examples/accepted-proof/README.md:44`). `example.y` is one 32-bit LE word.
- `SHA256SUMS` mechanism: nine lines `<sha256>  <relative path>` covering `ID.txt`, the three config files, `example.proof`, `example.req`, `example.y`, `ivk/key.bin`, `ivk/leaf/0.bin` (`examples/accepted-proof/SHA256SUMS:1-9`); it covers neither `README.md` nor itself. Check: `(cd examples/accepted-proof && sha256sum -c SHA256SUMS)` (`examples/accepted-proof/README.md:48`). Measured: all four sets pass with macOS `/sbin/sha256sum -c`.
- `cp_verify` prints `build=93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595` in its `result-v1` line when built from this repository's sources; it is a digest of the source files, not of compiler or flags; the README pages show `<64 hex digits>` in its place; no upstream test compares it (`examples/README.md:36-41`).
- In the examples the commitment ID after `-id` ships with the example; in a real check it must not (`examples/accepted-proof/README.md:7`, `:58`).
- No false files for `cp_verify` made by cheating programs are stored (`examples/README.md:28-31`).

Sizes below are from `ls -l` on the checkout (bytes).

### 1.1 `examples/accepted-proof/` — small, exact match

| file | bytes |
|---|---|
| `config/policy.txt` / `KL.bin` / `layout.txt` | 2,479 / 464 / 27,038 |
| `ivk/key.bin` / `ivk/leaf/0.bin` | 1,096,408 / 536,952 |
| `example.req` / `example.y` / `example.proof` | 264 / 4 / 4,145,300 |
| `ID.txt` / `SHA256SUMS` / `README.md` | 65 / 714 / 9,214 |

- Model: synthetic, 8 layers, 4 routed experts, 64 tokens per request, vocabulary 512 (`examples/accepted-proof/README.md:54`). Configuration `prover/examples/target_small_f2_roomy`; made with `cp_commit … -M 1` and `cp_prove` on one H100 (`:67`).
- Request: 64 tokens, r = 60, e = 64; `example.y` = 199 (`:44-45`). The proof states tokens 61, 62, 63 and the token after the request are each the committed model's first choice (`:52`).
- Command (`:9-15`), from the repository's top directory:

```sh
bin/cp_verify examples/accepted-proof/config examples/accepted-proof/ivk \
  examples/accepted-proof/example.req examples/accepted-proof/example.y \
  examples/accepted-proof/example.proof \
  -id 79a5a2bc7a469b40df73dedf40abeb740671e8ae8077738bd3743897aeb22183 -q
```

- Expected: exit code 0, "under two seconds", last four lines (`:17-24`):

```
commitment: 49 closeness rounds of the one-time files rest on another source than the bound within a third of the distance; the table has a record: the binding of the weights rests on the theorem on codes (ePrint 2025/2055, Theorem 4.6), taken as given
proof of work: up to 32 bits counted in 38 rounds; with it the least round has 128.00 bits, without it 96.23 bits
result-v1 status=0 claim=exact-match id=79a5a2bc7a469b40df73dedf40abeb740671e8ae8077738bd3743897aeb22183 bits=128 work=32 work-rounds=38 least-round=128.00 least-round-without-work=96.23 commitment-assumed-rounds=49 record=1 r=60 e=64 T=64 tokens=61..63 y=yes policy=exact-match C=256 theta=256 cap=0 s=16 sh=8 sT=4 F=24 above-clip=0 leaf=0 stages=key,leaf,request dw=8 build=<64 hex digits>
YES
```

- Upstream documents only these four lines per example, plus a 12-line sample of the closing block for this example in `docs/verifying.md:290-305` (`commitment ID:`, `id: named by the caller and equal`, `h_par=0adb76ee…`, `weight hiding: NOT CHECKED BY THIS CALL …`, `covered: r=60 e=64 T=64 C=256 theta=256 cap=0 s=16 sh=8 positions=60..63 tokens=61..63 y=yes next-token=no policy=exact-match above-clip=0 (...)`, three `stage <name>: work:` lines, then the four lines above). The complete stdout is not stored upstream. Measured on my build: 105 lines with `-q`, 136 without (see Part B for hashes).

### 1.2 `examples/accepted-proof-clipped-gap/` — small, clipped-gap policy

| file | bytes |
|---|---|
| `config/policy.txt` / `KL.bin` / `layout.txt` | 2,486 / 464 / 27,038 (`layout.txt` has the same SHA-256 as 1.1's) |
| `ivk/key.bin` / `ivk/leaf/0.bin` | 1,095,160 / 536,544 |
| `example.req` / `example.y` / `example.proof` | 264 / 4 / 4,151,892 |

- Configuration `prover/examples/target_small_f2_gap`, own seed and commitment (`examples/accepted-proof-clipped-gap/README.md:62`); the commitment ID covers `policy.txt`, so each policy needs its own commitment (`:30`).
- Policy lines `C 9244130`, `theta 323343`, `cap 1`; cost = logit gap + 2^sh (256); exact match is the case C = theta = 2^sh, cap = 0 (`:32-40`).
- Request: 16-token prompt + 32-token reply, r = 15, e = 47, proof about tokens 16..47; e < 64 so the proof says nothing about the next token and `example.y` holds 0 (`:46`).
- Command (`:9-15`):

```sh
bin/cp_verify examples/accepted-proof-clipped-gap/config examples/accepted-proof-clipped-gap/ivk \
  examples/accepted-proof-clipped-gap/example.req examples/accepted-proof-clipped-gap/example.y \
  examples/accepted-proof-clipped-gap/example.proof \
  -id 8df714349b76202d6f302bb80b33d6d0798bd81d987b9e387038b7fd24c55ae6 \
  -policy clipped-gap,9244130,323343,1,16,8 -q
```

- Expected: exit code 0; last four lines (`:17-24`):

```
commitment: 49 closeness rounds of the one-time files rest on another source than the bound within a third of the distance; the table has a record: the binding of the weights rests on the theorem on codes (ePrint 2025/2055, Theorem 4.6), taken as given
proof of work: up to 32 bits counted in 38 rounds; with it the least round has 128.00 bits, without it 96.23 bits
result-v1 status=0 claim=policy id=8df714349b76202d6f302bb80b33d6d0798bd81d987b9e387038b7fd24c55ae6 bits=128 work=32 work-rounds=38 least-round=128.00 least-round-without-work=96.23 commitment-assumed-rounds=49 record=1 r=15 e=47 T=64 tokens=16..47 y=no policy=clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8 sT=4 F=24 above-clip=1 leaf=0 stages=key,leaf,request dw=8 build=<64 hex digits>
WITHIN LIMITS: clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8
```

- `WITHIN LIMITS` is not `YES` although the exit code is the same (`:26`). Without `-policy`, or with other values than `policy.txt` sets, the call ends `NO: policy`, exit code 1 (`:42`; `examples/README.md:43-45`).

### 1.3 `examples/full-size/` — Maverick-shaped, exact match

| file | bytes |
|---|---|
| `config/policy.txt` / `KL.bin` / `layout.txt` | 2,629 / 2,784 / 224,975 |
| `ivk/key.bin` / `ivk/leaf/0.bin` | 3,290,496 / 2,942,944 |
| `example.req` / `example.y` / `example.proof` | 4,104 / 4 / 18,779,540 |

- Model shape of Llama 4 Maverick (48 layers, 128 routed experts), synthetic weights, none of Meta's weight files (`examples/full-size/README.md:3`, `:37`). Configuration `prover/examples/target_full_f2`, one H100, `cp_commit -keep-for-the-audit`, `cp_prove -in-step 1 -memory lean` (`:41`).
- Request: 1,024 tokens, r = 23, e = 1024; proof about tokens 24..1023 and the next token 52599: 1,001 tokens in one proof (`:35`).
- Command (`:9-14`):

```sh
bin/cp_verify examples/full-size/config examples/full-size/ivk \
  examples/full-size/example.req examples/full-size/example.y \
  examples/full-size/example.proof \
  -id 7a285919b43961861d9839530c26725accf26aa6d74e3c2afa31b9dc6bcd18fe -q
```

- Expected: exit code 0; needs ≥ 4 GiB free; no `-j` means one thread for the longest stage (`:7`). Last four lines (`:16-23`):

```
commitment: 86 closeness rounds of the one-time files rest on another source than the bound within a third of the distance; the table has a record: the binding of the weights rests on the theorem on codes (ePrint 2025/2055, Theorem 4.6), taken as given
proof of work: up to 32 bits counted in 71 rounds; with it the least round has 128.00 bits, without it 96.23 bits
result-v1 status=0 claim=exact-match id=7a285919b43961861d9839530c26725accf26aa6d74e3c2afa31b9dc6bcd18fe bits=128 work=32 work-rounds=71 least-round=128.00 least-round-without-work=96.23 commitment-assumed-rounds=86 record=1 r=23 e=1024 T=1024 tokens=24..1023 y=yes policy=exact-match C=256 theta=256 cap=0 s=15 sh=8 sT=4 F=24 above-clip=0 leaf=0 stages=key,leaf,request dw=8 build=<64 hex digits>
YES
```

### 1.4 `examples/full-size-clipped-gap/` — Maverick-shaped, clipped gap

| file | bytes |
|---|---|
| `config/policy.txt` / `KL.bin` / `layout.txt` | 2,631 / 2,784 / 224,975 (`KL.bin` and `layout.txt` byte-identical to 1.3's: `examples/full-size-clipped-gap/README.md:80`) |
| `ivk/key.bin` / `ivk/leaf/0.bin` | 3,293,720 / 2,943,992 |
| `example.req` / `example.y` / `example.proof` | 4,104 / 4 / 18,762,484 |

- Configuration `prover/examples/target_full_f2_gap` (`:76`). Policy `C 25856`, `theta 512`, `cap 1`, chosen by definition (theta = 2m, C = 101m, m = 2^sh = 256), not fitted (`:34-42`).
- Request: 1,024 tokens, r = 23, e = 1024; token 524 is the model's second choice (cost 10,745,515), the other 999 checked tokens cost 256 each; next token 61122 (`:58`).
- Command (`:9-15`):

```sh
bin/cp_verify examples/full-size-clipped-gap/config examples/full-size-clipped-gap/ivk \
  examples/full-size-clipped-gap/example.req examples/full-size-clipped-gap/example.y \
  examples/full-size-clipped-gap/example.proof \
  -id d62a9c1f6542db1e8ca422d0f50b2b9b40bf505c6bbfa87ec003bcae69c49191 \
  -policy clipped-gap,25856,512,1,15,8 -q
```

- Expected: exit code 0; last four lines (`:17-24`):

```
commitment: 86 closeness rounds of the one-time files rest on another source than the bound within a third of the distance; the table has a record: the binding of the weights rests on the theorem on codes (ePrint 2025/2055, Theorem 4.6), taken as given
proof of work: up to 32 bits counted in 71 rounds; with it the least round has 128.00 bits, without it 96.23 bits
result-v1 status=0 claim=policy id=d62a9c1f6542db1e8ca422d0f50b2b9b40bf505c6bbfa87ec003bcae69c49191 bits=128 work=32 work-rounds=71 least-round=128.00 least-round-without-work=96.23 commitment-assumed-rounds=86 record=1 r=23 e=1024 T=1024 tokens=24..1023 y=yes policy=clipped-gap C=25856 theta=512 cap=1 s=15 sh=8 sT=4 F=24 above-clip=1 leaf=0 stages=key,leaf,request dw=8 build=<64 hex digits>
WITHIN LIMITS: clipped-gap C=25856 theta=512 cap=1 s=15 sh=8
```

### 1.5 `examples/rejected-proofs/` — no stored proofs

Holds a script and three tables; no altered files are stored (`examples/rejected-proofs/README.md:3`). See section 2.

### 1.6 `examples/protocol-toy-false-files/` — not `cp_verify`'s format

- No README; described in `examples/README.md:23` and `:27-31`, in `LIST.tsv` and in the head of `stored_false_test.py`.
- Twelve false files and four honest controls of the library's toy instances (`examples/protocol-toy-false-files/LIST.tsv:2-17`): 3 false batch proofs (575–580 KB), 5 false key files (~500 KB), 2 false entry files (~131 KB), 1 false `product` proof (7,680 B), 1 false `links` proof (12,576 B); honest: 2 proofs, `key.file` (503,744 B), `entry.file` (131,432 B). `LIST.tsv` columns: file, sha256, checker (`proof-0`, `proof-1`, `key`, `entry`, `product`, `links`), must (`refuse`/`accept`), the words the checker must print, what the lie is (`LIST.tsv:1`).
- Eleven of the twelve were made by cheating builds whose code is not in the repository; the twelfth (`BENT_SWAP`) is an honest entry rearranged by a script (`examples/protocol-toy-false-files/stored_false_test.py:15-19`; `tests/new/second/README.md:25`).
- These files are not in the format that `cp_verify` reads (`examples/README.md:23`, `:30-31`).
- Run: build two checkers from `blocks/` with `make`, then `stored_false_test.py <frame folder> <new folder>` (`stored_false_test.py:21-24`; `SUITE.md:194`). Expected last line begins `stored_false_test.py: all 12 false files refused`, exit code 0 (`examples/README.md:23`). Exit 3 if a false file was accepted (`stored_false_test.py:30-32`). Not run here.

`examples/maverick/` and `quickstart-gpu.sh` need one H100 (`examples/README.md:24-25`) and store no proof.

## 2. Negative vectors: `try_altered_copies.py`

**What it does.** `try_altered_copies.py CP_VERIFY NEW_DIRECTORY [TABLE] [--example NAME]` (`examples/rejected-proofs/try_altered_copies.py:9`). It first checks the unaltered files (must be exit 0 and last line `YES`, or for the clipped-gap example `WITHIN LIMITS: clipped-gap C=… theta=… cap=… s=… sh=…` built from `policy.txt`: `:201-214`, `:478-482`), then for each table row makes one altered set and calls the verifier (`:486-502`).

**Verifier call.** `[verifier, <config dir>, <ivk dir>, example.req, example.y, example.proof, "-id", ID, *policy, "-q"]` (`:243-249`). stdout and stderr are merged and the **last line** of the merged text is the verdict (`:64-77`). A row passes iff exit code is 1 and the last line equals the table's fifth column exactly (`:493-500`).

**Table format** (five tab-separated columns: description, file, place, change, expected last line; `examples/rejected-proofs/altered_copies.tsv:1-21`):

- place: `first`, `middle` (length // 2), `last`, `end`; `byte N`; `token N` (byte 4N); `token first-checked` (reads r from the request, uses token r+1); `field NAME [#K]` (first byte of a named proof field) (`try_altered_copies.py:113-130`).
- change: `flip` (XOR 1: lowest bit of that byte), `cut` (drop that byte and all after), `append HEX` (at `end`), `put HEX` / `put HEX over HEX` (overwrite; the second HEX asserts the current bytes, so a row refuses to run on another file), `other-digit` (ID only: that hex digit becomes `0`, or `1` if it was `0`) (`:133-159`, `:183-190`).
- For `ID.txt` rows nothing is written; only the value after `-id` changes (`:185-190`). For a file under `config/` or `ivk/` the whole directory is copied beside the changed file, because the verifier takes directories (`:236-242`).

**Cases and expected names.**

| table | rows | expected last lines |
|---|---|---|
| `altered_copies.tsv` (`:22-31`) | 10 | proof bit flip / last byte cut / byte appended → `NO: proof-refused`; `key.bin` bit → `NO: key-refused`; `leaf/0.bin` bit → `NO: entry-refused`; prompt token / checked reply token → `NO: proof-refused`; `example.y` → `NO: reply-differs`; `KL.bin` bit → `NO: model-statement`; another ID → `NO: model-statement` |
| `altered_copies_clipped_gap.tsv` (`:5-14`) | 10 | same, except the `example.y` row: `NO: statement-range`, because e < T so `example.y` must hold 0 (`:1-4`) |
| `every_kind_of_item.tsv` (`:13-91`) | 79 | 24 `proof-refused`, 23 `entry-refused`, 19 `key-refused`, 2 `model-statement`, 2 `cp-key-head`, 2 `cp-proof-head`, 2 `token-range`, 2 `statement-range`, 1 `chain-refused`, 1 `cp-entry-missing`, 1 `reply-differs` (my tally of column 5) |

`every_kind_of_item.tsv` has 23 rows on `ivk/key.bin` (K, `:13-35`), 23 on `ivk/leaf/0.bin` (E, `:36-58`), 26 on `example.proof` (P, `:59-84`), 4 on `example.req` (R, `:85-88`), 3 on `example.y` (Y, `:89-91`); 72 `put`, 3 `cut`, 4 `append`. It aims at one row per *sort of item* (tag, root, message element, OOD answer, nonce, salt, digest, …), not every field (`examples/rejected-proofs/README.md:40`; `every_kind_of_item.tsv:1-12`). Its rows name byte offsets with `put NEW over OLD`, so it fits `examples/accepted-proof` alone (`every_kind_of_item.tsv:5-7`).

Rows a new verifier is most likely to get wrong **[inference]**:

- `P01` (`:59`): next token 199 written as 199 + p — a non-canonical field encoding → `NO: proof-refused`. `P05` (`:63`): a word equal to p in an early round → the distinct name `NO: chain-refused`. `K15`, `K20`, `E16`, `E19` (`:26`, `:31`, `:50`, `:53`): words p and 2^64−1 → refused.
- `P02` (`:60`): slot 28 written as 92 (low 6 bits are the true slot) → refused; a verifier that masks the slot accepts.
- `P03` (`:61`): another nonce that also yields the 20 bits of proof of work → refused (the nonce is in the transcript).
- `P19` (`:77`): leaf-table number +1 → `NO: cp-entry-missing`. `P20`/`P21` (`:78-79`): version `H811` for `H821`, magic `CPEN` for `CPPF` → `NO: cp-proof-head`. `K16`/`K21` (`:27`, `:32`): `NO: cp-key-head`. But the same changes on the leaf file (`E09`, `E20`: `:43`, `:54`) give `NO: entry-refused`.
- `K02`, `K22` (`:14`, `:33`): the anchor's root and its first stored record answer are covered by the commitment ID → `NO: model-statement`, not `key-refused`.
- `R03` (`:87`) e = 65 > T → `NO: statement-range`; `R04`, `Y02` (`:88`, `:90`) token = 512 = vocabulary size → `NO: token-range`; `Y03` (`:91`) 8-byte token file → `NO: statement-range`.

**Expected screen output** for the default call (`examples/rejected-proofs/README.md:20-36`):

```
The altered copies are written to /tmp/tmp.XXXXXXXXXX/altered-copies
the files as they are                  exit code 0   YES
    proof of work: up to 32 bits counted in 38 rounds; with it the least round has 128.00 bits, without it 96.23 bits
    by the verifier's own count, the weakest round has 128.00 bits with proof of work counted and the weakest without it has 96.23; no figure here is a security level
one bit of the proof changed           exit code 1   NO: proof-refused
the proof's last byte cut off          exit code 1   NO: proof-refused
one byte added to the proof            exit code 1   NO: proof-refused
one bit of ivk/key.bin changed         exit code 1   NO: key-refused
one bit of ivk/leaf/0.bin changed      exit code 1   NO: entry-refused
a prompt token changed                 exit code 1   NO: proof-refused
a checked reply token changed          exit code 1   NO: proof-refused
another token after the request        exit code 1   NO: reply-differs
another scale in KL.bin                exit code 1   NO: model-statement
another commitment ID                  exit code 1   NO: model-statement
10 altered sets: all rejected
```

Script exit codes: 0 all rejected as expected; 3 the verifier accepted an altered set; 2 wrong call, faulty table or missing file; 1 anything else (`try_altered_copies.py:23-25`, `:506`; `examples/README.md:49-51`).

**What it needs.** Python 3 standard library only (`try_altered_copies.py:28-37`), the path of a built verifier (`:445`, `:453-454`), the example files and a table (`:455-457`), and a new work directory whose ancestors are owned by the caller or root and are not group/other-writable without the sticky bit (`:458-462`). Only `field NAME` places need more: the verifier must answer `-plan request <policy> <KL> 128 -layout <layout> -prompt <req> -reply <y> -fields -q` with exit code 4 and `field: proof at <offset> …` lines (`:80-95`); none of the three shipped tables uses `field`. Disk: ~16 MB for the 10-row table, ~183 MB for the 79-row table; it writes only under the new directory and deletes nothing (`examples/rejected-proofs/README.md:14`, `:40`). Measured on macOS with my build: all three tables pass (Part B).

**Reuse for another verifier.**

- As-is it works for any binary with the same argv order, exit codes 0/1, and last-line strings. Because the fifth column is compared for equality, the new verifier must reproduce upstream's rejection *names*, or you pass a table of your own as the third argument. Note the merged stderr: a verifier that prints anything to stderr after its verdict breaks the "last line" read.
- The altered sets stay on disk as `<work>/NN/…` (`:488-490`), so one run against the oracle materialises a static corpus with oracle-confirmed names.
- The mutation logic is ~70 lines (`offset`, `altered`, `cases`: `:113-198`), Apache-2.0 (`:2-3`), and is reusable in a harness of our own **[inference]**.
- Upstream's own caveat: this is a demonstration that byte changes are noticed, not a soundness test; a cheating prover would not flip bits in an honest proof (`examples/rejected-proofs/README.md:54-56`).

A second CPU-only generator on the same stored files: `verifier/tests/record_altered_sets_test.py <cp_verify> <config> <ivk> <req> <y> <proof> <ID> <new folder>` (`verifier/tests/record_altered_sets_test.py:9`): 7 calls on the honest set (whole call, `-no-proof-of-work` → 14, part-calls → 3) and 23 altered sets around the stored OOD answers ("record", bytes 40..6183 of `key.bin` and of the leaf file), roots, and proof middle/cut/longer, each with an expected status and name (`SUITE.md:226`). Measured: all as expected on the small example.

## 3. Upstream tests that exercise the verifier on CPU

### 3.1 How the suite is organised

- `SUITE.md` is both the page and the input of `run_suite.py` (`SUITE.md:3`). 171 rows; 48 are named `verifier.*`, all of kind `cpu` (my count of the tables).
- The suite needs Linux with Landlock, `flock`, `make`, g++ 13 with libasan/libubsan, Python 3, `realpath` (`SUITE.md:29`); tests run confined by `tools/confine.py` (`SUITE.md:33`). **[inference]** `run_suite.py` is therefore not usable on macOS; I did not try. Any row's command can be run by hand outside the sandbox (`tests/README.md:26-28`).
- `./run_suite.py cpu <work>` leaves out every test that needs a row of kind `nvcc`, `gpu` or `gpu-by-run` (`SUITE.md:21`).
- Exit status of a test: 0 as expected, 1 not, 2 wrong call, 3 `cp_verify` accepted something it should have refused, 77 cannot run here (`SUITE.md:61-65`).

### 3.2 Rows that need only a built `cp_verify` (+ Python), no GPU

| row (`SUITE.md` line) | needs | asserts |
|---|---|---|
| `build.verifier` (105), `build.verifier.target` (106) | g++ | `verifier/build.sh --field 2 [- DIR]` exits 0 |
| `build.verifier.unit` (107) | g++ | compiles `cp_verify.cpp` with `-DCP_VERIFY_AS_A_UNIT` into `unit.o` and links `cp_configured_test` |
| `verifier.rejected_proofs` (229) | target build | `try_altered_copies.py` on both small examples: `10 altered sets: all rejected`, `YES` and `WITHIN LIMITS:` first lines |
| `verifier.record_altered_sets.example` (226), `.full` (227) | target build | 7 honest calls + 23 altered sets, each with status and name; `.full` runs on `examples/full-size` (4 slots, 5 min) |
| `verifier.call_accounting.examples` (201) | target build | the `accounting:` lines of a whole call equal the plan's; the `covered:` line is letter for letter what the page's rules give, on `accepted-proof` and `full-size` |
| `verifier.commitment_id.examples` (203) | target build | `cp_verify`'s commitment ID equals the one `docs/format/format_rules.py` forms (rules R4.8–R4.11) for three examples |
| `verifier.kit_rounds` (170), `verifier.kit_rounds_second` (171) | target build | `-plan request … -shapes` `round:` lines equal stored files (1,219 lines, 3 configurations); a second computation of the proximity tests' round errors |
| `verifier.example_kits` (206), `verifier.plan_tau` (222), `verifier.served.form` (233), `verifier.la_equals_lt` (212) | target build | planning calls and named refusals on parameter files with a line changed |
| `verifier.extreme_files` (207), `.full` (208) | target build | planning calls on altered inputs: no crash, no `NOT CHECKED`, none slow |
| `verifier.made_up_files.small/.full/.work` (214–216) | target build (+ a kit row) | synthetic key/leaf/proof files of valid lengths containing no proof: all stages run, expected statuses |
| `verifier.hostile_leaf_files` (211), `verifier.openings_left_out` (218) | unit + target build | leaf files a hostile sender could derive from an honest one; honest files with a whole Merkle opening removed |
| `verifier.clang_build` (202) | target build, clang++ | builds a second verifier with `build.sh --clang` and compares status and output with the g++ build on planning calls, made-up files and worlds |
| `integrations.cp_verify` (317) | `build.verifier`, pytest | 65 pytest cases of `integrations/check_proof.py` against the stored examples |

Rows needing no verifier build at all:

- Python known answers: `sources.format_vectors` (157), `verifier.format_hash` (168), `verifier.forest_values` (167), `verifier.hiding_coins` (169), `verifier.not_checked_names` (300).
- C++ unit/"twin" tests compiled with one g++ line each and run on CPU: `verifier.field_setting_test` (165), `verifier.forest_attention` (166), `verifier.weights_twin_test` (174), `verifier.forest_twin_test` (210), `verifier.link_door` (213), `verifier.one_chain_shell` (217), `verifier.pending_row` (220), `verifier.plan_record` (221), `verifier.psc_twin_test` (225), `verifier.req_chain_test` (230), `verifier.ws_build_fuzz` (237), `verifier.sanitized_walk` (232, 60 min, ASan/UBSan).

Rows of kind `cpu` that are GPU-dependent in practice, because they need `setup.target.other_parameters_worlds[.work]`, which is kind `gpu` and needs `cp_commit` and `cp_prove` (`SUITE.md:111-112`): `verifier.walker_on_a_world[.work]` (172–173), `verifier.entries_and_parts[.work]` (204–205), `verifier.extreme_proof_files` (209), `verifier.other_parameters` (219), `verifier.proof_fields_sweep[.work]` (223–224), `verifier.record_altered_sets.world` (228), `verifier.sanitized_files` (231), `verifier.served.form.world.kit` (234), `verifier.what_a_yes_covers[.work]` (235–236).

What the suite does not do: no row gives `cp_verify` a proof made by a cheating program (`SUITE.md:181`). In the known-answer rows `sources.format_vectors`, `verifier.forest_values`, `verifier.format_hash`, `verifier.kit_rounds` the stored answers are the same program's own output, so they show only that nothing changed (`SUITE.md:128`).

### 3.3 `verifier/tests/` file by file

Line numbers point at the file's own description.

| file | purpose |
|---|---|
| `call_accounting_test.py:7` | checks the `accounting:` and `covered:` lines of a whole call against the plan |
| `changed_sets.py:6` | shared helper: changes one file of an honest set at places `tools/audit/cut.py` names |
| `commitment_id_test.py:7` | the commitment ID per `FORMAT.md`, recomputed with `format_rules.py`, equals `cp_verify`'s |
| `entries_and_parts_test.py:8` | leaf table numbers, part-calls, bits above the target |
| `example_kits_test.py:8` | planning calls on `prover/examples` parameter files and changed lines |
| `extreme_files_test.py:8` | planning calls on altered input files; counts crashes and internal errors |
| `extreme_proof_files_test.py:8` | honest files, then copies altered to drive the verifier out of an array or into undefined arithmetic |
| `forest_lines.py:5` | helper: the `iota_*` lines a parameter file must state when a test changes a model's shape |
| `hostile_leaf_files_test.py:7` | leaf files a hostile sender could make from an honest one |
| `kit_rounds_test.py:8`, `kit_rounds_second.py:8` | planned rounds (error, work, count) against stored lines; second computation of proximity-test errors |
| `made_up_files_test.py:8` | synthetic key, leaf and proof files; needs no committer or prover |
| `not_checked_names.py:7` | the two `NOT CHECKED` names that may be the machine's fault agree across source and docs |
| `openings_left_out_test.py:7` | honest files with a whole Merkle opening left out |
| `other_parameters_kits.py:8`, `other_parameters_test.py:8`, `other_parameters_worlds.sh:6` | variant configurations; honest files of one configuration are rejected under another; makes the "world" fixtures (GPU) |
| `parameter_walk.py:8` | stress test against a hostile `policy.txt` |
| `plan_tau_test.py:8` | a `tau` that differs from the plan's number is rejected |
| `proof_fields_sweep_test.py:9` | honest proof with one leading field altered is rejected |
| `record_altered_sets_test.py:7` | altered public files and proofs under a commitment are refused |
| `served_form_test.py:8` | condition by condition, inputs not in the standard parameter form are reported |
| `walker_on_a_world_test.py:7` | runs the format document's walker (`read_proof.py`) on a `cp_prove` proof |
| `what_a_yes_covers_test.py:7` | prints what a YES is about; `NOT-A-VERIFICATION` without `-id`, with a misfit `-next-token`, or with `-no-proof-of-work` where work is needed |
| `clang_build_test.sh:7` | second build with clang++ and comparison with the g++ build |
| `compiler_pass_control.sh:7`, `compiler_pass_control.cpp:4` | reproduces the g++ 13.3.0 ipa-modref miscompilation that motivates `-fno-ipa-modref` |
| `hc_parts_test.sh:7` | builds and runs one `hc_*_test.cpp` |
| `sanitized_walk_test.sh:7` | builds with ASan/UBSan from unchanged sources and runs hostile files |
| `cp_configured_test.cpp:6` | tests `cp_with_configured` from a program linking the verifier's code |
| `field_setting_test.cpp:6` | verifier's field arithmetic vs plain division by p, in F_p (p = 2^64 − 2^32 + 1) and E = F_p[x]/(x^3 − 2) |
| `first_queries_tool.cpp:6` | writes the parameter bytes of the first queries of a proof's three hash chains |
| `forest_lookup_check.cpp:6`, `psc_layer_check.cpp:6` | verifier's side of the lookup argument / product layers on values a GPU prover sent |
| `forest_twin_test.cpp:6` | verifier's lookup vs the library's lookup argument run as prover |
| `hc_forest_attention_test.cpp:6` | unit test of the attention sub-proof's lookup-forest shape |
| `link_door_test.cpp:6`, `req_chain_test.cpp:6` | the check of a request's proof outside the sub-proofs (`vf_request_chain.h`) |
| `merge_twin_test.cpp:6` | verifier's merge vs a prover built from the library |
| `one_chain_shell_test.cpp:6` | `vf_transcript_calls.h` on the verifier's channel of a hash chain |
| `pending_row_test.cpp:6`, `weights_twin_test.cpp:6`, `ws_build_fuzz.cpp:6` | claims on the weight matrix: pending claim, coefficients, layout fuzz |
| `plan_record_test.cpp:6` | the text record by which a stage passes its accounting to the parent |
| `psc_twin_test.cpp:6`, `sumchecks_twin_test.cpp:6` | verifier's product-tree layers and sumchecks on proofs from the library |
| `tail_twin_test.cpp:6` | the approximate range check ("smallness test") claim by claim against a CPU prover written in the test; no `SUITE.md` row runs it (`verifier/README.md:296-299`) |
| `claims_report.h:6`, `coefficient_vectors.h:6`, `flat_known.h:6` | test-only helpers |
| `forest_values.txt:1`, `forest_weights.txt:1` | 275 and 473 stored lines generated by `known_answers/forest_values.py` |
| `hash_vectors.txt:1` | 57 stored lines: 44 `H <number> <L> <state>` and 13 `TH <L> <digest>` |
| `known_answers/blake2b_f.py:5` | BLAKE2b's compression function F in Python with a self-test against RFC 7693 and `hashlib` |
| `known_answers/format_hash.py:5` | the hash functions C, H, TH of `verifier/HASHES.md` in Python; checks `hash_vectors.txt` |
| `known_answers/forest_values.py:7` | expected lookup-forest shapes and weights |
| `known_answers/hiding_coins.py:7` | a Python generator of the prover's private random values (not needed by a verifier) |
| `known_answers/kit_rounds/*.txt` | 392 + 434 + 393 stored `round:` lines for `pinned_no_proof_of_work`, `target_full_f2`, `target_small_f2` |

### 3.4 `tests/`

- `dangerous_calls_test.py`, `folder_look_copies_test.py`: repository hygiene, not the verifier (`tests/README.md:34-35`).
- `s8_model.py`, `s8_known_answers.tsv`: a Python model of two hash rules **that the proof files' format does not use** (`tests/README.md:36`). Not relevant to a verifier of the format.
- `new/run_new.py`: runner of the shared library's own tests (`tests/README.md:37`).
- `new/second/`: **second verifiers in plain Python** of the library's toy files (`toy_check.py`, `links_check.py`, `key_check.py`, `lin_check.py`, `zkpy.py`, `entry_check.py`, `proof_check.py`), using only the standard library and `format_rules.py`, written from `docs/format/toys/` (`tests/new/second/README.md:3-13`). They verify toy files, not `cp_prove` proofs; `proof_check.py` is the least independent of the C++ sources (`:3`). One command builds the tools and has every file judged by both: `bash tests/new/second/run_honest.sh "$D/work" 4`, about eight minutes at one job (`:19-23`). Not run here.

### 3.5 Sources of golden intermediate values

1. **Planning calls of `cp_verify`** (check nothing, status 4, last line `PLAN ONLY: no proof was checked`; `verifier/docs/plan-data.md:3`). Lines are "made for programs": one line, one fact, the kind as first word (`:5`). `-plan request … -fields` prints `field: <file> at|at-most <place> <bytes> <class>: <name>` for every field of every file; classes `words`, `elements` (refused unless every coordinate is below p), `digest`, `salt`, `nonce`; a place is exact up to the first answer to a draw of positions, from there on `at-most` (`verifier/docs/plan-data.md:30`). Measured on `accepted-proof`: 11,398 `field:` lines (key 3,429 exact + 154 at-most; entry 8 + 35; proof 1,575 + 6,197), 955 KB; `-shapes` gives 393 `round:` lines, 33 `group:`, 5 `link <n>:` (sub-proofs G0, A0, G1, A1, H), `table:`, `length:`, `footing:`; `-plan id` gives `h_par=` and `commitment ID:`; `-plan arrays` gives 45 `array:` lines. Full-size `-fields`: 64,599 lines, 5.5 MB, 1.45 s.
2. **Whole-call output without `-q`, and `-show-stages`** (prints the stages' output even after a rejection: usage text). Stage blocks carry `plan-sums:`, `plan-rests:`, `plan-near:`, `plan-round:`, `seal <digest>`, `result: word=… dj=…`. The stage accounting record is a defined text format (`verifier/tests/plan_record_test.cpp:6-8`).
3. **`verifier/tests/first_queries_tool.cpp`**: writes `<stem>.first.parameters`, `shared.parameters`, `second.parameters`, the parameter bytes of the first queries of the three Fiat–Shamir chains, from the configuration alone (`:6-13`). Build: `cp_verify.cpp` with `-DCP_VERIFY_AS_A_UNIT` into `unit.o`, then the tool (`:14-16`; `SUITE.md:107`).
4. **`docs/format/read_proof.py`** with `--public`, `--table`, `--statement`: walks a `cp_prove` proof by the format rules: re-encodes the three chains' statements, forms every first value, makes every round's query, tests every proof-of-work nonce, samples, climbs the binding tree, asks that no byte is left (`docs/format/read_proof.py:28-35`). It is **not a verifier**: none of the protocol's content checks; it derives no plan and takes the chains' parameter bytes from item 3's files (`:37-40`). Upstream ran it only on toy files, small `cp_prove` proofs, and once on `examples/full-size` by report (`:53-58`). `read_key.py` and `read_entry.py` read toy files only, not a `key.bin` or leaf file of `cp_commit` (`docs/format/README.md:34`; `docs/format/read_key.py:35`). The exact invocation for a real proof is in `verifier/tests/walker_on_a_world_test.py:59-90`.
5. **`docs/format/format_rules.py` + `format-vectors.txt`**: rules R1.x–R8.x and R12.x–R15.x as a Python program using only the standard library and importing nothing of the programs; `format-vectors.txt` (227 lines) is its output (`docs/format/format_rules.py:7-19`). It lacks sizes and plans (section 8), sub-proofs (section 11) and the verifier's content tests (section 13); the R15.x functions were written from the programs' source, not from the rules (`:21-23`). Check: `python3 docs/format/format_rules.py | diff - docs/format/format-vectors.txt` (`:11`).
6. **`verifier/tests/hash_vectors.txt` + `known_answers/format_hash.py`, `blake2b_f.py`**: hash-level vectors (section 3.3).
7. **`verifier/tests/known_answers/kit_rounds/*.txt`**: stored planner `round:` lines; no second computation (`verifier/tests/kit_rounds_test.py:20-21`).
8. **`verifier/tests/forest_values.txt`, `forest_weights.txt`**: lookup-forest shapes and coefficient values.
9. **Toy level**: `docs/format/toys/*.md` (worked runs with bytes), `tests/new/second/*.py`, `examples/protocol-toy-false-files/` (section 1.6).

Measured in Part B: items 1, 3, 4, 5, 7 and the BLAKE2b self-test run on macOS; the walker reads all of `accepted-proof`, `accepted-proof-clipped-gap` and `full-size` proofs whole.

Two design facts that bear on any reimplementation:

- Parameter derivation is exact integer arithmetic (`Big`, `Real`, `Bound`): "Only integer operations are used, so all machines get the same results; functions returning double are for printed figures only" (`blocks/numbers/real.h:6-22`).
- The four public tables (SiLU, sigmoid, rotary, softmax-exp) are computed with the platform's floating-point library (`verifier/src/cp_verify.cpp:183`, `:202`, `:1598`; `verifier/src/vf_attention_shape.h:204-206`) and compared with digests in `policy.txt` (lines `tsilu0..7`, `tsig0..7`, `trope0..7`, `texp0..7`); a library that rounds differently turns an honest proof into `NO: table-digest-<name>` (`verifier/README.md:306-309`; `verifier/docs/output.md:345`; `docs/format/FORMAT.md:2166`, `:2177`, `:2193`).

## 4. `docs/faults.md` and `docs/known-errors.md`

**`docs/faults.md` is not a catalogue of faults tried against the verifier.** It is the operator's runbook for when `cp_commit` or `cp_prove` rejects, fails, crashes or hangs (`docs/faults.md:1-8`). Its verifier-relevant content:

- An operator's own `cp_verify` check that ends `NO:`, `NOT-A-VERIFICATION`, or gives no answer twice puts the service on hold; first rule out the caller's mistakes: wrong policy → `NO: policy`, mistyped ID → `NO: model-statement`, missing `-id` → `NOT-A-VERIFICATION`, as does `-no-proof-of-work` where a round needs its work (`docs/faults.md:25-30`).
- A response that `cp_verify` rejects can contain unmasked hidden values (`docs/faults.md:53-54`).

Where the tried fault classes are actually documented:

- Byte-level alterations of honest files: section 2 above, and the "Refusals of altered, malformed and extreme files" rows (`SUITE.md:177-181`).
- Cheating programs: none of it is repeatable from the repository. No suite row gives `cp_verify` a proof made by a cheating program (`SUITE.md:181`); the repository stores no such files for `cp_verify` (`examples/README.md:28-31`). By report, 57 lying proofs were tried at full size (24 for a false claim, 33 carrying a planted lie), none accepted by either verifier, on one commitment, exact match, with the test programs not in the repository (`guide/known-limits.md:135-153`). `cp_verify` has not been reviewed independently (`docs/limits-all-rows.tsv:737`, row E28); there has been no independent security audit (`guide/known-limits.md:131-132`).
- Parameter space: `cp_verify` accepts a wider range of parameters than upstream's tools produce, and that range is untested (`verifier/README.md:293-295`). No honest file made with counted proof of work under a changed setting has been shown to it (`docs/limits-all-rows.tsv:551`, row E11).

**`docs/known-errors.md`**: 21 entries of wrong *wording* (pages, comments, messages); "No entry is a known way to make a verifier accept a false claim" (`docs/known-errors.md:3-5`). The list is declared incomplete (`:237-239`). Entries a new verifier's author should know:

- Entry 1 (`:17-25`): "the bound within a third of the distance" in `cp_verify`'s output is a name; at the default setting no round rests on it. The Lean hand-translation `verify-on-bytes` prints "the proved lemma" instead, so the `commitment:` line differs between the two programs.
- Entry 5 (`:57-65`): `cp_verify` prints under `h_par=` the same digest as under `configuration=`, word by word instead of byte by byte; Lean's `hPar` is a different digest. No verifier compares the printed `h_par=` with anything. Measured: `h_par=0adb76ee…` and `configuration=ee76db0a…` for `accepted-proof`.
- Entries 12–14 (`:131-160`) are tests that fail through a fault of the test; entry 14: `integrations.unit` fails where the pytest plugin ddtrace is installed.

Things `cp_verify` does not check or cap (from its own README and the client page):

- It limits neither running time nor memory; set limits yourself (`docs/verifying.md:181-194`). It reads `key.bin`, the leaf file and the proof in full before checking lengths, so an oversized file can end in exit 5 or a kill (`verifier/README.md:300-302`).
- It does not know end tokens; a reply cut short verifies as a shorter reply (`docs/verifying.md:274-278`).
- It accepts the tokens before the checked range exactly as the request file gives them (`docs/verifying.md:222-227`).
- No verifier checks weight hiding (`verifier/README.md:260-263`); the output says `weight hiding: NOT CHECKED BY THIS CALL`.
- It admits `sh` 7 as well as 8; no theorem or written argument covers 7 (`docs/verifying.md:243-244`, `:353-354`).
- Counted proof of work changes neither verdict nor exit code unless `-no-proof-of-work` is passed (`docs/verifying.md:245-249`).
- The range check's own code is only partly tested (`verifier/README.md:296-299`).
- Hardening covers `std::vector`/`std::string` indices, not plain pointers and C arrays, which the sources use in many places (`verifier/README.md:65-75`).

Exit codes and last lines (`docs/verifying.md:323-332`; usage text of the built binary): 0 `YES` or `WITHIN LIMITS: clipped-gap C=… theta=… cap=… s=… sh=…`; 1 `NO: <name>`; 14 `NOT-A-VERIFICATION`; 5 `NOT CHECKED: <name>` (neither acceptance nor rejection; a malicious provider may be able to turn a `NO` into it); 2 bad command line or `input-unreadable-<role>:`; 3 `PART PASSED: key|leaf`; 4 `PLAN ONLY`; 15 no last line. All rejection names: `verifier/src/vf_rejection_names.txt` (304 lines, several are prefixes ending in `-`); explained in `verifier/docs/output.md:331` and `docs/format/FORMAT.md` section 13.8 (`SUITE.md:179`).

## 5. Measured verification cost (upstream figures)

| what | figure | source |
|---|---|---|
| small example call | "under two seconds" (one call in each of three runs, 24 CPUs of a shared host; not on the released programs) | `examples/accepted-proof/README.md:17` |
| full-size, one thread, prover's machine | about 21 s; 21.14 s mean of 3 (public 4-bit files, next token); 20.99 s (synthetic) | `guide/performance.md:23`; `docs/figures.tsv:83`, `:116` |
| full-size, 8 threads / 24 threads | 16.84 s / 17.07 s | `docs/figures.tsv:115`, `:84` |
| stored full-size example, shared VM with 24 vCPUs | 36.2–44.0 s in 8 calls; a second set 43.5–66.2 s | `docs/figures.tsv:85`; `examples/full-size/README.md:7` |
| full-size clipped-gap example | about 21 s in one call, files in cache | `examples/full-size-clipped-gap/README.md:7` |
| memory | up to 3.53 GB in the largest process (24 threads); ~3,400 MiB sampled sum over the call's processes; "have at least 4 GiB free" | `guide/performance.md:23`, `:51`; `examples/full-size/README.md:7` |
| limits tried | accepted under 8 GiB address space per process and 600 s; with 2 GiB → `NOT CHECKED: internal-stage`, exit 5; with 5 s → exit 124 | `docs/verifying.md:187-194` |
| batch of 24 via the middleware, six checks at once, one thread each | 94.0 s; one proof alone 22.6 s | `guide/performance.md:15` |
| Lean verifier, same stored proof | about 24 min (1,393–1,440 s), up to 14.13 GB | `guide/performance.md:23`; `docs/figures.tsv:117` |
| build | g++ 13, "about two minutes and 1.6 GB of memory" | `verifier/build.sh:7-8` |

Threads and structure: one call runs three stages (key, leaf, request), each in a child process on the same bytes (`verifier/src/cp_verify.cpp:12-17`). `-j N` (1..256, default 1) sets the request stage's threads; the two shorter stages run at the same time with an eighth as many each, at least one (`verifier/README.md:114-115`). All three stages are in memory at once (`verifier/README.md:306-307`). Upstream gives no finer breakdown than the per-stage seconds the program prints. My own measurements are in Part B.

## 6. `integrations/check_proof.py`

It runs `cp_verify` and makes the comparisons that tie the answer to the caller's own values (`integrations/check_proof.py:5-13`; `docs/verifying.md:336-354`):

- Inputs the caller states: `--commitment-id`, `--public-key-dir`, `--parameter-file`, `--scales-file`, a range (`--range START:END` or `--reply PROMPT_LEN:REPLY_LEN`), `--end-token IDS|none`, policy options (`integrations/check_proof.py:832-835`, `:994`).
- It checks the files against the caller's ID first, runs `cp_verify` in a private temporary directory, and compares the **whole `result-v1` line** against a pattern built from the caller's values, the request and the parameter file (`:123-134`): `status`, `claim`, `id`, `bits=128`, `work`, `work-rounds`, `least-round…`, `commitment-assumed-rounds`, `record=1`, `r`, `e`, `T`, `tokens`, `y`, `policy`, `C`, `theta`, `cap`, `s`, `sh`, `sT`, `F`, `above-clip`, `leaf` (against the proof's header), `stages=key,leaf,request`, `dw=8`, `build=` (form only).
- The two lines before `result-v1` must be the `commitment:` line (at least one round, ending with `; the table has a record: …`) and the `proof of work:` line; the parameter file must say `record 1` (`:136-151`).
- End of reply: the last checked token must be one of the caller's end tokens and no earlier checked token may be one (`:1192-1198`). `cp_verify` knows no end tokens.
- Differences from `cp_verify`: under clipped gap `--C` and `--s` must equal the file's values but `--theta` and `--cap` are upper limits; it accepts only `sh` 8, `sT` 4, `F` 24 (`docs/verifying.md:350-354`). It cannot compare the tokens before the range (`docs/verifying.md:343-344`).
- Exit codes 0 (`outcome=verified` or `within-limits`), 1 rejected, 2 error, 14 not a verification (`integrations/check_proof.py:67-70`, `:838-845`).

The client's full acceptance rule is eight points (`docs/verifying.md:214-278`): own verifier, own files, own ID, verdict (exit 0 and last line exactly `YES` or beginning `WITHIN LIMITS: clipped-gap`), the `covered:` line matches, proof-of-work decision, the `commitment:` line's words, end of reply.

## 7. Licensing facts for redistributing examples or derived vectors

- The repository is Apache-2.0: `LICENSE:1-3`; "Apache 2.0: see LICENSE. Material from other projects keeps its own licence" (`README.md:208-213`). Source and script files carry `Copyright 2026 Anthropic PBC` and `SPDX-License-Identifier: Apache-2.0` (e.g. `examples/rejected-proofs/try_altered_copies.py:2-3`).
- `NOTICE:1-4`: "FlashProve / Copyright 2026 Anthropic PBC / This product includes software developed at Anthropic PBC", followed by third-party notices. Apache-2.0 section 4(d) requires a redistribution to carry the attribution notices of `NOTICE` that pertain to the part redistributed **[inference: standard reading of the licence, not a statement of upstream's]**.
- The stored proofs, key files and leaf files are on synthetic weights; no weight file of Meta's was used (`examples/README.md:6-8`; `examples/full-size/README.md:3`). Meta's own files and third-party weight files are fetched by the user and are not in the repository (`THIRD_PARTY.md:167`).
- Constants in the stored `config/` files "may depend on" or were "computed from" Llama 2 7B / Llama 4 Maverick: `s 15`, `eps*_lo`, the full-size `KL.bin` and `layout.txt`, `sh 8`/`sT 4`, `MF`/`KF`, the rotary base, the model's shape numbers, the `rp` flags, the small configurations' `KL.bin` and `layout.txt`, `S 12`/`rx 8` and the `texp*` digest lines, and the SHA-256 digests in the examples' `SHA256SUMS` (`THIRD_PARTY.md:184-189`, `:201-233`, `:268`). Upstream lists the dependence; it states no extra licence term for these numbers. Llama 4 Maverick itself is under the Llama 4 Community License Agreement (`THIRD_PARTY.md:158-162`).
- If the verifier sources are vendored (to build the oracle), the third-party entries that list `verifier/` or `blocks/` files apply: the paper the protocol builds on (`THIRD_PARTY.md:5-12`), the BLAKE2 reference package, taken under CC0-1.0 (`THIRD_PARTY.md:293-303`), ChaCha20 sources, SplitMix64, plonky2/Plonky3 field arithmetic (`THIRD_PARTY.md:330`, `:402`, `:442-458`). `docs/format/format_rules.py` adapts BLAKE2 reference code too (`THIRD_PARTY.md:296`).
- Contributor rule relevant to an oracle: "Never edit a source file to change a result" (`AGENTS.md:98`).

Practical size: `examples/` is 66 MB, of which the two full-size sets are about 25 MB each.

---

# Part B — can the oracle be built on this Mac without Docker?

## Verdict

**Native macOS build works, but not via `verifier/build.sh`.** The script refuses (exit 2). A direct compile of the one translation unit with `/usr/bin/clang++`, using the script's `--clang` flag set with only the three ELF linker options removed, succeeds with **no source edit and no shim**. A variant with one extra `-D` (libc++ hardening) restores the bounds-check behaviour that `-D_GLIBCXX_ASSERTIONS` gives on Linux. Both variants give identical output on everything I ran.

## Environment

macOS Darwin 25.6.0 arm64; Apple clang 21.0.0 (clang-2100.1.1.101); `/usr/bin/g++` is the same clang; `/bin/bash` 3.2.57; Python 3.15.2; `/sbin/sha256sum` present; Homebrew coreutils 9.12 already installed (`/opt/homebrew/opt/coreutils/libexec/gnubin`); no GNU findutils; no GNU g++; no Docker. Nothing was installed.

## Private copy

`<scratchpad>/oracle-build/FlashProve/` holds: all top-level files, `verifier/`, `blocks/`, `examples/`, and the four prover headers the build reads (`prover/{attn,head,prover}/plan_rounds.h`, `prover/hiding/token_plan.h`: `verifier/build.sh:311`, `-I../../prover` at `:352`). Added later for the Python tools and one test: `docs/format/`, `prover/examples/`, `prover/tests/configurations/`. `diff -rq` against upstream: identical. Upstream `git status`: clean after all work.

## What the build is

One compiler call on `verifier/src/cp_verify.cpp` from `verifier/src` (`verifier/build.sh:309`, `:351-353`):

```
g++ -O2 -fno-ipa-modref                         # default (build.sh:328)
clang++ -O2                                     # with --clang (build.sh:329)
-D_GLIBCXX_ASSERTIONS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fstack-protector-strong -fstack-clash-protection
-ftrivial-auto-var-init=zero -fPIE -pie -Wl,-z,relro,-z,now,-z,noexecstack      # build.sh:348-349
[-fcf-protection=full on x86_64]                                               # build.sh:350
-std=c++17 -Wall -Wextra -Wuninitialized -Werror=unused-result -Wno-misleading-indentation -pthread
-I. -I../../blocks -I../../prover -DBLK_FIELD=2 -DBLK_COUNT_HASH_CALLS=1 -DSERVING_BUILD=1 -DDIGEST_WORDS=8
-DVF_SOURCE_DIGEST="\"$build_word\"" -o "$work/cp_verify" cp_verify.cpp
```

`build_word` is the SHA-256 of `sha256sum`'s output over `verifier/src/*`, the four prover headers and every non-test `*.h` under `blocks/`, under `LC_ALL=C` (`verifier/build.sh:310-311`). Upstream notes: only clang 18.1.3 has been tried with `--clang`; figures and test runs use the g++ build (`verifier/build.sh:26-29`). `-fno-ipa-modref` works around a g++ 13.3.0 bug; clang has neither the pass nor the flag (`:324-327`).

## Log

Commands were run from the copy's top directory unless stated. `$O` is `…/scratchpad/oracle-build/out`.

**Step 0 — digest of the copied sources.** The `build.sh:311` pipeline, run by hand with `/sbin/sha256sum`, `/usr/bin/find`, `sort`, `xargs` (36 files in `verifier/src`, 94 headers in `blocks/`):

```
build=93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595 dw=8
```

Equal to the documented value (`examples/README.md:36`).

**Step 1 — `verifier/build.sh` as-is.**

```
$ verifier/build.sh
build.sh: nothing was built: the output directory …/oracle-build/FlashProve/bin cannot be used: /: it could not be examined: name a directory of your own below directories that only you or root can change (such as one in your home directory): end the call with "- DIRECTORY"
exit=2
```

Cause: `LC_ALL=C stat -c '%u %a %F' -- "$here"` (`verifier/build.sh:87`); BSD `stat` answers `stat: illegal option -- c`. Side effect: an empty `bin/` (created at `:179`).

**Step 1b — same script, GNU coreutils first on `PATH`** (environment only; nothing installed, nothing edited):

```
$ PATH=/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH verifier/build.sh
build.sh: nothing was built: the output directory …/bin holds something that belongs to another account, or a directory that its group or others can write in, or could not be searched: name a new directory: end the call with "- DIRECTORY"
exit=2
```

Cause: `find "$out" -ignore_readdir_race -mindepth 1 \( … -type d -perm /022 \) -print -quit` (`verifier/build.sh:223`); macOS `/usr/bin/find` answers `find: -perm: /022: illegal mode string`. GNU findutils is not installed. `verifier/build.sh --clang - <dir>` with the same `PATH` fails the same way (exit 2).

Further blockers past that point, by direct probes: `readlink -z` (`:105`) and `mv -fT` (`:360`) are GNU-only (covered by the coreutils `PATH`); the default compiler line fails on Apple clang:

```
$ echo 'int main(){}' | /usr/bin/g++ -O2 -fno-ipa-modref -x c++ -fsyntax-only -
clang++: error: unknown argument: '-fno-ipa-modref'
```

**Step 2a — direct compile, the exact `--clang` command line, nothing adapted.** Compiles; only the link fails:

```
clang++: warning: argument unused during compilation: '-fstack-clash-protection' [-Wunused-command-line-argument]
clang++: warning: argument unused during compilation: '-pie' [-Wunused-command-line-argument]
ld: unknown options: -z -z -z
clang++: error: linker command failed with exit code 1 (use -v to see invocation)
exit=1   (20.46 s)
```

No source-level error or warning: no x86 intrinsics, no missing Linux header, no GNU extension that Apple clang rejects, no libstdc++-only feature. The one Linux-only call, `prctl(PR_SET_DUMPABLE, 0)`, is already guarded by `#ifdef __linux__` (`verifier/src/cp_verify.cpp:49-51`, `:3420-3424`). `blocks/coins/coins.h:95` calls `::getrandom`, which macOS lacks, but the verifier's translation unit does not reach it (the compile succeeds).

**Step 2b — minimal adaptation: drop `-Wl,-z,relro,-z,now,-z,noexecstack`.**

```sh
cd verifier/src && export LC_ALL=C
bw=93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595   # computed as in step 0
/usr/bin/clang++ -O2 -D_GLIBCXX_ASSERTIONS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fstack-protector-strong \
  -fstack-clash-protection -ftrivial-auto-var-init=zero -fPIE -pie -std=c++17 -Wall -Wextra -Wuninitialized \
  -Werror=unused-result -Wno-misleading-indentation -pthread -I. -I../../blocks -I../../prover -DBLK_FIELD=2 \
  -DBLK_COUNT_HASH_CALLS=1 -DSERVING_BUILD=1 -DDIGEST_WORDS=8 "-DVF_SOURCE_DIGEST=\"$bw\"" \
  -o "$O/cp_verify.2b" cp_verify.cpp
```

Result: exit 0; the same two "argument unused" warnings and nothing else; 19.24 s real; 1.22 GB peak RSS; `Mach-O 64-bit executable arm64`, 2,436,992 bytes.

**Step 2c — 2b plus `-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE`.** Exit 0, 19.80 s, 2,470,912 bytes. Reason: `-D_GLIBCXX_ASSERTIONS` is a libstdc++ macro and does nothing under Apple's libc++. Probe: a three-element `std::vector` indexed at 6 runs on and exits 0 with only `-D_GLIBCXX_ASSERTIONS`, and dies with SIGTRAP (exit 133) with the libc++ macro. Upstream relies on that behaviour: an out-of-range `v[i]` kills the stage with a signal and the stage counts as not passed (`verifier/build.sh:330-335`; `verifier/README.md:65-67`). This is a compiler-flag change from outside the tree, not a source change. Choosing EXTENSIVE over FAST as the nearer analogue is **[inference]**.

## Results with the built binary

**The four stored sets, exact documented commands** (2b installed as `bin/cp_verify`):

| set | exit | last line | wall (`/usr/bin/time -l`) | max RSS | stage seconds printed (key / leaf / request) |
|---|---|---|---|---|---|
| `accepted-proof` | 0 | `YES` | 0.63–0.65 s (3 runs; very first run 0.89 s) | 196–201 MiB | 0.29 / 0.27 / 0.63–0.65 |
| `accepted-proof-clipped-gap` | 0 | `WITHIN LIMITS: clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8` | 0.63–0.65 s | 191–195 MiB | 0.29 / 0.27 / 0.62–0.65 |
| `full-size` | 0 | `YES` | 7.93–8.11 s (3 runs) | 3,730–3,985 MiB | 0.89–0.95 / 0.73–0.77 / 7.9–8.1 |
| `full-size-clipped-gap` | 0 | `WITHIN LIMITS: clipped-gap C=25856 theta=512 cap=1 s=15 sh=8` | 7.90–8.04 s | 3,780–3,968 MiB | 0.90 / 0.73–0.74 / 7.9–8.0 |

- The last four lines of each call equal the README text character for character, with `build=93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595` where the READMEs print `<64 hex digits>`.
- stdout: 105 lines with `-q` for all four; without `-q` 136 lines (small) and 216 (full). stderr: empty.
- Threads: `full-size -q -j 8` 6.45 s; `-j 16` 6.41 s (stage header then reads `request ---- 16 thread(s)`, key and leaf `2 thread(s)`); stdout identical to the default run apart from the stage headers. User CPU 9.3–10.3 s. The request stage dominates and is mostly serial here.
- "max RSS" is `/usr/bin/time -l`'s "maximum resident set size". **[inference]** That is the largest single process of the call's tree, not the sum of the three stages.
- 2b vs 2c: stdout identical on all four sets after removing the seconds in the three `---- stage … ----` headers.
- SHA-256 of that normalised `-q` stdout (`sed -E 's/, [0-9]+\.[0-9]+ s$//'`), candidates for goldens once a Linux g++ build confirms them:

```
5283c1221fe3e16d890b0c648835a068c4dab82b2ccd7f2615599cf31a9c1918  accepted-proof
d85a899f62ebd3ae53c40ad6e3999375f17ad84a63227f7a299cf678add4c5a9  accepted-proof-clipped-gap
a8ea7ee44f324629cd7e49cebc242a33768459ff760a2d9d988cc06a6533732a  full-size
b52439221bc3560aae41f04dcf227a15ef40aa1a3177a569379f42815b33cb75  full-size-clipped-gap
```

**Upstream's altered sets** (`python3 -I -B examples/rejected-proofs/try_altered_copies.py …`):

| run | result | wall |
|---|---|---|
| default table, `accepted-proof` | screen output equal to `examples/rejected-proofs/README.md:20-36` (apart from the directory line); `10 altered sets: all rejected` | 5.7 s |
| `--example accepted-proof-clipped-gap` | first line `WITHIN LIMITS: clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8`; `10 altered sets: all rejected` | 5.3 s |
| `every_kind_of_item.tsv`, binary 2b | `79 altered sets: all rejected`, script exit 0 | 43 s |
| `every_kind_of_item.tsv`, binary 2c | identical log, script exit 0 | 43 s |

Every row was rejected with exit code 1 under exactly the name the table expects. No row produced `NOT CHECKED` or a signal on either binary.

**Other upstream checks run against the macOS binary.**

- `verifier/tests/kit_rounds_test.py`: `kit_rounds_test.py: 3 kits, 1219 kinds of rounds; 0 kits not as stored` on 2b and 2c. The stored lines were printed by upstream's `cp_verify` (`verifier/tests/kit_rounds_test.py:20`), so this is agreement with the reference build on 1,219 planner lines, including the two-decimal error figures.
- `verifier/tests/record_altered_sets_test.py` on `accepted-proof`: `7 calls on the honest set and its unaltered copy, 23 altered sets: all as expected` (the line `SUITE.md:226` asks for).
- `verifier/tests/commitment_id_test.py` on all four examples: `all as expected`; the Python-formed ID equals `cp_verify`'s and each `ID.txt`.
- `-plan accounting <kit> 128` on all eight complete configurations under `prover/examples/` and `prover/tests/configurations/`: each prints `plan: this program's four public tables match the parameter file's digests`; `target_small_file_f2` (no `layout.txt`) ends `NO: plan-layout`, as documented (`docs/format/README.md:38-40`). So macOS's math library reproduces the four floating-point tables at every shipped configuration.
- `docs/format/format_rules.py | cmp - docs/format/format-vectors.txt`: identical (227 lines). `verifier/tests/known_answers/blake2b_f.py`: `all as expected`.
- `first_queries_tool` (built with clang++ from `unit.o`; the `SUITE.md:107` command with `g++ -fno-ipa-modref` replaced by `/usr/bin/clang++`; 18 s + 2 s) plus `read_proof.py`, invoked as in `walker_on_a_world_test.py:85-86`:

| proof | `example.first.parameters` / `shared` / `second` (bytes) | walker | wall |
|---|---|---|---|
| `accepted-proof` | 897,712 / 5,926 / 1,839 | exit 0, `the whole file is read: 4145300 bytes`, 28 lines | 0.76 s |
| `accepted-proof-clipped-gap` | 897,712 / 5,926 / 1,839 | exit 0, `… 4151892 bytes` | 0.76 s |
| `full-size` | 5,462,480 / 8,989 / 3,309 | exit 0, `… 18779540 bytes`, 54 lines | 15 s |

  The walker's print lists, per sampling round, the number of draws, the domain, and each opened tree's depth, width, column count and byte range, plus the slot and the binding tree's root (small proof: first chain 8,037 rounds, shared chain 42, second chain 16; slot 28 of 2^6).
- Unit tests compiled with clang++ from the `SUITE.md:165` and `:225` commands (minus `-fno-ipa-modref`): `field_setting_test, setting 2: all passed`; `psc_twin_test: ok (trees of 2 to 32 leaves; 115 changed scalars and as many changed mask entries noticed)`. Both are the lines the suite asks for.

**Hand-made mutations on `accepted-proof`** (all with `-q`; stdout is three lines on a rejection; stderr empty):

| change | exit | stdout |
|---|---|---|
| proof byte 2,072,650 XOR 0xFF | 1 | `---- the call ----` / `refused by the stage request: an opening does not lead to its root` / `NO: proof-refused` |
| `-id` with the last digit `3` → `0` | 1 | `id: these are not the files of the commitment that you named; nothing in them was checked` / `id: take the commitment ID from your own record of where it was published, never from these files` / `NO: model-statement` (0.26 s: fails before the proof is looked at) |
| token file holding 200 instead of 199 | 1 | `---- the call ----` / `refused by the stage request: the proof is about another reply` / `NO: reply-differs` |
| the clipped-gap example's `example.req` | 1 | `---- the call ----` / `refused by the stage request` / `NO: statement-range` (**[inference]** that request has e < T, so y = 199 breaks "y must be 0") |
| same flipped proof with `-show-stages` | 1 | 67 lines: the three stage blocks, then the same three closing lines |

**Other statuses exercised.**

| call | exit | last line |
|---|---|---|
| no `-id` | 14 | `NOT-A-VERIFICATION`; `result-v1 status=14 … id=not-shown-without-id` |
| `-bits 100`; `-no-proof-of-work` | 14 | `NOT-A-VERIFICATION` |
| clipped-gap example without `-policy` | 1 | `policy: the request covers more than the output token, the parameter file sets another policy than exact-match, and the call has no -policy` / `NO: policy` |
| missing proof file | 2 | `input-unreadable-proof: the proof file cannot be read: No such file or directory` |
| `-key <config> <key.bin> -id …`; `-leaf <config> <key.bin> <leaf> -id …` | 3 | `PART PASSED: key`; `PARTPASSED`-style `PART PASSED: leaf` |
| any `-plan …` | 4 | `PLAN ONLY: no proof was checked` |
| no arguments | 2 | 98 usage lines on stderr, the last naming what was not accepted |

(The leaf part-call's last line is exactly `PART PASSED: leaf`.)

## Recipe

```sh
# In a checkout at commit 9e2bdd8; OUT is a directory outside the checkout.
cd verifier/src && export LC_ALL=C
bw=$({ sha256sum * ../../prover/*/plan_rounds.h ../../prover/hiding/token_plan.h
       cd ../../blocks && find . -type f -name '*.h' ! -path '*/tests/*' | sort | xargs sha256sum
     } | sha256sum | cut -c1-64)
[ "$bw" = 93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595 ] || { echo "sources differ"; exit 1; }
/usr/bin/clang++ -O2 -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE \
  -D_GLIBCXX_ASSERTIONS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fstack-protector-strong -fstack-clash-protection \
  -ftrivial-auto-var-init=zero -fPIE -pie -std=c++17 -Wall -Wextra -Wuninitialized -Werror=unused-result \
  -Wno-misleading-indentation -pthread -I. -I../../blocks -I../../prover -DBLK_FIELD=2 -DBLK_COUNT_HASH_CALLS=1 \
  -DSERVING_BUILD=1 -DDIGEST_WORDS=8 "-DVF_SOURCE_DIGEST=\"$bw\"" -o "$OUT/cp_verify" cp_verify.cpp
```

`sha256sum` here is macOS's `/sbin/sha256sum`; `find`, `sort`, `xargs` are the BSD ones. Drop the first `-D` for the strictly minimal variant (2b). Then self-check: the four documented commands and the three `try_altered_copies.py` runs.

## What this does not establish

- No comparison with a Linux g++ build was possible here. Agreement with the reference is established only where upstream stores reference text: the four closing lines per example, the 99 expected rejection names of the three tables, the 23 of `record_altered_sets_test.py`, and the 1,219 `round:` lines.
- Apple clang 21, libc++, arm64 and macOS's math library are all outside what upstream has tried (clang 18.1.3 on Linux only: `verifier/README.md:33`).
- No input made either macOS binary end in `NOT CHECKED` or a signal, so the hardening difference between 2b and 2c was never exercised.
- Core dumps are not switched off on macOS (the `prctl` call is Linux-only). Irrelevant for public test vectors.
- Not run: `run_suite.py`, `clang_build_test.sh`, `stored_false_test.py`, `tests/new/second/run_honest.sh`, `record_altered_sets_test.py` on the full-size set, the sanitizer rows.

---

# Recommended oracle strategy

1. **Pin the oracle by commit and by build word.** Fetch upstream at `9e2bdd8` and require `build=93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595` in every `result-v1` line the harness reads. Never patch the sources (`AGENTS.md:98`).
2. **Authoritative oracle: Linux x86-64, g++ 13, unmodified `verifier/build.sh`.** Upstream's verifier build has been run on Ubuntu 24.04 x86-64 with g++ 13.3 and Python 3.12/3.13; install line `apt-get install -y --no-install-recommends g++ make python3 unzip` (`docs/quickstart.md:59-71`). In CI: build, then run the four documented example commands and `try_altered_copies.py` on both small examples and with `every_kind_of_item.tsv` as the oracle's own self-test before using it. **[inference]** a GitHub-hosted `ubuntu-24.04` runner meets this (g++ 13 by default, enough memory for the ~4 GiB full-size check); not verified here.
3. **Local oracle on macOS: the clang++ recipe above (variant 2c).** Gate it with the same self-test, and with a byte comparison of its normalised output against goldens recorded by the Linux build. On any disagreement the Linux build decides. Use it for the tight red-green loop; it answers a small proof in 0.65 s.
4. **Record goldens once, from the Linux build, and commit them** (small sets in-repo; full-size outputs as hashes or fetched by commit):
   - per example: exit code; full stdout without `-q` and with `-q`, with the three stage-header seconds stripped; the `result-v1` line parsed into fields;
   - per example: `-plan id` (ID, `h_par`), `-plan request … -fields`, `-plan request … -shapes`, `-plan accounting`, `-plan arrays`; the non-`-q` whole-call stdout already contains the per-stage `plan-*`, `seal` and `result:` lines;
   - per example: the three `*.parameters` files from `first_queries_tool` and the `read_proof.py` walker print;
   - the part-calls `-key` and `-leaf` (exit 3) and the status paths 2, 14;
   - per altered set: the mutation (file, offset, old and new bytes), exit code, the three-line `-q` stdout, and the `-show-stages` stdout for diagnosis.
5. **Negative corpus:** materialise `try_altered_copies.py`'s sets once against the oracle (10 + 10 + 79) and `record_altered_sets_test.py`'s 23; keep the tables as the source of truth and regenerate rather than hand-edit. Extend with rows of our own in the same TSV format, always labelled by the oracle, never by expectation.
6. **Compare in tiers** **[inference]**: (a) verdict class from exit code and last line (accept / within-limits / reject / not-a-verification / not-checked) must always match; (b) the rejection name must match on upstream's tables; (c) `result-v1` fields must match on accepts; (d) intermediate lines (`field:`, `round:`, commitment ID, `h_par`, walker positions) are milestone tests for the planner, the format layer and the transcript, in that order. Compare printed floating-point figures only where upstream stores them; decisions use integer arithmetic (`blocks/numbers/real.h:19-22`).
7. **Use the Python format layer as a second reference below the oracle.** `format_rules.py` and `read_proof.py` are standard-library Python, run on macOS, and read all stored proofs whole; they give hash, chain, proof-of-work, sampling and Merkle-opening behaviour with printable intermediates, independent of `cp_verify`'s content checks.
8. **Budget.** A full differential pass over both small examples with all 99 + 23 altered sets costs about one minute of oracle time on this Mac; each full-size call is ~8 s and ~4 GiB.

Limits of the corpus that the test strategy must state: four honest proofs, one request per commitment, leaf table 0 only (`-M 1`), `sh 8` only, proof of work always counted, no request with r = T − 1 (`tokens=none`, the `-next-token` case), no proof from a cheating prover in `cp_verify`'s format. New honest proofs need `cp_commit` and `cp_prove` on an H100 (`examples/accepted-proof/README.md:67`; `SUITE.md:111`); the CPU prover upstream mentions is not in the repository (`verifier/build.sh:326-327`).

# Open questions

1. Does a Linux g++ 13 build print byte-identical stdout (seconds aside) to the macOS clang build on the four examples, the planning calls and all altered sets? Untested here; it decides whether macOS-recorded goldens can be trusted at all.
2. Can CI run the oracle on a hosted `ubuntu-24.04` runner as assumed (g++ 13, ~4 GiB for full size, `build.sh`'s directory-ownership checks)? Is `run_suite.py` (Landlock) wanted there, or only hand-run row commands?
3. How should the harness treat exit 5 (`NOT CHECKED`) and a rejection under a different name than the oracle's: hard failure, or same-class equivalence? Upstream says a malicious provider may turn a `NO` into `NOT CHECKED` (`docs/verifying.md:331`).
4. The four floating-point tables: must the Bend verifier compute them (needing `exp`, `sin`, `cos` and rounding that match the reference bit for bit), or may it take them as data and check the digests in `policy.txt`? Upstream's own verifier refuses on a mismatch (`verifier/README.md:306-309`).
5. Is the full-size proof (18.8 MB, ~4 GiB and 8 s in C++) in scope for the Bend verifier's tests, or only the two small proofs?
6. Can more honest vectors be obtained (GPU access, or from upstream) for the uncovered cases: r = T − 1, leaf index ≠ 0, no counted proof of work, `sh 7`, a second request under one commitment?
7. Redistribution: is copying `examples/` (66 MB, constants that "may depend on" Llama models per `THIRD_PARTY.md:184-233`) into the new repository acceptable, or should the corpus be fetched by commit and checked with `SHA256SUMS`? Which `NOTICE` entries must travel with vendored verifier sources?
8. Which libc++ hardening mode is the right stand-in for `_GLIBCXX_ASSERTIONS`, and does any hostile input make the two macOS variants, or macOS and Linux, differ? None of the 122 altered sets did.
9. Does the Bend verifier keep `cp_verify`'s CLI and last-line contract (so upstream scripts run unchanged), or a wrapper maps to it?
