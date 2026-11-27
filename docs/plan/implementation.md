# Implementation plan

> Status: living

The standalone verifier checks the four bundled H821 configurations. The first release took each protocol stage from the reference implementation into Bend, then ran the complete verifier against the published proofs. The release tracker links the implementation issues, their prerequisites and their conformance evidence. [Standalone release](https://github.com/AbdelStark/flashprove-bend-verifier/issues/12)

## Choosing work

GitHub issues hold the dependency graph and the acceptance evidence for each change. For the next unassigned task, start with the lowest-numbered open implementation issue whose prerequisites have closed. Check its assignees and linked pull requests for work already in progress. A release tracker groups its child issues. [Open issues](https://github.com/AbdelStark/flashprove-bend-verifier/issues)

From this checkout, the GitHub CLI can list open issues with no open prerequisites, oldest first. The query skips pull requests and parent trackers.

```sh
gh api --paginate 'repos/{owner}/{repo}/issues?state=open&sort=created&direction=asc&per_page=100' \
  --jq '.[] | select(.pull_request == null and .sub_issues_summary.total == 0 and .issue_dependencies_summary.blocked_by == 0) | "#\(.number) \(.title)"'
```

## Workstreams

| Milestone | Order of work | Evidence |
| --- | --- | --- |
| [Fast Bend verifier](https://github.com/AbdelStark/flashprove-bend-verifier/issues/23) | Stage timings identify the expensive arithmetic, allocations and traversals. The vector layout and independent stage calls feed into request-stage parallelism. | Matched whole-call timings, observed worker counts, peak memory and the same verdicts on the conformance corpus. [Performance contract](../spec/performance.md) |
| [Assurance](https://github.com/AbdelStark/flashprove-bend-verifier/milestone/4) | Differential runs compare Bend with the C++ reference. Mutation tests ask whether a missing refusal is observable. The arithmetic work has its own proof obligations. | Reproducible disagreements or refusal coverage, stage-specific diagnostics and kernel laws with a checked mathematical statement. [Assurance contract](../spec/assurance.md) |
| [Additional configurations](https://github.com/AbdelStark/flashprove-bend-verifier/milestone/5) | Bend derives plans, error accounting, geometry and weight placement from the public files, so the caller trusts only the commitment ID. [Decision](../adr/configuration-admission.md) | A genuine proof for a configuration outside the bundled four, with agreement on that proof and its altered copies. [Public plan decision](../adr/public-plans.md) |

Keep requirements and evidence together. A change to configuration admission must still bind the caller's chosen commitment and compute the verdict from the supplied key, leaf and proof. A benchmark uses the same policy and coverage on both builds. [Verification contract](../spec/verifier.md) · [Contributor guide](../../CONTRIBUTING.md)
