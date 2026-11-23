# 07 — The Lean verifier: structure, cost, scope, and what is reusable for a port

> Status: frozen
> Recovered working notes, 2026-11-23. Upstream excerpts from FlashProve, Copyright 2026 Anthropic PBC, Apache-2.0.

Source: FlashProve 0.16.0-rc.26, commit 9e2bdd8, read-only copy at
`<scratchpad>/upstream/FlashProve`. All paths below are relative to that root. Nothing was built or
run; `tools/lean-verify/README.md` is assumed read and is cited only for line numbers.

Evidence tags used throughout:

- **[R]** read in the cited source or doc line.
- **[M]** a measurement that upstream reports (never mine). Upstream says most of its figures were
  taken on Lean files and parser sources that differ from this repository's
  (`tools/lean-verify/README.md:302-306`).
- **[S]** a static count I made from `import` lines and file contents, with the small scripts in
  `<scratchpad>/research/_tools/` (`import_closure.py`, `struck.py`, `closure_sizes.py`,
  `closure_list.py`). Cross-checks: my count of library modules in `native-modules.txt` is 1,670 and
  my import closure of `OnBytes.Main` is 200 modules, both equal to upstream's own figures
  (`tools/lean-verify/native-modules.txt:4`; `lean/Ask/README.md:111-113`).
- **[I]** my inference. Not stated upstream, not measured.

## 0. What matters most for the spec

1. There are two different Lean verifiers in the tree, and they differ by an order of magnitude in
   speed. The proved one (`verify`, run through its "executable form" by `lean-verify`) takes 19–39
   minutes. The unproved hand translation of `cp_verify` (`verify-on-bytes`, `lean/OnBytes/`) took
   112–121 s and 5.2 GB at full size on one thread as a compiled stand-alone program, against 25 s
   for `cp_verify` in the same comparison (`lean/OnBytes/LIMITS.md:811-821`, `:870-872`) [M].
2. So the 19–39 minutes are not what a pure-functional rendition of the checks costs. They are the
   cost of executing a verifier that was *compiled inside Lean from an IOP description* for the
   purpose of a soundness proof (bit-list oracle strings, digests as functions, oracle-query trees),
   partly interpreted, behind a multi-minute external pre-pass. Section 3 gives the evidence.
3. `lean/OnBytes/` is the closest functional reference for a port: 200 modules, 48,520 lines with
   comments, no Mathlib, total functions over `ByteArray`/`UInt64`/`List`/`Array`, reading the raw
   files itself, file by file tied to named C++ sources [S][R]. It inherits no soundness theorem and
   has documented differences from `cp_verify` (section 5).
4. A new verifier inherits no theorem from either (section 6).

## 1. Structure of the executable Lean verifier

### 1.1 The names

- `verify` (`lean/Ladder.lean:416`): the verifier of the soundness theorem, a Lean term that cannot
  be executed: "`verify` as typed cannot be executed. Lean marks it noncomputable."
  (`lean/THEOREM.md:511`) [R].
- The executable form: `PV.Ride.rideThe` / `PV.Ride.verdictThe`
  (`lean/Johnson/PVR/RideThe.lean:54`, `:102-108`), tied to `verify` by theorems (section 6).
- `lean-verify`: the shell command that evaluates that form inside the `lean` program. "It is
  evaluated inside Lean; it is no built program" (`lean/GAPS.md:64`) [R].
- `verify-on-bytes` (`lean/OnBytes/`, entry `OnBytes.Main`): a different verifier, section 5.

### 1.2 The run, outermost first

`tools/lean-verify/lean_verify.sh` (313 lines) does, in order [R]:

1. Checks arguments, tools and paths; refuses any input file above 2^28 bytes (`:98-111`). Tools
   required include `prlimit`, `timeout`, `realpath`, `sha256sum`, `stat` (`:77`).
2. Copies the claim (three public files, ID, request, token file) into a fresh work directory and
   prints their SHA-256 (`:145-151`).
3. Runs `read_claim.py`, a second reader of the claim in Python; its six lines must later equal
   Lean's, byte for byte (`:156-161`, `:295-296`).
4. Compares the three public files with `examples/full-size/config` (a note only, `:162-167`) and
   reads the policy numbers; "exact match" is `(C, theta, cap, sh, sT) = (256, 256, 0, 8, 4)`
   (`:174-186`).
5. `lake build --no-build Johnson.PVR.Program Johnson.PVR.ProgramGuard`: no verdict unless the
   compiled library fits the sources (`:196-197`).
6. Runs the parser: `tools/parser/parse_files.sh config keys request proof work/parser` (`:203`),
   and insists on its last line and on exactly one parsed leaf file (`:205-209`).
7. Unless `--no-native`: has Lake make one native object per line of `native-modules.txt`
   (`+<module>:c.o.export`, `:215-237`), checks each object is newer than its `.c` and `.olean`
   (`:250-251`), and links them into `work/libnative.so` with `lake env leanc -shared`, anew at
   every call (`:254-256`).
8. Runs Lean on one file, one thread:
   `lake env lean -j1 --tstack=4000000 --load-dynlib=$work/libnative.so -D interpreter.prefer_native=true LeanVerify.lean`,
   under `prlimit --fsize=1048576`, with the seven arguments in `LEAN_VERIFY_ARGS` (`:258`,
   `:271-275`).
9. Gives a verdict only if Lean's exit status (10/11), its last line, the count of verdict lines
   and the claim lines all agree (`:293-313`).

`tools/lean-verify/LeanVerify.lean` (26 lines) is the whole Lean entry: `import Johnson.PVR.Program`
(`:19`) and one `#eval` that calls `PV.Program.run` and exits with 10, 11 or 12 (`:23-26`). It is an
`#eval` in a file that `lean` elaborates, not a `main`, because "the library's module OnBytes.Main,
which lies beneath the verifier's files, has declared that name" (`:11-13`) [R].

### 1.3 `lean/Johnson/PVR/Program.lean` (312 lines)

- `Given` (`:56-67`): eleven `ByteArray`s: three public files (`pol`, `lay`, `KL`), three user
  files (`id`, `req`, `y`), five parser outputs (`key`, `keySeeds`, `leaf`, `leafSeeds`, `proof`).
- `Claim` (`:71-75`): `commitment : Commitment`, `prompt output further : List Token`.
- `T := Inst.Model.ppref.T` (`:80`), the constant 1,024 (`lean/Inst/Model/Program.lean:122-123`).
- `callOk` (`:92-95`): tests 1–4 of FORMAT.md 12.2: request file exactly `4 * (T + 2)` bytes, token
  file 4 bytes, `r < e ≤ T`, token file 0 where `e < T`. Where one fails the command gives *no
  verdict*, "where `cp_verify` rejects" (`:87-91`).
- `claimOf : Given → Option Claim` (`:102-107`): `callOk`, then `PV.Front.idOf` (64 lower-case hex
  digits, at most a newline) and `PV.Front.userOf` (`lean/Johnson/Top/Fire/Code/PvFront.lean:46`,
  `:89`). No theorem covers these three functions (`:31-34`; `lean/GAPS.md` entry 37 per
  `lean/THEOREM.md:248-252`).
- `stepsOf g c := PV.Ride.rideThe (pubOf g) Fmt.oracle (formOf g c) c.commitment c.prompt c.output`
  (`:117-118`), of type `Except String FastSteps`.
- `verdictAt g c r := PV.Ride.verdictThe (pubOf g) Fmt.oracle (formOf g c) r` (`:121-122`).
- `verdictOf g := (claimOf g).bind fun c => verdictAt g c (stepsOf g c)` (`:125-126`): "one pure
  function of the bytes" (`:15-16`), `Given → Option Bool`.
- `verifyValue` (`:129-132`): `verify`'s value at the claim, at the hash `hashOf Fmt.oracle`;
  `noncomputable`.
- Theorems: `verdictOf_at` (`:135`), `verdictOf_is_verify` (`:142`), `verdictOf_none` (`:155`); in
  `ProgramTotal.lean`: `verdictAt_eq` (`:31-34`), `verdictOf_map : verdictOf g = (claimOf g).map
  (verifyValue g)` (`:37`), `verdictOf_eq` (`:43`). They "are theorems on Lean terms, not on code
  that runs" (`lean/Johnson/PVR/ProgramTotal.lean:5-6`).
