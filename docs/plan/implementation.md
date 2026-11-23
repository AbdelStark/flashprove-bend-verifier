# Implementation order

> Status: living

Each row links to an issue with an acceptance test and a native GitHub blocked-by relationship for each prerequisite. Issue state tracks delivery. This table records architecture and ordering. Requirement definitions live in the [verification contract](../spec/verifier.md).

| Issue | Work | Requires | Exit evidence |
|---|---|---|---|
| [#1](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/1) | Build the reference oracle and run original proof sets | — | Exact and clipped-gap, two sizes, matching whole-call results and altered-input refusal |
| [#2](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/2) | Use Bend arithmetic in the whole call | #1 | Linked Bend primitive, known answers, independently identified build and reference parity |
| [#3](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/3) | Bind public inputs and commitment in Bend | #1 | Checked bytes, expected ID/policy and stage intermediates |
| [#4](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/4) | Implement arithmetic, transcript and authenticated openings | #2 | Field/hash known answers, round traces and authenticated paths |
| [#5](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/5) | Establish checked plans and accounting | #3, #4 | Canonical plans/shapes for each supported configuration and rejection on mismatches |
| [#6](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/6) | Verify key and leaf chains | #5 | Both independent stages agree with the reference and refuse altered inputs |
| [#7](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/7) | Implement the common sub-proof checks | #5 | Reproducible intermediate claims and checked final equations |
| [#8](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/8) | Check each model segment | #7 | Feed-forward, attention and head constraints on real requests |
| [#9](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/9) | Ship independent Bend verification | #6, #8 | Three stages and all closing guards under both policies, with all applicable altered-copy cases |
| [#10](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/10) | Measure end-to-end performance | #9 | Same-host measurements with fixture ID, threads, memory method and output |

For the first independent implementation, a finite set of supported model configurations is acceptable. It must verify any conforming key, leaf and request proof within the declared scope. Configuration-specific constants may encode public geometry and authenticated tables. Only the caller can select a trusted commitment. A proof digest, fixture path or stored verdict must never decide verification.

Triage divergences at the first mismatching intermediate. Add the smallest failing case, fix the responsible component, rerun its fixture and then the whole-call matrix. Update the issue with the command, revision, platform and result so a new contributor can reproduce it. Record a speedup only after verifying equivalent coverage and output. [Porting notes](../research/protocol.md)
