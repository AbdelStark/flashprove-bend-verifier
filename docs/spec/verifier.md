# Verification contract

> Status: living

The standalone CPU executable, `build/verify-bend`, checks FlashProve H821 proofs over field 2 (Goldilocks). It accepts four public configurations, one for each combination of model size and token policy in the published examples. For each configuration the implementation must check the key, leaf, request and proof supplied with the call. The unmodified upstream C++ executable, `cp_verify`, serves as the reference in our tests. [Protocol revision](../../upstream.lock) · [Implementation plan](../plan/implementation.md)

## What a proof claims

The claim concerns the committed **integer model** evaluated on a window of `T` token IDs. Its intermediate values must stay within the ranges and tables checked by the segment proofs. The caller specifies which predictions to check. The entire window is an input to the run, even when the caller asks about a single output. The protocol works with token IDs and integer logits. A floating-point checkpoint, a sampler and a text tokenizer would each require a separate correspondence to this computation. [Upstream statement of scope](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/limits.md#what-a-yes-covers)

The request consists of `T` tokens followed by two positions `r` and `e`, all little-endian 32-bit words, with `0 ≤ r < e ≤ T`. The covered positions are the half-open interval `[r, e)`. For each covered position `t` below `T − 1`, compare the prediction with request token `t + 1`. At the final position `T − 1`, compare it with the separate next-token word `y` if `e = T`. When `e < T`, the caller supplies zero for `y` and the verdict covers only tokens inside the request. All token IDs must be in the vocabulary. [Format §12.2](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#122-the-callers-two-files)

- Under **exact match**, each covered token must have the largest integer logit at its position. Ties go to the lowest vocabulary index.
- Under **clipped gap**, let `n` be the number of covered tokens inside the request. Each has a cost derived from its logit gap, including the tie break, plus `2^sh`. The sum of the `n` costs after clipping each to `C` must be at most `n × theta`. At most `cap` of the original costs may exceed `C`. A token other than the top choice can satisfy these bounds.
- Whenever `e = T`, the next token must be the top choice under either policy. It has no cost. With `r = T − 1` the claim covers that token alone.

## What the caller trusts

Supply a commitment ID obtained from a source that vouches for the intended model. Build the request and next-token file from the tokens you wish to verify. To allow clipped-gap checks on request tokens, choose the policy and its five numbers (`C, theta, cap, s, sh`) independently of the proof and pass them with `-policy`. The verifier compares them with the configuration. Keep every input immutable for the duration of the call. The ID and policy shipped with each example let readers replay that example. [Format §12.5](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#125-the-acceptance-policy) · [Upstream acceptance rule](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/verifying.md#when-to-accept)

The release binds its public geometry and seven chain plans to a digest of the configuration bytes. Bend authenticates the four public tables against their configured digests. Verification then proceeds through three stages. [Public plan decision](../adr/public-plans.md) · [Standalone entry](../../src/standalone.bend)

1. The **key** stage checks the anchor commitment and its proof. The verifier reconstructs the ID from the configuration and key material and compares it with the caller's ID.
2. The **leaf** stage checks the leaf selected by the proof header, including its link to the anchor.
3. The **request** stage checks the feed-forward, attention and output-head relations, the covered outputs and the claims linking the computation to the selected weight table.

## Acceptance and failures

Require exit status zero, the expected closing verdict and a complete `result-v1` record. Compare the commitment ID, `claim`, `r`, `e`, `T`, `tokens`, `y` and policy with the caller's inputs. Check the stage and accounting fields against the upstream output contract. A next-token-only proof under a clipped-gap configuration can end in `YES` with `claim=next-token` and `tokens=none`. A clipped-gap proof that covers request tokens ends in `WITHIN LIMITS`. Record the build identity alongside the verdict. [Output contract](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/output.md)

The `bits=128` field gives the target used to check each round's error accounting, including credited proof of work. The record gives the weakest round with and without that credit. Binding the weights also relies on the upstream coding-theoretic assumption printed in the `commitment:` line. A security bound for the whole deployed verifier would have to account for all rounds, the hash model, the setup and the implementation. [Upstream accounting limits](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/limits.md#the-soundness-figure) · [Formal assurance](assurance.md)

Treat malformed or unsupported inputs, a policy mismatch, any failed or incomplete stage, a timeout, a signal or truncated output as non-acceptance. Preserve the distinction between a proof refusal and an execution failure when reporting a result. The format permits some differences in failure order and diagnostic names. [Format §13.7](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#137-from-the-stages-to-the-result)

## Requirements and test evidence

The pinned format and its companion files for §§8–11 define the wire rules. Where the format delegates behavior to code, cite the pinned implementation, capture a differential case and record any known divergence. Format §17 lists known discrepancies. Section 18 describes the assumptions made when a verifier takes plans or shapes as inputs. [Format](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format) · [Implementation map](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/source-map.md)

| Requirement | Obligation | Evidence |
|---|---|---|
| **REQ-E2E-1** | Build the unmodified reference verifier at the pin. Verify fixture checksums and use its whole-call interface. | `make standalone-extended` and `make fuzz` run the unmodified `cp_verify` beside Bend on the same inputs and compare exit codes and verdicts. Record the build identity. |
| **REQ-INPUT-1** | Bound parsing and allocation before using file-controlled lengths. Apply the grammar and arithmetic and shape checks in §§8–10, 12 and 13.8. Reconstruct and compare the ID. | `make public-input-test` compares public intermediates. Keep cases for short and trailing input, unsupported versions, noncanonical elements, mismatched ID or policy, and out-of-range positions or tokens. |
| **REQ-TRANSCRIPT-1** | Match both hash constructions, label encodings, canonical base and extension field arithmetic, challenge sampling, work nonces, tree domains and authentication paths. Consume exactly the planned bytes. | Run vectors and independent known answers on both lanes with `make test` and `make test-native`. Compare real chain intermediates and refuse changes to a nonce, path, leaf or encoding. |
| **REQ-PLAN-1** | Bind shapes, round order, counts, codes, error accounting and sizes to the configuration. Check wide arithmetic and the digests of all four public tables. | `make plans-reproduce`, `make plan-test` and `make public-input-test` compare public data across all four profiles and exercise changes to its contents and associations. |
| **REQ-COMMIT-1** | Read the key and leaf to EOF. Check their protocols, equations and openings, and bind the selected leaf through the anchor to the expected ID. | `make stages-full` compares intermediate evidence. `make standalone-extended` exercises damaged key or leaf data, changed stored answers and a substituted leaf. |
| **REQ-ENGINE-1** | Apply the shared sub-proof checks in §§11.1, 11.5 and 13.9, including masking, row claims, padding, weight placement, counts and final equations on authenticated data. | Compare known values for sumchecks, lookups, smallness, fold and merge. Exercise changed claims, masks, padding and endpoints with the relevant unit cases and `make request-claims-test`. |
| **REQ-SEGMENT-1** | Build the feed-forward, attention and output-head constraints of §§11.2–11.4. Check the links between segments, the outer request chains, the shared batch and its binding tree. | `make stages-full` checks intermediate values for all three segment families under both policies. Exercise changed witnesses, links and output claims. |
| **REQ-ACCEPT-1** | Require all three stages, the caller's ID, actual coverage and policy, and all 14 conditions of §13.7. Emit a verdict only when verification completes. | `make standalone-full` runs all four published sets with no external verifier executable. Run the rejection suites on bad input and failed stages, including missing files and unsupported profiles. |
| **REQ-PERF-1** | Measure whole calls and identify the executable and stages timed. | `make benchmark-standalone` records checked runs. Report pins, fixtures, host, compilers and flags, worker settings, warmups, repeated times, peak memory method and verdict. See the [performance contract](performance.md). |

The §13.7 conditions include the commitment, error-bound interpretation, target, commitment-stage bounds and work cap. They also fix the model profile, token source, clamps, norm shifts, public table digests, policy, parameter form, distinct code shapes and number of record answers. Several follow from admitting only the four reviewed configurations. Expanding the configuration set requires establishing them for the new files.

## Conformance corpus

The published examples contain proofs over synthetic weights at two model sizes. Token indices in the table are zero-based and inclusive. Each row also checks the commitment, proof-of-work and result records against the fixture's expected output. [Upstream examples](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples) · [Standalone test](../../scripts/standalone-test.py)

| Fixture | Request tokens | Next token | Expected closing verdict |
|---|---|---|---|
| `accepted-proof` | 61–63 | Yes | `YES` |
| `accepted-proof-clipped-gap` | 16–47 | No | `WITHIN LIMITS: clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8` |
| `full-size` | 24–1023 | Yes | `YES` |
| `full-size-clipped-gap` | 24–1023 | Yes | `WITHIN LIMITS: clipped-gap C=25856 theta=512 cap=1 s=15 sh=8` |

A separate run generated a fresh commitment and a next-token-only proof for the small synthetic model. Both C++ and standalone Bend accepted token 301. The run record includes the proof digest and all four closing lines. [Fresh H100 proof](../research/fresh-proof.md)

For each new component, include a case at its verification boundary. The altered-copy suites cover proof, key, leaf, request, token, configuration and caller ID. A transcript walk exercises the parser and openings. A whole call must also close the algebraic equations and pass the policy and coverage checks. [Assurance contract](assurance.md) · [Upstream theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md)
