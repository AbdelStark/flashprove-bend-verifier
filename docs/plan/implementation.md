# Implementation order

> Status: living

The [standalone release tracker](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/12) groups the eight implementation and benchmark issues. Each issue has an acceptance test and a GitHub blocked-by relationship for each prerequisite. The [hybrid MVP](https://github.com/AbdelStark/fv-flashprove-bend-verifier/milestone/1) and [independent Bend verifier](https://github.com/AbdelStark/fv-flashprove-bend-verifier/milestone/2) milestones track delivery. This table records architecture and ordering. Requirement definitions live in the [verification contract](../spec/verifier.md).

| Issue | Work | Requires | Exit evidence |
|---|---|---|---|
| [#1](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/1) | Build the reference oracle and run original proof sets | — | Exact and clipped-gap, two sizes, matching whole-call results and altered-input refusal |
| [#2](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/2) | Use Bend arithmetic in the whole call | #1 | Linked Bend primitive, known answers, independently identified build and reference parity |
| [#3](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/3) | Bind public inputs and commitment in Bend | #1 | Checked bytes, expected ID/policy and stage intermediates |
| [#4](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/4) | Implement arithmetic, transcript and authenticated openings | #2 | Field/hash known answers, round traces and authenticated paths |
| [#5](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/5) | Establish checked plans and accounting | #3 | Canonical plans/shapes for each supported configuration and rejection on mismatches |
| [#6](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/6) | Verify key and leaf chains | #4, #5 | Both independent stages agree with the reference and refuse altered inputs |
| [#7](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/7) | Implement the common sub-proof checks | #4, #5 | Reproducible intermediate claims and checked final equations |
| [#8](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/8) | Check each model segment | #7 | Feed-forward, attention and head constraints on real requests |
| [#9](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/9) | Ship independent Bend verification | #6, #8 | Three stages and all closing guards under both policies, with all applicable altered-copy cases |
| [#10](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/10) | Measure end-to-end performance | #9 | Same-host measurements with fixture ID, threads, memory method and output |
| [#11](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/11) | Reduce the measured field multiplication cost | #2 | Same-host whole-call improvement with field and proof conformance retained |

## After the standalone release

An [independent review](../research/independent-review.md) of the released verifier found no input on which it accepts and the reference refuses, and measured it at 35 times the reference's time at full size with no parallel call in the sources. The work that follows has three milestones: [fast Bend verifier](https://github.com/AbdelStark/fv-flashprove-bend-verifier/milestone/3), tracked by [#23](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/23) against the [performance contract](../spec/performance.md); [assurance](https://github.com/AbdelStark/fv-flashprove-bend-verifier/milestone/4), against the [assurance contract](../spec/assurance.md); and [any configuration](https://github.com/AbdelStark/fv-flashprove-bend-verifier/milestone/5). Each issue below has a GitHub blocked-by relationship for each prerequisite. Take the lowest-numbered issue whose prerequisites are closed.

| Issue | Work | Requires | Exit evidence |
|---|---|---|---|
| [#13](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/13) | Report stage times and add a profile target | — | Stage lines that leave standard output unchanged; a profile table naming Bend defs |
| [#14](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/14) | Halve the cost of the extension product | [#13](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/13) | Twice the kernel throughput, all known answers, a faster whole call |
| [#15](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/15) | Hold vectors in flat limb arrays | [#13](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/13) | Freeing and counting under 8% of the profile; a third less memory |
| [#16](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/16) | Remove closures from the fold and deposit loops | [#13](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/13) | Closure application under 1% of the profile |
| [#17](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/17) | Hoist repeated traversals and lookups | [#13](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/13) | List and string traversal under 1% of the profile |
| [#18](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/18) | Cut full-size peak memory below 7 GB | [#15](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/15) | Peak resident memory by the benchmark protocol |
| [#19](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/19) | Run the three stages as parallel calls | [#13](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/13) | Identical output at 1 and 16 threads; first refusal in key, leaf, request order |
| [#20](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/20) | Fork-join the request stage | [#15](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/15), [#19](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/19) | Six times faster at 16 threads at full size; the scaling table |
| [#21](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/21) | Gate CI on the small call's relative cost | [#13](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/13) | A budget that fails an injected slowdown |
| [#22](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/22) | Publish matched measurements | [#14](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/14)–[#18](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/18), [#20](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/20) | The Lucid protocol at 1 and 16 threads beside C++ and both Lean baselines |
| [#24](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/24) | Fuzz differentially in CI and record a long campaign | — | No Bend accept beside a reference refusal in 10,000 cases per fixture family |
| [#25](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/25) | Mutation-test the rejection points | [#24](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/24) | Every disabled refusal fails a test, or has a written reason |
| [#26](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/26) | Tie requirements to commands in docs-check | — | A requirement without a runnable command fails the check |
| [#27](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/27) | Name the refusing stage | — | No key-stage name for a fault in a proof or leaf file |
| [#28](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/28) | Prove laws for the arithmetic kernels | [#14](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/14) | `ALL PROOFS CHECK` in CI for limb and reduction laws |
| [#29](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/29) | Decide how other configurations are admitted | — | An architecture decision record with its trust statement |
| [#30](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/30) | Derive plans and accounting in Bend | [#29](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/29) | Byte-equal parameter files for all 28 bundled chains |
| [#31](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/31) | Derive geometry and apply the public-file tests | [#29](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/29) | Derived values equal the catalogs; each test has an input it alone refuses |
| [#32](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/32) | Verify a proof under a configuration that is not bundled | [#30](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/30), [#31](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/31) | Both verifiers agree on a genuine set and its altered copies |
| [#33](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/33) | Complete or retire the unfinished research digests | — | No digest described as incomplete |

The single-thread items #14 to #17 touch different modules and can proceed side by side once #13 lands. A speed change never alters a verdict: the rules are in the performance contract.

For the first independent implementation, a finite set of supported model configurations is acceptable. It must verify any conforming key, leaf and request proof within the declared scope. Configuration-specific constants may encode public geometry and authenticated tables. Only the caller can select a trusted commitment. A proof digest, fixture path or stored verdict must never decide verification.

Triage divergences at the first mismatching intermediate. Add the smallest failing case, fix the responsible component, rerun its fixture and then the whole-call matrix. Update the issue with the command, revision, platform and result so a new contributor can reproduce it. Record a speedup only after verifying equivalent coverage and output. [Porting notes](../research/protocol.md)
