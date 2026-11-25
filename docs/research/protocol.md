# Protocol source map

> Status: living

The standalone entry reads the caller's files, checks the public statement, and runs the key, leaf and request stages. If two verifiers disagree, compare the first value they compute differently. The closing line alone cannot tell you whether they disagreed on the request, a field element or an authenticated opening. [Bend entry](../../src/standalone.bend) · [Upstream verifier order](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#13-what-a-verifier-does-in-order)

## From bytes to a verdict

| Question | Where to read | How to check |
| --- | --- | --- |
| Which configurations, rounds and table shapes are allowed? | [Public plan decision](../adr/public-plans.md), [Bend reader](../../src/plan.bend), [upstream parameter derivation](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/08-parameters.md) | `make plans-reproduce` compares the exported parameters byte for byte. `make plan-test` checks the reader on genuine and changed plans. |
| Which tokens and policy did the caller ask about? | [Statement and trust boundary](../spec/verifier.md), [statement reader](../../src/policy_statement.bend), [output fields](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/output.md) | `make public-input-test` checks public intermediates and layout across the four configurations. |
| Where does a transcript or Merkle path first differ? | [Fiat–Shamir rounds](../../src/round_io.bend), [openings](../../src/opening_bytes.bend), [upstream format vectors](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/format-vectors.txt) | `make test-native` runs the arithmetic, hash, transcript and opening vectors. The upstream planner describes the chain layout. Sampled positions determine the actual opening lengths. [Planner output](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/plan-data.md) |
| How does the selected leaf bind to the caller's model commitment? | [Key transcript](../../src/key_stage.bend), [leaf algebra](../../src/leaf_check.bend), [key and leaf format](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/09-key-and-leaf-files.md) | `make stages-test` compares the small-fixture stage evidence, including a known leaf-link equation. |
| Which model operation does the request prove? | [Request stage](../../src/request_stage.bend), [feed-forward](../../src/segment_ff.bend), [attention](../../src/segment_attention.bend), [output head](../../src/segment_head.bend), [proof-file format](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/10-proof-file.md) | `make stages-full` checks the intermediate projections on both model sizes. `make request-claims-test` changes individual algebraic claims while holding the transcript fixed. |
| Does the complete call agree with the reference? | [Conformance corpus](../spec/verifier.md#conformance-corpus), [upstream reference code map](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/source-map.md) | `make standalone-full` checks the four published outcomes. `make standalone-extended` checks refusals. |

## Measurement records

The [request projection report](request-projection.md) compares the current Bend verifier with native Lean OnBytes after independently selecting workers for each CPU. It also accounts for time across a complete request. The [sparse U3 report](sparse-u3.md) records the previous release, including a breakdown of its 25 request segments. The [earlier CPU optimization report](cpu-optimization.md) pairs standalone Bend with compiled Lean OnBytes on an Apple M4 Max and a Lucid Xeon. It includes all samples for the earlier and optimized builds and the profiles that motivated the change. The [original M4 Max benchmark](m4-standalone.md) records the performance before this work. The [Lucid runs](lucid.md) include C++ and the theorem-linked Lean command. The [initial Bend experiments](bend2-assessment.md) time individual kernels and a fork-join tree. The [fresh-proof record](fresh-proof.md) follows one request from a new commitment on an H100 through both CPU verifiers.

## Working notes from the original port

The November 2026 notes record the source lines, calculations and experiments used during the port. They refer to the [pinned upstream checkout](../../upstream.lock). Use the format and the executable tests above to resolve a discrepancy.

- [Wire format, hash domains and arithmetic](notes/01-format-core.md)
- [Verifier order, interface and results](notes/02-verifier-order-interface.md)
- [Parameter derivations and layout](notes/03-params-key-leaf-proof.md). The key, leaf and request rows above supersede this note for the file readers.
- [Shared sub-proofs and weight claims](notes/04-subproof-machinery.md)
- [Feed-forward, attention and output-head equations](notes/05-segment-subproofs.md)
- [Lean verifier structure and execution](notes/07-lean-verifier.md)
- [Fixture corpus and C++ oracle](notes/08-corpus-and-oracle.md)

For the C++ architecture and cost questions originally assigned to a separate digest, use the [upstream source map](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/source-map.md#the-files) and the [measured C++ whole calls](lucid.md#independent-bend-verification). The published stack samples profile Bend. [Original research index](https://github.com/AbdelStark/fv-flashprove-bend-verifier/blob/c1989750b5f90bda5e63ecd79d07126790914d9b/docs/research/protocol.md)
