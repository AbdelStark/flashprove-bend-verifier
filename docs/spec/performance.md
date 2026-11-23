# Performance contract

> Status: living

The standalone verifier is correct on every fixture and slow. This page fixes how its speed is measured, what it must reach, and what a speed change may never alter. The correctness requirements stay in the [verification contract](verifier.md); the measurements behind the numbers here are in the [independent review](../research/independent-review.md) and the [Lucid results](../research/lucid.md).

## Where the time goes today

Measured on the standalone build of `f82965b`, one thread, exact-match fixtures.

| Quantity | Small | Full-size | Source |
|---|---:|---:|---|
| Bend standalone, median wall | 14.7 s | 665.1 s | Lucid, Xeon 8480CL |
| C++ `cp_verify`, median wall | 1.45 s | 19.1 s | same host |
| Lean OnBytes, median wall | 5.8 s | 95.5 s | same host |
| Theorem-linked Lean, median wall | n/a | 1,141.3 s | same host |
| Bend peak resident memory | 0.84 GB | 11.6 GB | M4 Max; Lucid |
| Bend time relative to C++ | 10x | 35x | derived |

A stack sample of the full-size call splits the verifier's own CPU time as follows. The small call has the same shape.

| Share | Where | What it is |
|---:|---|---|
| 41% | `extension.product`, `sumcheck.mul` | field multiplication in the cubic extension |
| 28% | `term_drop`, `span_fade`, `rfc_wrap` | freeing and reference counting of list cells and boxed elements |
| 10% | closure application | `Bool.pick` over function values in `fold.deposit` and similar |
| 20% | `row_tensor.choice`, `fold.*`, `List.length`, `List.drop`, `Nat.pow`, `String.order` | list traversal and repeated lookups inside loops |
| under 1% | BLAKE2b | all hashing |

Three structural facts follow. The request stage is 84% of the small call (key 1.0 s, leaf and link 0.4 s, request 7.6 s on an M4 Max). The sources contain no parallel call, so 16 threads take as long as one. The field kernel alone, at the measured 4 to 5 times C, would put the full-size call near 90 s on the Lucid host; the other 570 s are data representation.

## Requirements

| Requirement | Obligation | Evidence required for completion |
|---|---|---|
| **REQ-PERF-2** | The verifier reports the wall time of the key, leaf and request stages on request, on the error stream, without changing standard output or the verdict. | A documented option prints one line per stage. The four closing lines are byte-identical with and without it. A make target writes a stack-sample summary for a named fixture. |
| **REQ-PERF-3** | On one thread the full-size exact-match call takes at most 8 times the C++ median measured in the same job, and its peak resident memory is at most 7 GB. | The [benchmark protocol](#measurement-protocol) on the Lucid host, three samples per program, with the stage lines of REQ-PERF-2. |
| **REQ-PERF-4** | On 16 threads the full-size exact-match call takes at most the one-thread C++ median measured in the same job. | The same protocol with the thread count recorded, plus the scaling table at 1, 2, 4, 8 and 16 threads. |
| **REQ-PAR-1** | The exit status and every line of standard output are identical at every thread count, for accepted and for refused inputs. When several checks fail, the reported one is the first in sequential order: key, then leaf, then request, and file order inside a stage. | All four fixtures, both altered-copy tables and `make fuzz` at 1 thread and at 16, compared byte for byte. |
| **REQ-PERF-5** | A change that slows the small exact-match call by more than a stated tolerance fails CI. | A checked-in budget, expressed as CPU time relative to `cp_verify` on the same runner, and a CI step that compares against it. |

The two budgets of REQ-PERF-3 and REQ-PERF-4 are engineering targets derived from the kernel bound above and from the 12 to 14 times scaling that Bend's fork-join showed on 16 cores in the [spikes](../research/bend2-assessment.md). Change them here, with the measurement that justifies the change, and nowhere else.

## Rules for a speed change

1. **Verdicts first.** Before and after, `make ci`, `make standalone-extended` and `make fuzz` pass, and the closing lines of the four fixtures are byte-identical. A faster verifier that accepts one more input is a defect, whatever it gains.
2. **Measure, then change.** A pull request names the row of the profile it targets and reports the same measurement before and after. A change with no measured gain on a whole call is reverted.
3. **Kernels keep their known answers.** A change to field, extension, hash or transcript code runs the independent vectors on both lanes (`make test`, `make test-native`).
4. **No unchecked code for speed.** The verification path stays free of `@unsafe` defs and foreign effects, so that laws about it remain provable and `--verdict` remains possible. The only foreign code is the argument shim of the native entry.
5. **Sequential meaning.** A parallel call may reorder work, never results: REQ-PAR-1 is tested on every change that adds one.
6. **Representation behind an interface.** Field elements, extension elements and vectors of them are reached through their own modules, so that a native 64-bit integer in a later Bend release, or a different vector layout, changes those modules alone.

## Measurement protocol

A number counts when it comes from `make benchmark-standalone` or its Slurm job, which: verifies every fixture file against its `SHA256SUMS`; runs one verified warm-up per program; then three fresh processes per program in alternating order with an empty executable search path; requires exit 0 and the four published closing lines from every sample; and records wall time, peak resident memory, the thread count, the host, the compiler versions, and the source and executable digests. Report the median and all samples. Compare programs only within one job. State the fixture, the policy and the thread count beside every figure, and keep measurements of other builds or hosts labeled as such.
