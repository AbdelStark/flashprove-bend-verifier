# Working on the verifier

Read the [verification contract](docs/spec/verifier.md). For backlog work, choose the next unblocked issue in the [implementation plan](docs/plan/implementation.md). Use the [research index](docs/research/protocol.md) to find a protocol rule or upstream implementation.

- Begin with `make bootstrap` and `make upstream`. Use `make help` for the available commands. Keep upstream source and fixtures read-only. Put generated files and test outputs in the ignored build directory.
- For a verification change, identify the affected stage, the rule it enforces and the input that could otherwise reach acceptance. For each new check, keep a known answer or refusal with its provenance. Exercise both Bend lanes when practical. On the verification path, run the native whole call and `make fuzz`. [Assurance contract](docs/spec/assurance.md)
- When a comparison fails, trace the first differing value and keep the smallest reproducer. Update the living requirement or toolchain note and link the finding to its issue. Preserve frozen research as a record of its revision.
- A pin change belongs in `toolchain.lock` or `upstream.lock`. Include a short architecture decision recording the affected rules and fixtures. Rebuild and retest the standalone and hybrid paths and their reference. Account for any changed expected results.
- For a speed change, verify the verdicts, then take the same measurement before and after. Scope the claim to those builds. [Performance contract](docs/spec/performance.md)

Before handoff run `make ci` and `make docs-check`. Record the requirement, source identity, commands, observed results and any limits in the issue or pull request. A whole-call requirement needs a whole-call result. Name the native and integration runs, including fixture sizes, and say which lanes were unavailable. [Contributor guide](CONTRIBUTING.md)
