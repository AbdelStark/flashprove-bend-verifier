# Admitting a configuration outside the bundled four

> Status: living

## Context

The verifier accepts only the four configurations published with FlashProve. Everything else ends `NO: unsupported-configuration`. For each of the four, plans, codes, segment shapes, weight placement and error accounting come from the upstream planner. A maintainer runs it offline and compiles the output into Bend catalogs. A provider's real commitment has its own parameter and scale files, so its proofs cannot be checked today. [Configuration-bound public plans](public-plans.md)

FORMAT 8.4 gives a second verifier two ways to get these numbers. The first rebuilds the derivation of 8.4 bit for bit from the three public files. The second takes the plan, the codes and the shapes as public inputs in their canonical bytes. Section 18 says what the second way costs. Whoever supplies the plan chooses every round's error. The parser and steps 3 to 6 and 8 of 8.4, item 23, no longer run, so every condition they enforce becomes a hypothesis of any soundness statement, unless the verifier tests it again. [8.4](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/08-parameters.md#84-what-is-derived) · [Section 18](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/docs/format/FORMAT.md#18-for-a-formal-definition)

We weighed three options.

| Option | What the caller trusts | What whoever controls the extra input can do | Section 18 |
| --- | --- | --- | --- |
| **(a) Derive in Bend** from the parameter, layout and scale files | The commitment ID and the verifier. The ID already names the three public files. | Nothing: there is no extra input. | The first way. It adds no duty. |
| **(b) Load a bundle at run time**, authenticated by a digest the caller passes beside the ID | The ID, the verifier, and whoever computed the bundle and its digest | Choose the codes and the number of positions, and so the error of every round. They can also skip the 8.4 checks the verifier no longer repeats. | The second way. The section 18 conditions become hypotheses. |
| **(c) Keep compiled catalogs**, with a documented admission tool | The ID, the verifier, and the maintainer who ran the planner for that configuration | The same as (b), but only at release time and in public review | The second way, with the derivation done offline by the upstream code |

## Decision

We take option (a). Bend derives the plans, codes, segment geometry, weight placement and error accounting from the three public files. It applies the tests of FORMAT 13.8 to those files, and it refuses a configuration that 8.4 rejects. No other input is needed at run time: the caller trusts the commitment ID and the verifier binary, as they do today.

This keeps the verifier standalone. It removes the maintainer from the trust path for new configurations. It also lets a later proof about the Bend verifier rest on one hypothesis, that the files are the ones the ID names, instead of on the condition lists of section 18.

One limit stays. FORMAT 8.4 says the numbers, codes and plan words can be rebuilt from its text, but the verdict on a plan (item 22) cannot, because the text does not give every round's error. For those error terms the derivation follows the pinned source (`blocks/frame/parameters.h`). It is checked against the bounds the upstream planner exports for the four bundled configurations.

## Consequences

- **REQ-PLAN-1** will be met by derivation. The obligation stays the same: bind shapes, round order, counts, codes, error accounting and sizes to the configuration. The evidence changes. For the bundled four, the derived bytes and bounds must equal the catalogs. A configuration with one changed parameter line must derive the planner's plan or be refused under the planner's name. [Verification contract](../spec/verifier.md)
- **Catalogs become test data.** When the derivation matches them, `plan_catalog`, `accounting_catalog`, `weight_catalog`, `ff_catalog`, `head_catalog` and the segment profiles stop being inputs to verification. `make plans-reproduce` keeps checking them against the planner.
- **Cost.** The derivation runs once per call, on the public files, before the key stage. It must stay small next to the request stage. Its time is reported under the public stage of `-timing`.
- **Until the derivation lands**, the verifier keeps refusing other configurations with `NO: unsupported-configuration`. Nothing is admitted through a bundle or a new catalog entry in the meantime.
- **Follow-up work**, in order: #30 derives the chain plans and round accounting (8.4). #31 derives geometry and weight placement and applies the tests of 13.8. #32 generates a proof under a configuration outside the four and verifies it with Bend and `cp_verify`.
