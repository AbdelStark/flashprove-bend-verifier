# Assurance contract

> Status: living

The central requirement runs one way. For the same input bytes, trusted commitment and caller policy, every proof that standalone Bend accepts must also be accepted by the pinned C++ verifier. A passing test establishes this only for the inputs it ran. The [verification contract](verifier.md) defines what an acceptance claims.

## What the tests establish

All four published proofs pass in standalone Bend and match their expected closing records. Native Lean OnBytes agrees with those records on the claim, commitment, coverage and policy. Flipping one bit halfway through the small exact-match proof makes Bend, OnBytes and C++ all refuse it. A separate fresh proof exercises a new commitment under a supported configuration. [Conformance run](https://github.com/AbdelStark/flashprove-bend-verifier/issues/14#issuecomment-7126795221) · [OnBytes and one-bit comparison](https://github.com/AbdelStark/flashprove-bend-verifier/issues/28#issuecomment-7126358874) · [Fresh-proof record](../research/fresh-proof.md)

Passing honest proofs is weaker evidence than it looks. An honest proof exercises many equations at once. For example, the verifier combines a segment's row claims with transcript challenges and checks the result against a masked message. A wrong coefficient can break that check. But a coefficient that multiplies zero padding can pass unnoticed, and so can code on a branch the fixture never reaches. An honest proof also passes a check the implementation forgot to make.

So the negative tests come in two kinds:

- **Changed input bytes** exercise the parser, the public-file checks, proof of work and Merkle openings. A change to proof bytes, though, usually stops at an early transcript check.
- **Fixed-transcript tests** reach the later equations. `make request-claims-test` keeps a genuine transcript and changes one target or coefficient at the equation itself.

Both kinds matter for the closing conditions in format §13.7 and the exceptional challenge values in §13.9. [Fixed-transcript tests](../../scripts/test-request-claims.py) · [Format §13](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#13-what-a-verifier-does-in-order)

## What has been formally checked

Bend ships an independent kernel that rechecks translated definitions against their declared types (`bend … --verdict`). It accepted the Goldilocks arithmetic, the cubic extension and the standalone entry at `ca1297c`, the standalone entry again after the sparse U3 change at `d623abe`, the standalone definitions at `9d00a32`, the revision behind the Xeon measurements, and the standalone definitions of `b4a8c4b`, the latest measured revision, with one unused definition removed. That last check ran on an M4 Max on 2026-11-26 with Lean v4.34.0, took 96 s and peaked at 8.4 GiB. Those sources are the ones in `05b2268`, where the full conformance suite was also rerun. [Rerun](../research/rerun-2026-11-26.md#conformance) [Kernel commands and verdicts](https://github.com/AbdelStark/flashprove-bend-verifier/issues/28#issuecomment-7136403428) · [Sparse U3 check](https://github.com/AbdelStark/flashprove-bend-verifier/issues/28#issuecomment-7157638941) · [Check at `9d00a32`](../research/request-projection.md#checking-the-verification-path)

A type is a weak statement. The declared type of `E3.mul` says it returns an element with three coefficients. The property we actually want says those coefficients equal the polynomial product modulo the Goldilocks prime and `X³ − 2`. Proving laws of that kind is REQ-ASSURE-5.

Upstream proves soundness for its Lean verifier, under a random oracle and assumptions about the public setup. Under exact match, the result is about the integer model's top token. Under clipped gap, it is about compliance with the chosen policy. Upstream keeps the theorem separate from the parser, from the compiled run and from the OnBytes implementation. To carry that theorem over to Bend, one would have to prove that Bend acceptance implies Lean acceptance for the same inputs, commitment, covered positions, policy and hash oracle. That proof does not exist yet. [Upstream theorem and premises](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md) · [OnBytes](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/OnBytes/README.md)

## Requirements

| Requirement | Obligation | Evidence required for completion | Status |
|---|---|---|---|
| **REQ-ASSURE-1** | For every input, standalone acceptance implies acceptance by the pinned `cp_verify`. | Run `make fuzz` on both small fixtures in CI. Record seeds and results for at least 10,000 cases per fixture family, including both full-size families. Fail on any Bend acceptance without a reference acceptance. The campaign tests the implication on sampled inputs. | CI fuzzes 32 cases per commit. The long campaign is open. [#24](https://github.com/AbdelStark/flashprove-bend-verifier/issues/24) |
| **REQ-ASSURE-2** | Each reachable rejection point in the standalone verifier has a test that fails when that check is disabled. | Disable one check at a time and rerun the conformance tests. For each change that survives, add a test that catches it or show why the rejection is unreachable. | Open. [#25](https://github.com/AbdelStark/flashprove-bend-verifier/issues/25) |
| **REQ-ASSURE-3** | Each requirement in `docs/spec` names an existing command that CI or a documented extended job runs. | Extend `make docs-check` to fail on a requirement without a runnable command. | Open. [#26](https://github.com/AbdelStark/flashprove-bend-verifier/issues/26) |
| **REQ-ASSURE-4** | Each refusal names its stage and file and maps to an upstream class, such as `key-refused`, `entry-refused`, `proof-refused` or a named public-input check. | Group fuzz results by altered file. Require that no proof or leaf fault is reported as a key-stage fault. | Open. [#27](https://github.com/AbdelStark/flashprove-bend-verifier/issues/27) |
| **REQ-ASSURE-5** | State and prove what the limb operations, modular reduction, extension product and canonical decoder compute. | State the laws in `LAWS.bend` and prove them in `PROOF.bend`. Require `ALL PROOFS CHECK` in CI and record which laws the independent kernel accepts with `--verdict`. | Open. [#28](https://github.com/AbdelStark/flashprove-bend-verifier/issues/28) |

When you add a check, supply an input that reaches it and fails there, or a fixed-transcript case that changes only its target. If the two verifiers disagree in either direction, record the seed, case index, exit codes and closing lines before you change any code. Keep every seed that exposed a defect as a regression test. For formal proofs, a maintainer writes the law in `LAWS.bend`. That statement then stays fixed while its proof is built in `PROOF.bend`. [Assurance issues and dependencies](../plan/implementation.md)