- `PV.Program.run : List String → IO UInt32` (`:290-293`) is the IO shell: `ending` (`:254-287`)
  reads the eleven files (`readRole`, `:198-206`, limit 2^28 bytes `:195`), requires
  `LEAN_ABORT_ON_PANIC=1` (`:256-258`), prints the claim (`:269-277`), forces
  `IO.lazyPure fun _ => stepsOf g c` (`:278`), prints the twelve steps (`:281-284`) and returns
  `Ending.of (verdictAt g c r)` (`:287`). "No theorem speaks of `run`, nor of compiled or
  interpreted code" (`:34-35`).

`lean/Johnson/PVR/ProgramGuard.lean` (130 lines) holds build-time checks only: `#guard_cone`,
`#guard_has`, `#guard_ctors` over `PV.Program.run` (`:35-38`), 22 known answers of `claimOf`
(`:77-100`), and four `#print axioms` (`:103-106`). The walk covers kernel terms, "Nothing here
speaks of Lean's compiler, interpreter or runtime" (`:28`). In one build the cone of `run` held
17,738 constants (`lean/GAPS.md:989`) [M].

### 1.4 Call chain to the kernels

```
PV.Program.run                                   Johnson/PVR/Program.lean:290
 └ ending → claimOf, stepsOf, verdictAt          :254-287
    └ PV.Ride.rideThe = rideOf letsThe           Johnson/PVR/RideThe.lean:41-54
       └ rideOf ℓ Z O B commitment prompt output Johnson/PVR/RideAll.lean:64-79
          ├ tiePremB (five premises)             Johnson/Goal/Tie/TiePremisesAsRows.lean:27-43
          │   InScope Z                          Ladder.lean:307-312
          │   ℓ.live = protocolDataWellFormed    Johnson/Goal/Description/Live.lean:142
          │   cThru O Z, sevenThru O …           Johnson/PV/HeadCore.lean:48, :51
          │   decodeD (cThru O Z) B              Johnson/Goal/Tie/DescriptionOnBytes.lean:133-140
          ├ decodeD … B   (a second time)        Johnson/PVR/RideAll.lean:68
          └ stepsFullAllAt …                     Johnson/Goal/Tie/RunPureFull.lean:415
             └ fastSteps (twelve steps)          Johnson/Top/Fire/Code/VerifyVFastStepsD.lean:103-133
                ├ build, enc, hash code = commitment
                ├ piTE / piLE / piBE             Johnson/Top/Fire/Code/VerifyVFastD.lean:90-100
                ├ seedE … .det F                 …/VerifyVFastD.lean:112
                ├ armTE, armBE = verifyWholeX … .det F   OnBytes/Maker/LessWhole.lean:159-169
                └ armLE = stagesWL …             Johnson/RunOne/StrictLinkWL.lean:68
 oracle: O = Fmt.oracle                          Fmt/Rules23.lean:208-215
   └ formatHash → Fmt.blake2b = blake2bSaltedPlain   Fmt/Rules23.lean:170-172; Fmt/Blake2b.lean:22-23
      └ Run.Blake2b.message → compress           Run/Blake2b/Hash.lean:198-200; Compress.lean:168-213
 decisions: theKeyGate / theProofGate / theLinkGate   Johnson/Goal/Description/Gates.lean:38-45
   └ FileDescription.run over three Fmt.View     Johnson/Desc/Block.lean:771
      └ Block.decide, field ops OnBytes.mulE …   Johnson/Desc/Block.lean:93; Johnson/Desc/K1/Own.lean:53, :78
```

`rideOf` returns `.error` strings in three cases (premises, decoders, first public answer not 32
bytes; `RideAll.lean:67-79`). `verdictFrom` turns the run into `Option Bool`: `some s.yes`, or
`some false` when out of scope or when the decoders refuse (`RideAll.lean:106-116`); `verdictThe`
adds a reject where the files are in scope and `protocolDataWellFormed` says no
(`RideThe.lean:102-108`).

The verifier proper is not a direct function. `verifyWholeX` returns a
`TypedOracleComputation 256 (K + 1) L Bool` (`lean/OnBytes/Maker/LessWhole.lean:159-169`), a tree of
oracle queries: `inductive OComp … | pure (a : α) | query (o : S.ι) (q : S.Dom o) (k : S.Rng o →
OComp S α)` (`lean/Rom/OComp.lean:31-33`). `.det F` (`lean/Rom/Cache.lean:81`) evaluates the tree at
an oracle family `F` (`VerifyVFastStepsD.lean:53`, `:74`, `:123-126`). The family is built from the
byte oracle by `gOf O := fun _ s => bytesToDig (O (toBytes s))`
(`lean/OnBytes/TypedOracleCompiler/Run/PageRunFast.lean:46`), and `hashOf O` is `gOf O ()`
(`lean/Johnson/Top/Fire/Code/FastFamProbe.lean:36`).

The decisions are an interpreter over data. A file's protocol is a `FileDescription`, a list of
`Block`s; each block carries `decide : S → List Fmt.RoundView → List (List (Nat × List UInt64)) →
Except String S` (`lean/Johnson/Desc/Block.lean:69-93`), and `FileDescription.run` is "its
verifier's decision ON THE VIEWS THAT THE COMPILER HANDS" (`:29-31`, `:771`). The key file's seat
is built from the public files alone: `keyDataAndDecisionOrRefusalAt`
(`lean/Johnson/Goal/Description/KeyFold.lean:43-46`).

### 1.5 The twelve steps in code

`structure FastSteps` (`VerifyVFastStepsD.lean:78-95`), `FastSteps.yes` their conjunction
(`:98-100`), `fastSteps` (`:103-133`) [R]:

| step | code |
|---|---|
| `buildOk` | `build (prompt, output) aux` is `some x` (`:111-112`); at full size `build` is `Flat.buildReq` (`PvFront.lean:115`) |
| `encOk` | `enc ⟨cm, rcd⟩` is `some code` (`:114-115`) |
| `idOk` | `hash code = commitment` (`:117`, `:133`) |
| `laidT`, `laidL`, `laidB` | `piTE fT`, `piLE e`, `piBE fB` are `some` (`:118-121`, `:130-132`) |
| `num` | `num copy πB.plains` (`:122`) |
| `seed0`, `seedJ` | `(seedE … cm rcd.1).det F`, `(seedE … e.cm e.rcd.1).det F` (`:123-126`) |
| `armT` | `armTE`: `verifyWholeX` on the key file's data, `Tag.test` (`:46-53`, `:127`) |
| `armL` | `armLE`: `stagesWL`, "the strict link's fourteen lines" (`:55-63`, `:128`) |
| `armB` | `armBE`: `verifyWholeX` on the proof file's data, `Tag.onl` (`:65-74`, `:129`) |

"All twelve are computed when the record is built: no step is spared by an earlier no among the
last six" (`:16-17`). The first three and the three `laid` steps do short-circuit (`:111-133`).
`FastStepsIs` (`:136-147`) is a `Prop` stated there and "not proved here" (`:13-14`).

### 1.6 BLAKE2b in Lean

- Implemented in `lean/Run/Blake2b/` (14 files, 3,140 lines with theorems). No Mathlib.
- Data types: `ByteArray` in and out; the state is structures of `UInt64` fields: `ChainingValue`
  (8 words, `Compress.lean:46-55`), `MessageBlock` (16 words, `:60-77`), `WorkVector` (`:80-96`),
  `State` (`:155-161`). "There is no array and no loop" in the compression function: twelve
  written-out `ROUND`s with the sigma permutation inlined as argument order (`:29-32`, `:180-203`);
  `G`, `ROUND`, `rotr64` are `@[inline]` (`:116-147`).
- Message loop: `updateBlocks`, tail-recursive on the block count (`Hash.lean:180-182`), `message`
  (`:198-200`), output by `store64` pushes (`:224-232`).
