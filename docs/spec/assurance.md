# Assurance contract

> Status: living

The central conformance requirement is one-way. For the same input bytes, trusted commitment and caller policy, every acceptance by standalone Bend must also be an acceptance by the pinned C++ verifier. A passing test establishes that comparison for the inputs it exercised. The [verification contract](verifier.md) defines what an acceptance claims.

## What the tests establish

All four published proofs passed in standalone Bend and matched their expected closing records. Native Lean OnBytes also agreed on the four records' claim, commitment, coverage and policy. Changing one bit halfway through the small exact-match proof made Bend, OnBytes and C++ all refuse it. A separate fresh proof exercises a new commitment under a supported configuration. [Conformance run](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/14#issuecomment-7126795221) · [OnBytes and one-bit comparison](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/28#issuecomment-7126358874) · [Fresh-proof record](../research/fresh-proof.md)

An honest proof exercises many equations at once. For example, the verifier combines a segment's row claims with transcript challenges and checks the result against a masked message. An incorrect coefficient can break that check. A coefficient multiplying zero padding, or code on a branch the fixture never visits, can pass unnoticed. An honest proof also gives the expected answer to a test the implementation might have omitted altogether. [Independent review](../research/independent-review.md)

Use two kinds of negative tests. Changing input bytes exercises the parser, public-file checks, proof of work and Merkle openings. A change to proof bytes often stops at an early transcript check. To exercise a later equation, `make request-claims-test` holds a genuine transcript fixed and changes a target or coefficient at the equation itself. Both kinds of tests matter for the closing conditions in format §13.7 and the exceptional challenge values in §13.9. [Fixed-transcript tests](../../scripts/test-request-claims.py) · [Format §13](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#13-what-a-verifier-does-in-order)

## What has been formally checked

Bend's independent kernel accepted the translated definitions of the optimized Goldilocks arithmetic, cubic extension and standalone entry at revision `ca1297c` with `--verdict`. The standalone entry also passed after the sparse U3 change at `d623abe`. For example, the declared type of `E3.mul` requires it to return an element with three coefficients. The stronger property says that the three coefficients equal the polynomial product modulo the Goldilocks prime and `X³ − 2`. Proving laws of that kind is the work of REQ-ASSURE-5. [Recorded kernel commands and verdicts](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/28#issuecomment-7136403428) · [Sparse U3 kernel check](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/28#issuecomment-7157638941)

Upstream proves soundness for its Lean verifier under a random oracle and assumptions on the public setup. Its exact-match result concerns the integer model's top token. Under clipped gap, the corresponding result concerns compliance with the chosen policy. Upstream distinguishes the theorem from the parser and compiled run and from its separate OnBytes implementation. To transfer that theorem to Bend would require proving that Bend acceptance implies Lean acceptance for the same inputs, commitment, covered positions, policy and hash oracle. That correspondence remains open. [Upstream theorem and premises](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md) · [OnBytes](../research/onbytes.md)

## Requirements

| Requirement | Obligation | Evidence required for completion |
|---|---|---|
| **REQ-ASSURE-1** | For every input, standalone acceptance implies acceptance by the pinned `cp_verify`. | Run `make fuzz` on both small fixtures in CI. Record seeds and results for at least 10,000 cases per fixture family, including both full-size families. Fail on any Bend acceptance without a reference acceptance. This campaign tests the implication on sampled inputs. |
| **REQ-ASSURE-2** | Each reachable rejection point in the standalone verifier has a test that fails when that check is disabled. | Disable one check at a time and rerun the conformance tests. For each surviving change, supply a test that catches it or show why the rejection is unreachable. |
| **REQ-ASSURE-3** | Each requirement in `docs/spec` names an existing command that CI or a documented extended job runs. | Extend `make docs-check` to fail on a requirement without a runnable command. |
| **REQ-ASSURE-4** | Each refusal identifies its stage and file and maps to an upstream class, such as `key-refused`, `entry-refused`, `proof-refused` or a named public-input check. | Group fuzz results by altered file. Require zero proof or leaf faults misreported as key-stage faults. |
| **REQ-ASSURE-5** | State and prove what the limb operations, modular reduction, extension product and canonical decoder compute. | State the laws in `LAWS.bend` and prove them in `PROOF.bend`. Require `ALL PROOFS CHECK` in CI and record which laws the independent kernel accepts with `--verdict`. |

When adding a check, supply an input that reaches that check and fails there, or a fixed-transcript case that changes only its target. If the two verifiers disagree in either direction, record the seed, case index, exit codes and closing lines before changing code. Keep any seed that identifies a defect as a regression test. For formal proofs, a maintainer sets the law in `LAWS.bend`. Keep that statement fixed while constructing its proof in `PROOF.bend`. [Assurance issues and dependencies](../plan/implementation.md)
