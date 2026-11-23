# Verification contract

> Status: living

This contract targets H821, field 2, at the revision in [upstream.lock](../../upstream.lock). The experiment has two milestones. The hybrid milestone runs a Bend cryptographic primitive inside a complete verification call and compares its results to an independently built, unmodified oracle. The independent milestone moves every acceptance decision into Bend. A comparison of those implementations measures different amounts of Bend code. [Implementation plan](../plan/implementation.md)

## Statement and trust boundary

A whole call takes the configuration directory, key directory, request bytes, four-byte next-token file, proof file and caller-selected commitment ID. The caller also supplies the expected acceptance policy if clipped-gap is allowed. Verification is over one consistent set of bytes. A service must keep its trusted ID and expected policy outside the prover-controlled files and ensure all stages see immutable inputs for the duration of a call. The bundled ID and inputs demonstrate reproducibility of the public example.

The request carries T tokens and the positions r and e as little-endian U32 words. For positions t in [r, e), the checked token is request[t+1] if t < T−1, or y if t = T−1. When the range excludes the next token, the format requires the neutral token file. Validate bounds, vocabulary, exact lengths and the complete request binding. In the exact-match policy a checked token is the committed integer model's first choice with the specified tie rule. In clipped-gap mode the covered request tokens satisfy the caller's named cost limits. At a checked final position the next token must still be the first choice.

## Requirements and test evidence

| Requirement | Obligation | Evidence required for completion |
|---|---|---|
| **REQ-E2E-1** | Build the C++ oracle from the pinned source, verify fixture checksums, use the whole-call interface. | Run the four stored accepted sets and refuse an altered proof. Record the upstream source identity and check the real exit status and expected output. |
| **REQ-KERNEL-1** | The hybrid must invoke checked, native-compiled Bend on the proof's cryptographic computation. A failed build or kernel self-test fails the run. | Independent known answers plus the real proof matrix. Verify the link or call path. Identify the hybrid build separately from the oracle. |
| **REQ-INPUT-1** | Bound parsing and allocation before consuming attacker-controlled lengths. Apply the pinned public-file grammar and arithmetic/shape checks of §§8–10, 12 and 13.8. Compare the reconstructed ID with the caller's ID. | Golden configuration and statement intermediates. Boundary/refusal tests for short or excess bytes, unsupported versions, noncanonical elements, wrong ID, range, token and policy. |
| **REQ-TRANSCRIPT-1** | Match both hash constructions, label encodings, canonical Goldilocks and extension arithmetic, challenge sampling, work nonces, tree domains and authentication paths. Consume exactly the planned bytes. | Pinned format vectors, independent differential kernel tests and known intermediate chains on a real proof. A modified nonce, path, leaf or encoding fails. |
| **REQ-PLAN-1** | Establish shapes, round order, counts, codes, per-round error accounting and sizes. Guard wide integer computations. Precomputed data needs an explicit trusted association with the full configuration and permitted scope. Authenticate all four public tables against their configured digests. | Compare canonical plan bytes, rounds, shapes and table digests on every supported profile. A changed plan/configuration association is refused. |
| **REQ-COMMIT-1** | Check key and leaf files to EOF, binding the selected leaf to the anchor and the expected commitment. Verify their protocols, equations and every opening. | Compare stage results and intermediate commitments across fixtures. Refuse altered key, leaf or stored answer and mismatched stages. |
| **REQ-ENGINE-1** | Apply all shared sub-proof checks of §§11.1, 11.5 and 13.9, including masking, row claims, padding and weight placement. Validate the counts and final equations that bind authenticated data. | Golden values for sumchecks, lookups, smallness, fold and merge, with changed claim, mask, padding and endpoint cases. |
| **REQ-SEGMENT-1** | Construct every feed-forward, attention and output-head constraint of §§11.2–11.4. Link each segment to its neighbors and the outer request chains, including the shared batch and its binding tree. | Compare G, A and H intermediates and final coverage under both policies. A changed segment witness, link or output claim fails. |
| **REQ-ACCEPT-1** | Require successful key, leaf and request checks, the caller's ID, actual coverage, policy and all 14 conditions of §13.7. Distinguish exact and bounded-cost acceptance. Any unsupported or incomplete verification yields a non-accepting outcome. | Run all four genuine fixtures and pinned applicable rejection suites through the independent Bend path with the C++ checker absent. Demonstrate rejection on bad input, failed stage, unsupported profile and missing input. |
| **REQ-PERF-1** | Measure whole calls and identify which implementation and stages performed them. | Publish fixture, hardware/OS, pin, compiler/flags, thread count, repeated wall times, warmup, peak memory method and verdict for each comparison. |

The source of truth for canonical bytes and required checks is the pinned format, including its §8–§11 companion files. For obligations the format explicitly delegates to code, cite the pinned implementation, capture a differential case and record any known divergence. §17 identifies differences already known upstream. §18 identifies assumptions an independent implementation makes if it accepts plans and shapes as input. [Format](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format) · [Implementation map](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/source-map.md)

## Acceptance and failures

The result binds the ID, verified leaf, request coverage, next-token coverage, policy, verification stages, target bits and accounting. A cp_verify-compatible consumer checks the actual exit code, closing verdict and the matching result-v1 fields. Record the source identity for the actual build. Implementations may give different rejection names where the format permits different check order. Preserve the distinction between malformed input, policy mismatch, unsupported settings and execution failure in diagnostics. A signal, timeout, truncated output, partial stage or missing file can never count as success. [Output contract](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/output.md)

Closing conditions cover a caller-named ID, the target security accounting, allowed error-bound reading, commitment-stage bounds, maximum work bits, whole-model profile, token source, clamps, norm shifts, table digests, admissible caller policy, standard parameter form, distinct code shapes and the required number of record answers. The format's full conditions, exceptions and table of parameter values govern the implementation. [Format §13.7](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#137-from-the-stages-to-the-result)

## Conformance corpus

| Fixture | Coverage | Expected closing verdict |
|---|---|---|
| accepted-proof | Small, exact | YES |
| accepted-proof-clipped-gap | Small, bounded cost | WITHIN LIMITS: clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8 |
| full-size | Full-size, exact | YES |
| full-size-clipped-gap | Full-size, bounded cost | WITHIN LIMITS: clipped-gap C=25856 theta=512 cap=1 s=15 sh=8 |

The altered-copy suites cover corrupted proof, key, leaf, request, token file, configuration and caller ID. Add boundary-specific unit cases for every ported component. Format walks validate transcripts and openings, while the whole call additionally enforces algebraic constraints and closing conditions. The Lean theorem applies to its specified verifier and hypotheses. Port conformance evidence consists of executable comparisons and tests. [Upstream examples](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples) · [Lean theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md)