- Two forms. `load64` reads with `USize` indices behind a proof (`Hash.lean:80-92`);
  `load64Plain` reads with `Nat` indices (`:60-68`). `Fmt.blake2b` is the plain form: "the form
  that Lean's kernel can compute; compiled code should call `blake2bF`" (`lean/Fmt/Blake2b.lean:9-10`,
  `:22-23`). `Fmt.blake2bF` is the fast form with `absorb`/`finish` for a shared prefix
  (`lean/Fmt/Blake2bFast.lean:30-48`), equal by theorem (`:65`).
- The format hash: `formatHash number tree index start bytes := blake2b (dlen number) salt pers
  (label number tree index ++ bytes)` (`lean/Fmt/Rules23.lean:170-172`), 64 bytes under number 162,
  else 32 (`:154`); thirteen domain numbers (`:114`).
- The oracle that a run uses: `Fmt.oracle : ByteArray → ByteArray` (`:208-215`). It *parses its
  argument back* (`oParse`, `:188-196`, with the domain test `hDom` `:164-167`), calls `formatHash`
  and returns one 32-byte half. It calls the plain BLAKE2b, since `formatHash` does (`:171`).
- A second, fixed hash on the same compression function: `OnBytes.secondHashFunction`
  (`lean/OnBytes/Hash/SecondHashFunction.lean:56`).
- The library has no `@[csimp]`, `implemented_by` or `extern` of its own (my grep over `lean/`
  found the words only in guard code and comments; `lean/Johnson/Desc/Laid/ProofAsks.lean:26` says
  `scripts/check.py` rejects them) [S].

### 1.7 Goldilocks and the cubic extension

Three representations exist [R]:

1. Format layer, through `Nat`: `Fld.two` has `p = 18446744069414584321`, `c = 2`
   (`lean/Fmt/Rules1.lean:158-169`); an element is a `UInt64` below p (`:172`); `Ext3 := UInt64 ×
   UInt64 × UInt64` (`lean/Fmt/FieldE.lean:45`); `mul f a b := f.red (a.toNat * b.toNat)` with
   `red f n := UInt64.ofNat (n % f.p)` (`:50-55`); `inv` is `pow a (p - 2)` (`:57-59`). "How.
   Nothing is done for speed" (`:23`). `mulEF` reduces once per coordinate (`FieldEFast.lean:47-50`).
2. Machine words: `F := UInt64`, `structure E` with `c0 c1 c2 : UInt64`
   (`lean/OnBytes/Base.lean:50-61`); `addF`, `subF`, `mulHi`, `reduceWide`, `mulF` on 64-bit words
   after plonky2's `reduce128` (`lean/OnBytes/Field/Word.lean:20-25`, `:55-98`), "so that the
   compiled program needs no arbitrary-precision arithmetic on elements" (`:8-10`); extension in
   `lean/OnBytes/Field/Ext.lean:51-134`. Proved equal to (1) (`Word.lean:32-36`).
3. Proof side only: integers modulo p and `F[x]/(x^3 − 2)` over Mathlib in
   `lean/Cb/Gl/GlField.lean` ("No code, no protocol occurs here", head comment).

The description's decisions use (2): `open OnBytes …` and `mulE`, `subE`, `oneE`, `thetaE` in
`lean/Johnson/Desc/K1/Own.lean:18`, `:53`, `:78` [R, one kind of block sampled]. The second field
of the format (`Fld.one`, p = 2^61 − 1, `Rules1.lean:164`) is not the full-size verifier's: the
arms take `ckP .two` (`VerifyVFastStepsD.lean:48`).

### 1.8 Strings, digests, vectors, proofs

| thing | representation | where |
|---|---|---|
| oracle query string | `List Bool` (`BitString`, `ZKCP.Str`, `Rom.Bits`) | `lean/VerifiableInference/RandomOracleModel.lean:30`; `lean/ZKCP/Defs.lean:38`; `lean/Rom/Defer.lean:52` |
| digest | a function `Fin 256 → Bool` (`Digest`, `Iop.Dig 256`) | `RandomOracleModel.lean:33`; `lean/Iop/Wire.lean:17` |
| hash | `BitString → Digest` | `RandomOracleModel.lean:36` |
| token, commitment | `Token := ℕ`, `Commitment := Digest` | `lean/VerifiableInference/Statements.lean:28`, `:31` |
| a round's challenge | `Fin b → Dig 256` (function of functions) | `lean/Run/PlanPull.lean:108-113` |
| bits ↔ bytes | `bytesL` over lists, `digToBytes d := bitsToBytes (List.ofFn d)`, `bytesToDig b := fun i => Fmt.bitAt b i.val` | `lean/Run/CodingBits.lean:38-44`, `:58`, `:61` |
| view of a chain | `rounds : List RoundView`, `opened : List (Nat × Nat × List UInt64)` | `lean/Fmt/View.lean:35-43` |
| vectors, polynomials | `List E` / `List F` with `Array` accumulators: `eqTable : Array E`, `polyEval (c : List E)`, `mleEvalE : List E → List E → E` | `lean/OnBytes/Field/Mle.lean:55`, `:61`, `:89` |
| parsed proof | `FormBytes` (five `ByteArray`s and `aux`), decoded by `decodeD`, which "hashes nothing" | `lean/Johnson/Goal/Tie/DescriptionOnBytes.lean:124-140` |

No Mathlib `Polynomial`, `Finsupp` or `ZMod` was found in the kernels I read. Of the 1,670
natively compiled library modules, 15 mention `ZMod` and 9 mention `Polynomial` [S]; whether any of
that code executes in a run I did not determine.

## 2. The parser (`tools/parser/`)

- What it is: `parse_files.sh` (bash), `parse_files.py` (Python, 38 KB), `read_parsed.py` (a second
  Python reader), and a C++ tool built at every call: `g++ -std=c++17 -O2 …` compiles
  `verifier/src/cp_verify.cpp` as a unit and links `tools/audit/pubtool.cpp`
  (`tools/parser/parse_files.sh:123-128`). `pubtool` writes the plans from the three public files
  with "the C++ verifier's own configuration code" (`tools/parser/README.md:106-107`); the parser
  "does not derive a plan" itself. Then `parse_files.py` (`:132`) and three `read_parsed.py`
  read-backs (`:134-136`).
- Outputs (`tools/parser/README.md:82-86`; `PARSED-FORM.md:9-15`): `key.parsed.bin`,
  `leaf-<k>.parsed.bin`, `proof.parsed.bin`; `<file>.seeds` (and `.seeds0` for the leaf);
  `<file>.order` (tests); with `--lines`, JSON lines for people. Lean reads five of them: key,
  key seeds, leaf, leaf seeds, proof (`lean/Johnson/PVR/Program.lean:247-249`).
