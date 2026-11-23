# Porting FlashProve H821 to Bend 2

> Status: frozen

Snapshot of the pinned source and seven research digests recovered from the first implementation session. Paths in the source column are relative to the pinned FlashProve checkout. The incomplete parameter digest ends in the layout calculations. The C++ investigator left no standalone report. The upstream source map supplies that part of the index.

| Investigation | Finding to carry into implementation | Primary source |
|---|---|---|
| Format core | Field elements occupy eight little-endian bytes per base coordinate. Reject out-of-range encodings before arithmetic. The H hash labels include a domain, tree and index. Its starting digest occupies the salt and personalization fields. K and TK use the compression function differently. | [Format §§2–7, 12.6](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md) |
| Verifier order | All three stages compare the commitment constructed from the configuration, anchor, seeds and stored answers with the ID supplied by the caller. A whole call also has closing conditions on security accounting, policy and scope. | [Format §§13–15](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#13-what-a-verifier-does-in-order) |
| Parameters, key, leaf and proof | The configuration and plan fix counts and ordering. Sampling changes the number of opening bytes consumed. A full-size table can have code length 2³², so a leaf's index can exceed a U32. Every raw byte of the configuration participates in the commitment. | [Parameter derivation](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/08-parameters.md) · [Key and leaf](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/09-key-and-leaf-files.md) · [Proof](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/10-proof-file.md) |
| Shared sub-proofs | Lookup constraints, masked sumchecks, row batching, range checks and weight claims bind authenticated values to equations. The request stage assembles these checks outside the generic protocol blocks. | [Shared machinery](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/11-1-machinery.md) · [Weight claims](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/11-5-weights-in-the-table.md) |
| Segment checks | A small stored request has two layer groups, each with a feed-forward and an attention segment, then an output head. The verifier constructs the coefficients for every family of claims and links values across the segments. | [Feed-forward](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/11-2-feed-forward-segment.md) · [Attention](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/11-3-attention-segment.md) · [Output head](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/11-4-output-head.md) |
| Lean verifier | The theorem-linked execution through Lean and the standalone functional verifier on bytes are separate baselines. OnBytes is useful for the byte-level port and documents differences from C++. | [Theorem-linked runner](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/tools/lean-verify/README.md) · [OnBytes limits and timings](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/OnBytes/LIMITS.md) |
| Corpus and oracle | The four stored proofs use synthetic weights, two sizes and two policies. The CPU verifier accepts all four. The upstream altered-copy tables cover byte encoding, authenticated files, request binding and policy. The toy false files have a different format. | [Examples](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/README.md) · [Altered copies](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/rejected-proofs/README.md) |

## Where to trace a mismatch

| First divergence | Reference |
|---|---|
| A domain byte, hash or field value | Run the upstream `docs/format/format_rules.py` and compare with the committed `format-vectors.txt`. The `known_answers` folder under `verifier/tests` holds hash-specific vectors. |
| A configuration-dependent round count or shape | Use `cp_verify -plan` with the arguments in `verifier/docs/plan-data.md`. It produces machine-readable shapes and field positions. After the first sampled positions, some offsets are upper bounds. |
| A chain seal, query or opening | The upstream test `verifier/tests/walker_on_a_world_test.py` drives the independent reader over a small real proof. Its walk checks framing and hashes. The protocol's arithmetic constraints still need the verifier. |
| A segment equation | Start with the corresponding subsection of §11, then locate the matching C++ implementation using `verifier/docs/source-map.md`. Use `vf_subproof_engine.h` for the shared checks and the segment-specific check files for model equations. |
| Whole-call result | Compare the actual exit code, four closing lines and caller-supplied inputs with the example README. A passing stage, valid ID or plausible stdout fragment provides insufficient evidence. |

## Baselines recovered from the first run

The first agent's macOS arm64 experiment compiled the pinned C++ sources directly with Apple Clang 21. Its small proofs took 0.63–0.65 s and its full-size proofs 7.90–8.11 s with default threading. At full size the reported maximum resident set was roughly 3.7–4.0 GiB. The three verifier stages have separate processes, and this number does not measure their aggregate live memory. These figures describe that build and machine. The same scratchpad records successful refusal of 122 altered sets across four tables.

Upstream reported 19–39 minutes for theorem-linked Lean verification and 112–121 seconds for the compiled OnBytes path at full size. Its comparable C++ run took 25 seconds. Hardware, configuration, build and input set matter for both comparisons. A same-host end-to-end run is required to attribute a speed difference to Bend. [Lean runner measurements](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/tools/lean-verify/README.md) · [OnBytes results](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/OnBytes/LIMITS.md#tests)

The Bend spikes measured Goldilocks multiplication, BLAKE2b compression, an independent hash tree and file ingestion. The independent tree demonstrated parallelism on that workload. Whole-proof timing includes serial transcript dependencies and memory-intensive model checks. [Bend assessment and reproducible spikes](bend2-assessment.md)

## Archived working notes

The original notes retain line references, calculations, potential discrepancies and experimentation logs. Temporary paths were normalized. Check an inference against its cited upstream rule before implementing it.

- [01 — Format core: FORMAT.md sections 1–7, `format_rules.py`, `format-vectors.txt`](notes/01-format-core.md)
- [02 — What the verifier does, in order; its interface; its results](notes/02-verifier-order-interface.md)
- [03 — Parameter file, derived quantities, key file, leaf file, proof file (FORMAT §8–§10)](notes/03-params-key-leaf-proof.md)
- [04 — The shared machinery of sub-proofs (FORMAT §11 head, §11.1, §11.5, protocol "tools", toy runs)](notes/04-subproof-machinery.md)
- [05 - Segment sub-proofs: feed-forward (11.2), attention (11.3), output head (11.4), and the integer model](notes/05-segment-subproofs.md)
- [07 — The Lean verifier: structure, cost, scope, and what is reusable for a port](notes/07-lean-verifier.md)
- [08 — Golden corpus and the `cp_verify` oracle](notes/08-corpus-and-oracle.md)
