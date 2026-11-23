# Working on the verifier

Read the [verification contract](docs/spec/verifier.md) and choose the next unblocked item in the [implementation plan](docs/plan/implementation.md). The [research index](docs/research/protocol.md) links protocol questions to source sections, fixture evidence and earlier experiments.

Use `make help` for the command surface. Begin with `make bootstrap` and `make upstream`. Keep reference source and examples read-only. Build outputs belong outside the source tree in the ignored build directory. Pin the compiler in `toolchain.lock` and the protocol revision in `upstream.lock`.

1. Identify the format rule or implementation-defined behavior, the affected verification stage, and how a bad proof could reach acceptance.
2. For each new check, capture a small known-answer or refusal case with its provenance. Compare both Bend lanes when practical and run the native whole call for changes on that path.
3. An issue is complete once its evidence is reproducible. Record the affected requirement, source identity, exact command, observed verdict and any residual limitations in the issue or PR. A passing fragment cannot satisfy a whole-call requirement.
4. When a mismatch reveals a gap, keep the minimal test and update the applicable living requirement or toolchain note. Keep frozen research as provenance. Link new findings to the issue that owns the fix.
5. For a pin change, include a short architecture decision record covering changed rules and fixtures. Rebuild and retest both binaries and account for changes in expected results. Scope performance claims to measured builds.

Run `make ci` and `make docs-check` before handoff. Include the native/integration commands exercised and disclose lanes that were unavailable. Check the Makefile for whether CI covers a particular fixture size.