- Format (`PARSED-FORM.md:20-37`): the format's own encoding: `u64` little-endian, `F` one `u64`,
  `E` three, `digest` 32 bytes, `bytes` and lists length-prefixed, structs as fields in order. Key
  and proof files have seventeen fields (magic `FPKEYC01` / `FPPRFC01`, root, answers, three
  chains' run values and rounds, trees, stored rows, binding root, …; `:39-60`); a leaf file has ten
  (`:124`). "A reader of a parsed file needs no hash, no plan and no public file" (`:17-18`).
- Why it exists, as upstream states it: "A verifier in Lean that takes typed values cannot read a
  file's bytes" (`README.md:3`), and "No file of the format holds a length, a count or an offset …
  the length of an opening … depends on the positions that were sampled, and these come out of the
  hash chain. So the parser replays every hash chain of a file" (`README.md:47-52`). It also
  *computes* values that are in no file: each chain's run value, the binding root, and "the whole
  path of each opened leaf" (`:54-56`).
- [I] The Lean language can read bytes (verify-on-bytes does, section 5). The pre-pass exists
  because the proved `verify` takes a typed proof and its decoder must hash nothing
  (`DescriptionOnBytes.lean:132`); cutting a raw file needs the hash chain, so that work is placed
  on the prover's side of the theorem.
- Trust: untrusted for soundness; "whatever the parser makes of their bytes is just the prover's
  last step" (`README.md:10-12`); the claim does not pass through it (`:13-21`). Cost: "about 1.5 GB
  of memory and a few minutes" (`:78-79`). Files above 2^28 bytes are refused (`:128-129`).
- Consequence for agreement with `cp_verify`: "One original file has many parsed files … several
  original files can have one parsed file … So the two need not agree on every file"
  (`README.md:113-120`).

## 3. Why it is slow

### 3.1 What upstream measured [M]

| what | time | where |
|---|---|---|
| a call to an accept or late reject | 19 to 39 min, "on about one core"; peak 9 to 15 GB | `tools/lean-verify/README.md:315` |
| three calls, one stored proof | 1,393 to 1,440 s, up to 14.13 GB, 64-CPU shared machine | `guide/performance.md:23`, `:54` |
| 35 calls side by side | 1,287 to 1,532 s each | `lean/THEOREM.md:542-543` |
| early reject (`idOk no`) | 4.5 to 11 min | `tools/lean-verify/README.md:316` |
| all interpreted (`--no-native`) | 9 h 18 min, one run | `README.md:318` |
| `verify-on-bytes`, compiled, full size | 112.1 s ± 0.6 (4 rounds); 120.8 s and 5.19 GB (one call) | `lean/OnBytes/LIMITS.md:813-815`, `:870-871` |
| `cp_verify`, same comparison | 25.0 s, 3.44 GB | `lean/OnBytes/LIMITS.md:871` |
| `cp_verify`, one thread, prover's machine | about 21 s, up to 3.53 GB | `guide/performance.md:23`, `:50` |

Upstream publishes no profile of the 19–39 minutes. The code comments decline to state times:
"Nothing on time or memory" (`VerifyVFastStepsD.lean:17`), "no time is written down here"
(`PageRunFast.lean:30-31`), "How fast anything is: that is measured outside this file"
(`lean/Fmt/FieldEFast.lean:30`). So every attribution of time to a cause below is [I]; the causes
themselves are [R].

### 3.2 Causes, with the definitions

**(a) The verifier is compiled from an IOP inside Lean, over bit strings and function-typed
digests.** This is the largest structural difference from `verify-on-bytes`, which shares the hash
kernel, the word field and `Fmt.View`.

- A digest is a function: `abbrev Dig (lam : ℕ) : Type := Fin lam → Bool` (`lean/Iop/Wire.lean:17`).
  Upstream's own diagnosis: "a digest is a function of the bit's number. Where a branch of a match
  has a function's type, the compiler puts the whole branch under a λ (seen in its output), and the
  call of the hash with it; so the hash is computed anew for every bit that is asked: 256 calls for
  one digest" (`lean/Run/CodingFnThin.lean:23-26`). In its trials "At a node famP asked 1 time and
  famOf 256 times … At a chain answer of three blocks famP asked 3 times and famOf more than 400
  times" (`:42-44`). The run form works around it by computing answers "first as data"
  (`:27-29`; `PageRunFast.lean:8-12`), but digests stay closures over a byte array
  (`digS`, `CodingFnThin.lean:95-98`) and are turned back into bytes bit by bit
  (`digToBytes`, `lean/Run/CodingBits.lean:58`).
- Every oracle query is a `List Bool`: "The strings are `codeRun`'s: still lists of bits, which are
  laid back into bytes: one pass over each string" (`PageRunFast.lean:26-27`), through
  `toBytes`/`bitsToBytes`/`bytesL` (`lean/Run/OracleBits.lean:42-43`; `CodingBits.lean:38-44`).
  Salts are bit lists too (`CodingFnThin.lean:90-91`).
- Type-level protocol data can be built at run time: "Compiled Lean is strict: a function that has
  the interface as a parameter, even an implicit one that stands in types alone, may get it built
  at the call. That is hopeless for one drawn field element" (`CodingFnThin.lean:15-17`).
- Structures sized by the tree, not by what is read: "Each written round's record holds the list of
  all positions of the round's trees … which the verifier never reads. The list has 2 ^ depth
  members for each of the round's trees" (`lean/OnBytes/Maker/LessWhole.lean:8-11`); `verifyWholeX`
  is the variant that avoids it.
- Draws: the proof-side reader "lays its words by `Fin.cons` … and looks a word up twice for every
  entry … At a round with very many entries that does not end in any useful time"
  (`lean/Johnson/RunOne/DrawT.lean:11-15`); the run kit `ckPT` replaces it (`:56-61`), yet "ALL b
  blocks of the round are read, drawn from or not: where a block stands behind a delayed hash,
  every one is hashed" (`:26-27`).
- The verifier is a query tree (`OComp`, section 1.4) evaluated against the family, with
  continuation closures at every query.

**(b) Redundant hashing.**

- A 64-byte answer is computed twice. `Fmt.oracle` returns one half per call
  (`lean/Fmt/Rules23.lean:213-214`) and `HO` asks both halves (`:228-232`). "A call of `cp_verify`
  for a round's challenges gives 64 bytes, and the form queries its two halves apart"
  (`lean/GAPS.md:245`).
- No midstate reuse. "Fmt/Rules5.lean hashes each call from its start: with a message of many
  thousand bytes and eleven calls that is eleven times the whole message"
  (`lean/Fmt/Rules5Fast.lean:10-11`), and the shared-prefix form cannot be used when the hash is an
  argument: "a state cannot be kept across calls of a hash that is handed in as a function"
  (`:36-37`). The executable form takes `O` as a function (`RideAll.lean:64`).
- A fixed number of blocks per round. One comparison on the stored full-size proof: the form made
  1,166,983 hash calls; `cp_verify`'s log has 600,017; "there are 142,924 that `cp_verify` never
  computed", because "Lean fetches a fixed number of blocks for each round (Fmt/Rules5.lean), and
  `cp_verify` computes a call only when the sampling reaches it" (`lean/GAPS.md:245-251`) [M].
- No cache: "A query that is asked twice is answered twice" (`PageRunFast.lean:22`); each
  configuration-class query is made twice (`GAPS.md:245`).
- Per call, `Fmt.oracle` re-parses the string it was just handed, re-checks the domain and
  re-concatenates label and bytes before hashing (`Rules23.lean:188-196`, `:170-172`), with the
  `Nat`-indexed BLAKE2b form (`lean/Fmt/Blake2b.lean:9-10`).
- By the text, `decodeD` over the five parsed files is evaluated twice per run: once inside
  `tiePremB` (`TiePremisesAsRows.lean:38-39`) and once in `rideOf`'s `match` (`RideAll.lean:68`);
  `cThru O Z` and `InScope Z` likewise recur (`RideAll.lean:67-72`, `:108`;
  `RideThe.lean:104-106`). [I] Whether the compiler or interpreter shares any of these was not
  measured.

**(c) The top of the call chain is interpreted.** Seven modules must stay out of the native helper
library (`tools/lean-verify/LeanVerifyWalk.lean:48-50`), and "each module that is one of `leftOut`,
or imports one, directly or indirectly" is struck (`:14-15`); "The code of a struck module is not
in the helper library: Lean interprets it" (`:31-32`). The reason is start-up cost: "A compiled Lean
program first runs the start-up code of every module that it imports, and that code evaluates every
definition that takes no argument. For each of the last six names of `leftOut` we built a program
that imports that module and prints one line: each ran out of memory (24 GB) before it printed"
(`:21-24`).

[S] From the import lines: the import closure of `Johnson.PVR.Program` has 4,172 library modules;
1,670 are in the native list; 892 import a left-out module and so are interpreted wherever their
code is reached; the other 1,610 hold no reached code by the walk's rule. The 892 include every
module from the entry down to the step record and the arms' definitions:

| module | holds | native? |
|---|---|---|
| `Johnson.PVR.Program`, `RideThe`, `RideAll` | `run`, `rideOf`, `verdictThe` | no |
| `Johnson.Goal.Tie.RunPureFull` | `stepsFullAllAt` | no |
| `Johnson.Top.Fire.Code.VerifyVFastStepsD`, `VerifyVFastD` | `fastSteps`, `armTE/LE/BE`, `seedE`, `piTE…` | no |
| `Johnson.RunOne.StrictLinkWL` | `stagesWL` (the link arm) | no |
| `Johnson.Goal.Description.{Gates,KeyFold,ProofFold,Live,LinkDec,Plan}`, `Johnson.Desc.Key.Slot` | the decisions' seats and gates | no |
| `Johnson.Desc.Key.{Desc,Road,Asks}` | assembling the key file's description from the public files | no |
| `Johnson.Goal.Tie.DescriptionOnBytes`, `Johnson.PV.EntryInOf` | `decodeD`, `entryAllD`: the decoders of the parsed files | no |
| `Johnson.PV.HeadCore`, `Johnson.Top.Fire.Code.PvFront`, `Ladder` | `cThru`, `idOf`, `userOf`, `InScope` | no |
| `OnBytes.Maker.LessWhole`, `ListedWhole`, `Rom.OComp`, `Rom.Cache` | `verifyWholeX`, the query tree and `det` | yes |
| `Johnson.Desc.Block`, `BlockSlot`, `Step`, `K1.Own`, `K1.Send`, `Johnson.RunOne.DrawT` | `FileDescription.run`, the blocks' `decide` (sampled), `ckPT` | yes |
| `Fmt.Rules23`, `Fmt.Rules5`, `Run.Blake2b.*`, `OnBytes.Field.*`, `Run.CodingFnThin`, `PageRunFast` | hash, chains, field, oracle bridge | yes |

So the inner loops are native and the orchestration, the decoding of the parsed files and the
building of the protocol's description are interpreted. [I] Closures made in interpreted code and
handed to native code (the decisions, the oracle family) are then entered through the interpreter
at each call; that cost is unmeasured.

How much time the interpreted part costs is not recorded. The bound is the `--no-native` run, 9 h
18 min against 19–39 min (`README.md:315`, `:318`): native code matters by a factor of 14 or more.
Upstream also notes "A wrong list can cost time, or cost a run its verdict"
(`LeanVerifyWalk.lean:32`).

**(d) One thread, no parallelism.** `lean -j1` (`lean_verify.sh:274`); "on about one core"
(`README.md:315`); no `Task.spawn`, `IO.asTask` or `Task.map` anywhere under `lean/` [S].
`cp_verify` "can use several threads" (`lean/OnBytes/README.md:116-117`).

**(e) Deep non-tail recursion.** "`Fmt.drawRound` is no loop (`Dr.times`, Fmt/Rules6.lean, builds
behind its call): the stack that it needs grows with what the round draws" (`DrawT.lean:27-28`);
`bytesL` is not tail-recursive (`CodingBits.lean:38-42`). The run reserves a 4 GB thread stack:
`--tstack=4000000` (`lean_verify.sh:274`; `README.md:43-44`). For verify-on-bytes, seven reached
functions have "no known bound on the depth of their recursion" (`lean/OnBytes/LIMITS.md:659-663`).

