# Assurance contract

> Status: living

Passing the four genuine proofs and refusing the published altered copies shows that the verifier agrees with `cp_verify` on those inputs. It does not show that every check is present, that every check is tested, or that a later change cannot remove one unnoticed. This page states what the repository must keep demonstrating beyond the [verification contract](verifier.md). The reasoning and the first measurements are in the [independent review](../research/independent-review.md).

## What agreement on honest proofs does and does not show

A segment's claims reach the verifier as one random linear combination, which a proximity test closes against a masked message. A verifier that forms a wrong coefficient fails honest proofs with overwhelming probability, because the mask is random and the prover made its sums for the right coefficient. The exception is a coefficient on data that is zero by construction, such as padding. So the four accepts constrain almost every algebraic coefficient the verifier builds. This is an argument, not a theorem of this repository. The accepts constrain none of the checks that stand apart from that equation: canonical encodings, bounds and counts, proof-of-work tests, openings of trees, the comparison of the next token, the conditions of FORMAT 13.7, and the sampled values at which FORMAT 13.9 lets no verifier accept. Those are shown only by inputs that violate them, or by removing the check and watching a test fail.

## Requirements

| Requirement | Obligation | Evidence required for completion |
|---|---|---|
| **REQ-ASSURE-1** | On every input, if the standalone verifier accepts then `cp_verify` at the pinned revision accepts. | `make fuzz` on both small fixtures in CI, and a recorded campaign of at least 10,000 cases per fixture family, full-size included, with seeds. One unsound case fails the run. |
| **REQ-ASSURE-2** | Every refusal the verifier can issue is exercised: for each rejection point in the standalone path, some test fails when that point is disabled. | A mutation run that disables one rejection point at a time and reruns the conformance targets, with the list of survivors. A survivor is closed by a new test or by a written reason why no input can reach it. |
| **REQ-ASSURE-3** | Each requirement of `docs/spec` names the command that demonstrates it, the command exists, and CI or a documented extended job runs it. | A `docs-check` rule over the requirement tables, failing on a requirement without a runnable command. |
| **REQ-ASSURE-4** | A refusal names the stage and file it came from, and maps to one of the reference's classes (`key-refused`, `entry-refused`, `proof-refused`, or the name of a test on the public files or the caller's inputs). | The fuzz campaign's rejection names, grouped by the altered file, show no key-stage name for a fault in a proof or leaf file. |
| **REQ-ASSURE-5** | Laws state the arithmetic kernels' meaning (limb arithmetic, reduction modulo p, extension product, canonical decoding) and `bend` proves them. | `LAWS.bend` and `PROOF.bend` at the repository root, `ALL PROOFS CHECK` in CI, and a note on what `--verdict` accepts of them. |

## Rules

1. A new check arrives with an input that it alone refuses, or with a fixed-transcript case that reaches it, as in `make request-claims-test`.
2. A disagreement with the reference in either direction is a finding: record the seed, the index and both last lines in the issue before changing code.
3. Fuzz seeds that found a defect become permanent regression cases.
4. Laws are stated in `LAWS.bend` by the maintainer and proved in `PROOF.bend`; a proof never edits the law it proves.
