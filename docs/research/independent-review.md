# Independent review of the standalone verifier

> Status: frozen
> Snapshot of 2026-11-23. Verifier sources of `f82965b` (source identity `4bc6ecdd…7df5`, unchanged at `db0afff`), Bend 2.0.40, upstream at the revision of `upstream.lock`. Written by a reviewer that did not write the verifier. Findings are owned by the issues named beside them; this page is not updated.

## Verdict

The standalone verifier does what its release notes say on everything this review could run: a clean checkout builds it, it accepts the genuine small and full-size proofs with the published closing records, and across 1,400 altered inputs it never accepted where `cp_verify` refused. It is also slow, uses none of Bend's parallelism, and admits four configurations only. The experiment's question was whether Bend makes this verifier fast. The answer so far: faster than the theorem-linked Lean verifier (1.7 times at full size), slower than the compiled Lean translation (7 times) and than C++ (35 times), with a measured path to close most of that gap.

## What was run

Machine: Apple M4 Max, 16 cores, 48 GB, macOS 26, Apple clang 21. Everything from a fresh worktree, not the authors' build directory.

| Check | Result |
|---|---|
| `make bootstrap upstream standalone oracle` on a clean checkout | Built in 2 min 42 s. The verifier printed the published source identity. |
| Small exact-match fixture | `YES`, the published `result-v1` record. 9.0 s wall, 8.75 s CPU, 0.84 GB peak. `cp_verify`: 0.66 s wall, 1.22 s CPU, 0.21 GB. |
| Full-size exact-match fixture | `YES`, the published record (tokens 24..1023, next token covered). 328 s CPU, 11.6 GB peak. The wall time, 409 s, is not a clean figure: a fuzz campaign shared the machine. |
| `BEND_THREADS=1` against `16`, small fixture | 10.72 s and 10.69 s CPU in the same conditions. No effect. |
| Differential fuzzing, first campaign | 600 cases (400 exact-match, 200 clipped-gap): both verifiers refused all 600. |
| Differential fuzzing, recorded campaign (`scripts/fuzz-differential.py -n 400 --seed review-1`) | 800 cases: both verifiers refused all 800. Tally below. |
| GitHub CI on `f82965b` | Green (`make ci`, 30 min). Not rerun locally. |

Stage split of the small call, from inputs that stop early: a wrong commitment ID ends after the key stage at 1.0 s; a proof altered at byte 100 ends after the leaf and its link at 1.44 s; the whole call takes 9.04 s. The request stage is 84% of the time.

### The fuzz campaigns

Each case alters one of the eight input files (proof 60%, key 12%, leaf 12%, request, token, the three public files) by one of seven mutations (bit flip, byte change, zeroed word, swapped words, incremented word, truncation, extension) and runs both verifiers on the same bytes. The only failing outcome is a Bend accept beside a reference refusal.

Recorded campaign, seed `review-1`:

| Fixture | Cases | Proof | Key | Leaf | Request | Token | Parameter | Scale | Layout | Bend refused | C++ refused |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| accepted-proof | 400 | 238 | 46 | 36 | 26 | 13 | 19 | 10 | 12 | 400 | 400 |
| accepted-proof-clipped-gap | 400 | 250 | 41 | 40 | 14 | 6 | 18 | 11 | 20 | 400 | 400 |

By mutation over both fixtures: 292 bit flips, 161 byte changes, 78 incremented words, 70 swapped words, 68 truncations, 66 extensions, 65 zeroed words. The first campaign (600 cases, an earlier copy of the same script, seeds `audit-1` and `audit-2`) had the same outcome.

What this shows: no byte of any input file is ignored by the Bend verifier in a way that the reference notices. What it cannot show: almost every alteration of a hash-chained proof is caught by the next proof-of-work or opening test, so random alterations do not reach the algebraic checks. Those are covered by `make request-claims-test` (fixed-transcript cases) and by the argument in the [assurance contract](../spec/assurance.md); neither is exhaustive.

### The profile

`sample` over 20 s of the full-size call (16,873 samples of the working thread) and 11 s of the small call:

| Share (full / small) | Symbols | Reading |
|---:|---|---|
| 30% / 27% | `extension.product` | cubic-extension multiplication |
| 11% / 7% | `sumcheck.mul` | the same kernel, called from sumcheck code |
| 28% / 36% | `term_drop`, `span_fade`, `rfc_wrap` | freeing and reference-counting heap cells |
| 10% / 11% | `Clo_apply` | closure application |
| 20% / 17% | `row_tensor.choice`, `fold.deposit`, `fold.fix`, `fold.mix`, `List.length`, `List.drop`, `Nat.pow`, `String.order` | traversal and repeated lookups |
| under 1% | `hashlib.B2b.round` | all BLAKE2b |

## Findings

Ordered by consequence. None is a soundness defect.

1. **No parallel call anywhere in `src/`.** A search for parallel `let`s finds none, and thread count has no effect. The reason to try Bend was its parallelism; the verifier does not use it yet. FORMAT 13.6 makes the three stages independent, and inside the request stage hashing is under 1% of the time, so the sequential transcript does not stand in the way. Owned by [#19](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/19) and [#20](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/20).

2. **Most of the time is not arithmetic the protocol requires.** Half of the profile is memory management, closures and list traversal. Vectors are `List<E3>` of boxed six-field records, reversed and re-appended; `fold.deposit` builds and applies two closures per node through `Bool.pick`; lengths and powers are recomputed inside loops; arrays are converted back to lists. Owned by [#15](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/15), [#16](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/16), [#17](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/17).

3. **The field kernel does about twice the work it needs.** `E3.mul` makes 9 base products and 15 full reductions where 3 reductions suffice, and each 64-bit product spends 20 `U32` multiplications where 16 suffice. Owned by [#14](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/14).

4. **Peak memory is 11.6 GB at full size**, against 3.4 GB for the reference. Owned by [#18](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/18).

5. **Four configurations only.** Any other parameter, scale or layout file ends `NO: unsupported-configuration`: plans, geometry, weight placement and accounting are generated from the reference planner and compiled in. The fresh-proof record shows the verifier is not tied to fixture bytes (a new commitment and proof under a bundled configuration verify), but a provider's own configuration cannot be checked. Owned by [#29](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/29) to [#32](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/32).

6. **The tests do not show that each check is tested.** The sources hold about 320 distinct refusal names. Agreement on honest proofs constrains the algebraic coefficients, not the checks that stand apart from the final equation. Nothing measures which refusals a test reaches. Owned by [#25](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/25).

7. **Refusals do not name their stage.** In the recorded campaign 321 of the 488 proof-file faults and 53 of the 76 leaf-file faults ended `NO: key-opening`: the opening code is shared and reports a key-stage name. Owned by [#27](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/27).

8. **No law, no proof.** The repository states no `law`. The property that would set a Bend verifier apart from the C++ one is still to be used. Owned by [#28](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/28).

9. **Requirements are not mechanically tied to their evidence.** `docs-check` verifies links, pins and make targets, not that a requirement has a command that demonstrates it. Owned by [#26](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/26).

10. **Two research digests are incomplete**, as the research index says. Owned by [#33](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/33).

## What the numbers support

The Lucid measurements of the same revision: Bend 14.7 s and 665 s, C++ 1.45 s and 19.1 s, Lean OnBytes 5.8 s and 95.5 s, theorem-linked Lean 1,141 s (small and full-size, one thread). The kernels measured in the [Bend assessment](bend2-assessment.md) run at 4 to 5 times C, which bounds a list-free, closure-free port near 90 s at full size on that host; 16 cores scaled a fork-join tree 12 to 14 times. The [performance contract](../spec/performance.md) turns those two bounds into its targets. They are targets, not results.

## Not checked

- The sources were not read line by line. The review read the entry, the key stage, the fold module, the field kernels and the native shim, and searched the rest.
- No fuzzing at full size, on Linux, or on the hybrid build.
- The clipped-gap full-size fixture and the JS lane of the whole call were not run.
- The catalogs generated from the reference planner were not compared with a fresh export (`make plans-reproduce` does that).
- No claim here says the verifier is sound. A reviewer's 1,400 refused inputs are evidence about those inputs.

## Reproduce

```sh
make bootstrap upstream standalone oracle
make fuzz                                              # 64 cases per small fixture
python3 -B scripts/fuzz-differential.py -n 400 --seed review-1   # the recorded campaign
```