**(f) No early exit after the sixth step.** `num`, `seed0`, `seedJ` and the three arms are all
computed whatever the earlier ones say (`VerifyVFastStepsD.lean:16-17`); a late reject costs "about
as long as step 2" (`README.md:101-102`).

**(g) Fixed overhead outside verification.** Each call compiles C++ (`parse_files.sh:123-127`),
replays the hash chains in Python and reads the result back three times (`:132-136`), has Lake
check 5,056 targets, and links the helper library anew "in 9 to 38 s (once … 125 s)"
(`README.md:344-345`); the first call also compiles the helper library, 5 to 9 minutes (`:314`).
The early reject, which stops at the third step, still takes 4.5 to 11 minutes (`:316`). [I] That
figure is mostly this overhead plus Lean loading the import closure, since `idOk` is decided before
any arm runs.

**(h) Memory.** 9 to 16 GB; "How much memory a call takes varies, and why is not known"
(`README.md:338`).

### 3.3 What the evidence does not support

- Bignum field arithmetic as the main cause. The `Nat`-based `Fmt.Fld` exists (section 1.7), but
  the sampled decisions use the word field, the same as verify-on-bytes, which runs in about two
  minutes. In the description files I sampled (`Johnson/Desc/K1`, `K8`, `Step.lean`,
  `Oracle.lean`) the only `Fmt.Fld` names are `Fmt.Fld.two.p` (8 times) and `okE` (twice) [S]. Not
  traced end to end.
- Mathlib abstractions on the hot path. The helper library holds 3,113 Mathlib modules only
  because the list "must be closed under imports" (`native-modules.txt:4`, `:8`;
  `LeanVerifyWalk.lean:15-16`). What a run does use of Mathlib, by the guard: "five of them
  Mathlib's stand-ins for the recursors of Bool, List, Option, PSum and Sum"
  (`ProgramGuard.lean:12-14`).
- BLAKE2b's inner loop. It is straight `UInt64` code (section 1.6). At 1,166,983 oracle calls in
  about 1,300 to 1,500 s the average is over a millisecond per call [I, arithmetic on two [M]
  figures], far above a few compressions; the cost sits around the hash, not in it.

### 3.4 Upstream on why it is built this way

- "`cp_verify`, the C++ program, is the verifier that users run: fast, tested, not formally
  verified. This command is the slow cross-check" (`tools/lean-verify/README.md:7-8`).
- "So that a run takes minutes and not hours, the first call compiles most of the Lean code that it
  needs into a shared library" (`README.md:15-16`).
- "`lean-verify` is a command of this repository, not a stand-alone program: no stand-alone
  verifier program is proved sound" (`lean/THEOREM.md:559-560`).
- The compression function is written without arrays because "A compiled verifier calls `compress`
  millions of times and Lean's kernel evaluates it inside proofs" (`lean/Run/Blake2b/Compress.lean:29-31`).
- "A protocol's decision multiplies in E some hundred thousand times" (`lean/Fmt/FieldEFast.lean:13`).
- "a run takes tens of minutes" (`guide/verify-a-proof.md:210`).
- Interpreted Lean elsewhere: one asking file "without `--load-dynlib` … took twelve and a half
  minutes" at the small example (`lean/Ask/README.md:21`); `tools/accepts … small` took 31 minutes
  on one core and about 10 GiB (`tools/accepts/README.md:46-48`).

## 4. Scope restrictions

- **Full size only.** Fixed in three places [R]: (1) `T` is the constant 1,024, so the request
  file must have 4,104 bytes, else no verdict (`Program.lean:77-80`, `:92-95`, `:228-229`;
  `tools/lean-verify/README.md:129-130`); (2) `InScope Z := decide (Z.lay = storedPublicFiles.lay)
  && … decide (Z.pol = policyFile (freeLinesOf pp)) && decide (2 ^ 8 ≤ pp.pol.theta)`
  (`lean/Ladder.lean:307-312`): the layout file must equal the stored full-size example's byte for
  byte and the parameter file must be that example's "but for the eight free numbers", so "only the
  scale file and these eight numbers are free" (`:297-301`); (3) the decisions are typed at the
  full-size record: "THE FULL SIZE ALONE" (`lean/Johnson/Desc/Key/Slot.lean:30`;
  `KeyFold.lean:19`). "The small example's files are out of scope: `verify` rejects them"
  (`lean/THEOREM.md:303`).
- **Policy.** `verify` tests scope and reading, not exact match (`Program.lean:298-301`). At other
  in-scope policies it can accept (`:301-304`); the script then prints `ACCEPT (under the files'
  policy …; NOT exact match …)` with exit code 0 (`lean_verify.sh:180-186`, `:300-302`). In scope
  `256 ≤ theta ≤ C < 2^32` and `cap ≤ 1,024` (`lean/THEOREM.md:1351-1352`). `verify` does not
  reject policies that mean nothing, "the C++ programs do" (`:1353-1357`).
- **Linux x86-64.** Stated, not explained: "It takes full-size files only, on Linux x86-64"
  (`tools/lean-verify/README.md:18`); "You need Linux (x86-64; nothing here is tested on another
  system)" (`lean/CHECKING.md:171`). [I] Concrete ties in the script: `prlimit` and GNU
  `stat -c`, `realpath -e`, `timeout` (`lean_verify.sh:77`, `:109`, `:274`), and a `.so` built by
  `leanc -shared` (`:255`). All measurements are on Linux x86-64 servers with GCC 15.3.0, not the
  clang that Lean ships (`README.md:302`, `:308-309`).
- **Other things it refuses or lacks that `cp_verify` handles.**
  - Tests 1–4 on the user's files give *no verdict* where `cp_verify` rejects (`Program.lean:87-91`).
  - Sixteen tests of its own on the public files, as gates (`lean/THEOREM.md:305-307`,
    `:1292-1295`); cost exponent 8 only, where `cp_verify` admits 7 and 8 (`:1298-1301`); the scope
    fixes `reading 1`, `rowcost 1`, `answers 1`, `listed 0` (`lean/OnBytes/LIMITS.md:596-598`).
  - Six positional arguments, the ID mandatory, no `-bits`, `-next-token`, `-policy`,
    `-no-proof-of-work`, `-key`, `-leaf` (`lean_verify.sh:9-12`; compare
    `lean/OnBytes/README.md:106-110`).
  - One proof, one request: the bound "is for one commitment, one prompt, one output, one proof and
    one call of `verify`" (`lean/THEOREM.md:150-151`).
  - Files above 2^28 bytes (`Program.lean:195`; `lean_verify.sh:109`).
  - It judges the *parsed* file. Altered parsed proofs with bits turned in Merkle-path entries that
    the walk does not take were accepted; at three matched places `cp_verify` rejected the raw proof
    and the form accepted the parsed file (`lean/THEOREM.md:639-660`). The parser refused 3 of 57
    lying proofs outright, "and a no-verdict is not a rejection" (`:593-595`).

## 5. `lean/OnBytes/` (verify-on-bytes) as a porting reference

### 5.1 What it is

"a hand translation of `cp_verify` into Lean, from which this repository builds no stand-alone
program" (`lean/OnBytes/README.md:5-6`). "The program reads the same proof files as the C++ verifier
`cp_verify`, in the same byte format … and it takes the same arguments. It follows `cp_verify`'s
source, and is a test tool" (`:9-12`). "It is not `verify`" (`:14`). "No soundness theorem reaches a
call that checks a real proof" and "the two programs are not independent" (`:22-25`).

### 5.2 Size and files

The folder has 3,074 Lean files, 618,963 lines; most are theorems, tests and files used beneath the
main theorem [S]. The *program* is the import closure of `OnBytes.Main`: 200 modules
(`lean/Ask/README.md:111-113`; `lean/OnBytes/LIMITS.md:671`), 48,520 lines with comments, one
external import, `Std.Data.HashMap`, no Mathlib [S]:

| part | modules | lines | role, and the C++ it cites |
|---|---|---|---|
| `OnBytes/Model/` | 60 | 18,919 | the call as "one pure function of the bytes of all inputs", rendering `cpMain` (`verifier/src/cp_verify.cpp`): heads, public files, planner inputs, chains, accounting, statement, the three stages, attention/layer/head model checks (`Model/Verify.lean:4-18`); cites `cp_verify.cpp`, `vf_common.h`, `vf_attention_check.h`, `vf_weights_layout.h` |
| `OnBytes/Iop/` | 17 | 7,293 | protocol building blocks (`Cs`, `Fold`, `Foldeq`, `Lin`, `Link`, `Lkp`, `Prox`, `Psc`, `Req`, `Tensor`, `Wf`, `Ground`); cites `blocks/iop/*.h` |
| `Fmt/` | 22 | 6,133 | the format rules as functions on bytes: `Rules1` (encoding), `Rules23` (hash), `Rules4`–`Rules8X` (chains, draws, trees, strict reader), `ParamsRead`, `Plan`, `View`, `FieldE` |
| `OnBytes/Params/` | 18 | 4,942 | parameter file reader and planner: schedules of all seven chains from the public files; cites `blocks/numbers/plan.h`, `blocks/frame/derive.h`, `cp_frame.cpp` |
| `OnBytes/Chain/` | 11 | 2,259 | the strict chain reader and session: hash chain, proof of work, draws, tree openings; cites `blocks/chain/rounds.h`, `blocks/tree/tree.h`, `opening.h` |
| `Run/Blake2b/` | 11 | 1,986 | BLAKE2b |
| `OnBytes/Shell/` | 9 | 1,440 | command line, file reads, printed lines |
| `OnBytes/Plan/` | 9 | 1,436 | layouts, ranges, units |
| `OnBytes/ChecksWithHashAsArgument/` | 17 | 1,283 | the second writing that `main` runs (`LIMITS.md:770-776`) |
| `OnBytes/Proof/`, `Key/`, `Entry/` | 7, 5, 2 | 1,097, 492, 191 | the three kinds of file; cite `blocks/frame/check.h`, `check_key.h`, `check_entry.h`, `handover_*.cpp` |
| `OnBytes/Field/` | 3 | 406 | `Word`, `Ext`, `Mle`; cite `blocks/field/gl64.h`, `field.h`, `mle.h` |
| `OnBytes/Hash/` | 3 | 150 | `H`, `Query`, `SecondHashFunction`; cite `blocks/hash/hash.h` |
| `Toy/`, `Base`, `Result`, `Walk`, `Main` | 6 | 493 | toy protocols, shared types, entry |

Upstream's own layout table: `lean/OnBytes/README.md:203-213`. Pages: `README.md` (213 lines),
`LIMITS.md` (955), `THEOREMS.md` (330), `GLOSSARY.md` (19).

### 5.3 How it is organised

A file is a sequence of chains, each checked in two steps (`lean/OnBytes/Base.lean:11-37`) [R]:

1. The strict reader `readChain` reads the chain's bytes given its description (`Fmt.SpecX`: label,
   plan, parameter bytes, round forms, all from the public files). "The reader makes every hash call
   of the chain, tests the proof of work, draws the verifier's messages and checks every opening of
   a tree against its root" (`:26-28`).
2. A decision tests the equations on what was read: "a pure function of public values and of the
   view (`Fmt.View`)"; "No decision reads bytes or calls the hash" (`:29-34`).

The whole call: `planned` derives everything from the three configuration files
(`Model/Verify.lean:58-62`), then three stages (key, leaf, request) run under one planner call
(`:13-18`; `LIMITS.md:739-747`). The shell reads the files and calls `wholeCall`
(`Model/Verify.lean:20-22`).

### 5.4 Representations

`F := UInt64`, `E` a structure of three `UInt64` (`Base.lean:50-61`); word arithmetic
(`Field/Word.lean:55-98`); the format hash in the compiled form, `formatHashFastForm := Fmt.HF`
(`Hash/H.lean:11-13`, `:31-32`; `lean/Fmt/Rules5Fast.lean:47`), with midstate sharing in the first
writing (`LIMITS.md:796-798`); files as `ByteArray`; vectors as `List`/`Array`
(`Field/Mle.lean:55-152`); `Std.HashMap` in `Chain/Index.lean` and `Iop/Tensor.lean` [S]. Every
function is total; no `partial` or `unsafe` definition in these folders [S].

### 5.5 Is it a complete rendition of `cp_verify`'s checks?

Intended to be, for the three checking calls: "This file renders the checking calls of cpMain …:
the whole call, -key and -leaf. Not rendered: the calls -plan …, the parsing of the command line
except three of its tests …, and the guards of main on the machine" (`Model/Verify.lean:6-9`).
Results and exit codes "are meant to be the same as for `cp_verify`" (`README.md:130-132`). It is
not restricted to full size: small example about 7 s and 0.3 GB, full size 121 s and 5.2 GB
(`README.md:115-116`). Documented differences (`LIMITS.md:527-728`) [R]:

- 15: the model's four lookup tables are computed in integer arithmetic; `cp_verify` uses floating
  point and the platform's math library (`:529-535`).
- 16: two of `cp_verify`'s planner checks on how a mask tree is opened "are not implemented here"
  (`:536-545`); one check on which taken-over tree an opening belongs to is weaker (`:567-584`);
  the parameter reader admits `reading`/`rowcost` 1 or 2, `answers` 1 to 4, `listed` 0 to 8 where
  `cp_verify` refuses (`:585-598`). "this program could accept what `cp_verify` rejects".
- 17: proof-of-work figures exact here, floating point there (`:599-616`).
- 18: refuses more and costs more: length limits (`:618-624`), a quadratic layout check
  (`:645-649`), "about 1.5 times the memory of `cp_verify` and more than 5 times its CPU time"
  (`:650-653`), deep recursion (`:659-665`), panics on out-of-range reads (`:666-676`).
- 19: only parameter files with attention proofs, routed experts and the 32 digest lines
  (`:677-680`).
- 20: names after `NO:` and exit codes can differ; it "reads all chains of a proof file before it
  tests any equations" (`:681-705`).
- 21: hostile environments (`:720-728`).
- `-q`, `-j`, `-show-stages` "are accepted but change nothing. The program runs on one thread"
  (`README.md:113-115`).
- 24: `main` runs a second writing of four checks with the hash as an argument, equal to the first
  by a theorem on terms (`LIMITS.md:770-791`); the two timed alike (`:811-821`).

Also to weigh: in one experiment "for most model checks (263 of 378), removing the check changed
the result of no full call" (`README.md:84-85`), so honest-file agreement does not show that a port
kept every check.

### 5.6 How it is run, and how fast

- This repository builds no program from it: "`lakefile.toml` names no target that builds one"
  (`README.md:103-104`); `lake build` "builds no program" (`:112-113`).
- `tools/accepts/` does not run `OnBytes.Main`. It converts `examples/accepted-proof` with the
  parser and runs four files of `lean/Ask/` (`tools/accepts/sheets.tsv`), "single parts' checks on
  the parsed files, part of them written to follow the C++ verifier"
  (`tools/accepts/README.md:9-13`, `:25-26`), at small size only: "`full` … is not in `sheets.tsv`,
  so the command ends without testing anything, exit code 2" (`:13-15`). `small` took 31 minutes,
  one core, about 10 GiB (`:46-48`); a second run about 33 minutes (`:49-52`).
- The compiled code can be loaded into Lean as `libvob.so`, built from
  `lake query +OnBytes.Main:transImports` (`lean/Ask/README.md:93-108`).
- The stand-alone timings come from builds upstream made itself, "with builds of copies of the
  sources that differ from this repository's" (`README.md:8-9`; `LIMITS.md:36-39`). The build
  nearest to these sources passed the three stored examples beside `cp_verify` in 12 pairs of whole
  calls (`LIMITS.md:852-868`) [M].

### 5.7 Assessment

- Good reference: self-contained, first-order, total, already split into reader and decisions,
  byte-exact on the same files, each folder naming its C++ counterpart, with build-time known
  answers (`Field/TestField.lean`, `Hash/TestBlake2b.lean`, `Fmt/Rules23.lean:246-255`).
- Its measured cost, about 5 times `cp_verify` on one thread, is the fairest upstream estimate of
  what a straightforward functional rendition costs [I].
- Not a specification: unproved, not independent of `cp_verify`, with the differences above. The
  byte format is the one that `docs/format/FORMAT.md` defines (`README.md:10-11`), and which values
  a parameter file's lines may have "is `cp_verify`'s to judge" (`:72-73`).
- [I] Porting hazards visible in the text: `UInt64` everywhere (Bend has U32 only, so every field
  and BLAKE2b word is two limbs); `Nat` used for sizes, indices and labels; `ByteArray.extract` and
  `++` used freely; recursion depth; `Std.HashMap` in two places.

## 6. The theorem's shape

Name and place: `VerifierAndGoals.AtTheName.sound_of_verify_at`,
`lean/Johnson/Goal/Skeleton/SoundOfVerifyAt.lean:69`. As Lean prints it (`lean/THEOREM.md:116-123`):

```
sound_of_verify_at (Z : PublicFiles) (pp : Inst.Model.ScalesAndPolicy)
  (scope : InScope Z = true) (read : readFiles Z = Except.ok pp)
  (exact : pp.pol = Inst.Model.AcceptancePolicy.exact) :
  Sound (systemOfRecord (atSecondHashFunction theDescription) Z (settingsOfRead pp))
    fun t => soundnessErrorInQueries t 1
```

Informally (`lean/THEOREM.md:256-261`): at public files that are in scope, are read, ask for exact
match and are fixed before the hash function is sampled, a fixed extractor reads at most one set of
weights off the commitment and the committer's hash queries, and `verify` accepts an output that is
not the model's at those weights with probability at most about q/2^124 + 2^-101.

- Hypotheses: `scope`, `read`, `exact` (three; `Program.lean:298-301`). Exact match is `C, theta,
  cap = 256, 256, 0`, "a premise on the parameter file, not a test in the text of `verify`"
  (`THEOREM.md:210-213`).
- Model: random oracle for the format's hash; a second fixed hash function "assumed independent of
  it"; classical adversaries; public files fixed before the hash is drawn (`:217-225`, `:387-397`,
  `:1227-1230`).
- Bound: `soundnessErrorInQueries q 1 = 16·T/2^128 + (T + 2)²/2^256` with `T = q + 1 + 2^23`
  (`:285-287`); one query is 32 bytes, so a 64-byte BLAKE2b call is two (`:288-291`). "about 124
  bits per query; not «128 bits»" (`:1227`). For one commitment, prompt, output, proof and call
  (`:150-151`).
- Axioms: `propext`, `Classical.choice`, `Quot.sound` only; no conjecture on codes (`:377-381`).
- Without exact match: `soundUnderPolicy_of_verify_at`
  (`lean/Johnson/Goal/Skeleton/SoundOfVerifyPolicy.lean:63`) gives only that the output meets the
  files' policy, which "alone it is weak" (`THEOREM.md:1336-1341`, `:1380-1391`).

Relations claimed between the four verifiers [R]:

| pair | what ties them |
|---|---|
| `verify` ↔ executable form | theorems: `PV.Ride.theForm_eq_verify` (`lean/Johnson/PVR/SoundOfTheForm.lean:87`), for any byte function with 32-byte answers in the hash's place; `sound_of_the_form_events` (`SoundOfTheFormEvents.lean:252`); `verdictOf_map` (`ProgramTotal.lean:37`). "These are statements about the term's value, not about whether or when an evaluation ends" (`THEOREM.md:526-527`) |
| executable form ↔ a run | none. "No theorem speaks of `run` …, of compiled code, or of whether `claimOf` cuts your files as the format page means" (`THEOREM.md:548-551`). A run trusts Lean's kernel, compiler, interpreter, loader, runtime, Lake, the C compiler, the parser's outputs as prover data, and the unproved claim readers (`tools/lean-verify/README.md:267-290`) |
| `verify` ↔ `verify-on-bytes` | none: "it is a different verifier, the theorem is not about it" (`lean/README.md:190-194`). `verify` uses some of its definitions for the scope test and public-file reading (`lean/GAPS.md:64`) |
| `verify` ↔ `cp_verify` | tests only: "Nothing is proved about them … What ties them to Lean is tests" (`lean/README.md:185-187`). "The two verifiers are close, not identical" (`THEOREM.md:1292`); they part on some altered files (`:652-660`); 881,280 of the form's 1,166,983 hash calls matched `cp_verify`'s (`:1296-1298`) |
| `verify-on-bytes` ↔ `cp_verify` | source-following and tests; theorems only of the form "if `main` returns 0 then its checks said yes on the bytes it read" (`lean/OnBytes/README.md:39-45`) |

What an independent implementer can honestly say: a new verifier is a fifth program with no
theorem. Agreement with `cp_verify` on files is test evidence about an unproved program; agreement
with `lean-verify` verdicts on full-size exact-match files is test evidence against the proved one,
through an unverified parser and run. The q/2^124 + 2^-101 bound is `verify`'s alone.

## 7. Toolchain facts

- Lean `leanprover/lean4:v4.29.1` (`lean/lean-toolchain`). Upstream notes that this version "is
  older than fixes of publicly known soundness bugs in it" (`lean/THEOREM.md:382-383`).
- `lean/lakefile.toml`: package `verifiableInference` 0.16.0; one `require`, Mathlib at rev
  `5e932f97dd25535344f80f9dd8da3aab83df0fe6`; three libraries: `Library` (28 directories and
  `Ladder`), `AtFullSide` (`--tstack=131072`), `ShapeLines` (`--tstack=262144`, no default target);
  options `autoImplicit = false`.
- `lean/lake-manifest.json` pins: mathlib `5e932f97…`; plausible `83e90935…`; LeanSearchClient
  `c5d5b8fe…`; importGraph `48d5698b…`; proofwidgets `4dd0959c…` (v0.0.95+lean-v4.29.1); aesop
  `7152850e…`; Qq `707efb56…`; batteries `756e3321…`; Cli `7802da01…` (v4.29.0).
- Size [S]: 29,563 `.lean` files and 6,016,507 lines under `lean/` (449 MB, sources only, no
  `.lake`). Largest: `Johnson` 20,414 files, `OnBytes` 3,074, `Cb` 1,515, `AtFullSide` 915, `E2E`
  865, `ShapeLines` 524, `Compile` 350, `Run` 349, `Fmt` 221.
- The executable verifier's import path [S]: 4,172 library modules, 856,682 lines: `OnBytes` 1,541,
  `Johnson` 752, `Cb` 684, `Run` 200, `ThirdParty` 140, `Fmt` 112, `Inst` 107, `Cm` 105, `Ior` 72,
  `Blocks` 71, `Iop` 71, `Compile` 66, `Rom` 51, `IntegerModel` 33, `VerifiableInference` 28,
  `ZKCP` 27, `Code` 26, `Hiop` 24, `Policy` 23, others 39.
- The native helper library: 5,056 modules, 1,670 of this library (379,636 lines [S]) and 3,386 of
  the packages, of which Mathlib 3,113, Aesop 135, Batteries 87 [S]
  (`tools/lean-verify/native-modules.txt:4`; `README.md:287`, `:367-368`).
- Building the soundness theorem compiles "about 16,000 Lean files" (`lean/README.md:220-221`); the
  verifier's build is "about a third of the Lean library" (`tools/lean-verify/README.md:14`).
- C compiler in all upstream runs: GCC 15.3.0 and GNU ld 2.46 in place of Lean's clang 19.1.2,
  which "is untried" (`lean/CHECKING.md:194-196`).

## 8. Baseline for benchmarking

### 8.1 Commands

One-time setup, in `lean/` (`tools/lean-verify/README.md:69-76`; `lean/CHECKING.md:179-184`, `:259`;
the README points to steps 1 to 3 of "The commands", `lean/CHECKING.md:231-259`, which I did not
read in full):

```sh
curl https://elan.lean-lang.org/elan-init.sh -sSf | sh     # Lean 4.29.1 from lean-toolchain
cd lean && lake exe cache get                               # Mathlib's compiled files
ls .lake/packages/mathlib/.lake/build/ir/Mathlib/Logic/Basic.c   # the packages must include .c files
LEAN_ABORT_ON_PANIC=1 lake build Johnson.PVR.ProgramGuard
```

The timed call, from the repository's top (`README.md:82-89`); expect exit code 0 and
`VERDICT: ACCEPT (exact match)`:

```sh
E=examples/full-size
tools/lean-verify/lean_verify.sh $E/config $E/ivk $E/example.req $E/example.y $E/example.proof $E/ID.txt
```

Companion calls: early reject with another ID (`:91-99`), late reject with another last token
(`:101-108`), the second stored set `examples/full-size-clipped-gap` (`:110-113`).

The `cp_verify` baseline on the same files (`examples/full-size/README.md:9-14`), after
`verifier/build.sh`, one thread for its longest stage:

```sh
bin/cp_verify examples/full-size/config examples/full-size/ivk examples/full-size/example.req \
  examples/full-size/example.y examples/full-size/example.proof \
  -id 7a285919b43961861d9839530c26725accf26aa6d74e3c2afa31b9dc6bcd18fe -q
```

### 8.2 The inputs

`examples/full-size/`: `example.proof` 18,779,540 bytes, `ivk/key.bin` 3,290,496,
`ivk/leaf/0.bin` 2,942,944, `example.req` 4,104, `example.y` 4, `config/layout.txt` 224,975,
`config/policy.txt` 2,629, `config/KL.bin` 2,784 [S]; synthetic weights, 1,001 tokens checked
(`guide/performance.md:23`).

### 8.3 What it needs

- Linux x86-64 (`lean/CHECKING.md:171`); `lake`, bash, GNU coreutils, diffutils, grep, sed,
  `prlimit`, `python3`, `g++` 13 or later (`tools/lean-verify/README.md:54-57`).
- Disk about 26 GB below `lean/.lake`, about 300 MB per call in `TMPDIR` (`:41-42`).
- Memory: 9 to 16 GB for a call; no tight `ulimit -v`, since "Lean's thread reserves a stack of
  4 GB" (`:43-44`, `:315`). One call at a time (`:47`).
- One-time build: 25 to 26 minutes on 96 cores, 33 on 48 threads, 49 on 32; 11.5 to 12.8 hours of
  processor time; 20 GB of the processes' own memory on 96 cores (`:313`). Helper library at the
  first call: 5 to 9 minutes (`:314`).

### 8.4 Fairness notes for a benchmark plan

- The 19 to 39 minutes include the parser (C++ compile, Python replay, three read-backs), Lake's
  checks, the link and Lean's start-up. Time the last stage alone as well: the script prints
  `running the verifier's executable form inside Lean` before it (`lean_verify.sh:262`), and
  `work/lean.err` is written as the lines come (`:262`).
- Discard the first call (it compiles the helper library).
- Upstream's own caveats: "None of these figures is an upper limit, and none was measured on the
  released files" (`README.md:302-304`); the fetch from public servers and Lean's own clang are
  untried (`lean/CHECKING.md:188-196`; `README.md:357-359`).
- Three baselines exist and should be named separately: `cp_verify` (about 21 to 25 s, or 36 to 44 s
  on a shared VM, `examples/full-size/README.md:7`), compiled `verify-on-bytes` (112 to 121 s, not
  buildable from this repository's `lakefile.toml` as shipped), and `lean-verify` (19 to 39 min).
  Only the first and third can be reproduced with shipped commands.

## Open questions

1. No profile. Upstream gives no split of the 19–39 minutes between the parser, Lean start-up,
   interpreted modules, oracle bridging and decisions. Is reproducing the baseline with per-stage
   timing in scope, given that it needs a 64-core-class Linux x86-64 machine and a build of about
   12 processor-hours?
2. Which semantics does the Bend verifier target: `cp_verify`'s (raw files, all its options and
   sizes; reference `lean/OnBytes/`) or `verify`'s (parsed files, full size, in-scope files only;
   reference `lean/Johnson/Desc/` and the compiler)? This note assumes the first. They are known to
   disagree on some altered files.
3. Does the Bend verifier parse raw files itself? Doing so means replaying every hash chain to find
   where openings end, as `cp_verify`, verify-on-bytes and the parser all do.
4. Which of verify-on-bytes' documented differences from `cp_verify` (points 15 to 21) should a
   port follow, and which should follow `cp_verify`? The lookup tables (integer here, floating point
   there) and the two unimplemented planner checks need a decision.
5. How many of the 892 struck modules hold code that a run actually reaches? `LeanVerifyWalk.lean`
   prints these counts (`:110-113`) but no page records them.
6. Which field arithmetic dominates the executable form's decisions? I sampled one block kind
   (word arithmetic); `Fmt.Fld`'s `Nat` arithmetic is used at least in the draws. Not traced whole.
7. verify-on-bytes as shipped has not been run by upstream as a stand-alone program built from this
   repository's sources (`lean/OnBytes/LIMITS.md:36-39`). Is building it (a `lean_exe` target over
   `OnBytes.Main`) acceptable as a differential-testing oracle and a second baseline? That would be
   a build of upstream code, outside this task's read-only rule.
8. The planner. The parser takes the plans from `cp_verify`'s C++ (`pubtool`); verify-on-bytes has
   its own planner in `OnBytes/Params/` (4,942 lines) with its own error accounting. Must the Bend
   verifier derive the round schedules and the 128-bit accounting itself, or may it take a plan as
   input?
9. Upstream's `verify-on-bytes` used 5.2 GB at full size and a stack above 10,240 kB
   (`lean/OnBytes/LIMITS.md:821`, `:878-879`). What are the memory and recursion-depth budgets for
   the Bend-to-C build?
