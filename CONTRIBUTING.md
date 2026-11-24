# Contributing

If Bend accepts a proof that the pinned C++ verifier refuses, report it privately. For ordinary bugs, include the input or fixture name, the command, and what each verifier printed. [Security reporting](SECURITY.md)

## Build a verifier you can check

Use Linux or macOS with Git, curl, make, clang, clang++ and Python 3.11 or newer on your path.
The Linux C++ reference build also needs g++ 13 or newer, GNU coreutils and findutils.
Run from the repository root.

```sh
make bootstrap
make upstream
make standalone-test
```

The last command builds the native Bend verifier and runs the two small proofs.
The exact-match example must end in `YES`. The clipped-gap example must end in `WITHIN LIMITS` with the published policy values.
Test outputs and generated data belong in `build/`. Keep the checkout in `.upstream/` read-only.
[Fixtures and expected results](docs/spec/verifier.md#conformance-corpus)

## Change a check

Start with a format rule and an input that exercises it.
If you change an equation inside a proof, a byte flip may only show that the transcript hash changed.
A test that holds the genuine transcript fixed can reach the equation itself.
For a parser change, a truncated or trailing field can exercise the rule directly.
[Protocol and source index](docs/research/protocol.md) · [Fixed-transcript tests](scripts/test-request-claims.py)

A pull request that changes verification behavior should name the requirement it serves and give a command another contributor can run.
Include the fixture or seed, the build identity, the exit status, and the observed verdict or intermediate value.
Keep the smallest case that exposes a disagreement. Run the native verifier on a whole proof when its acceptance path changes.
[Verification contract](docs/spec/verifier.md) · [Assurance contract](docs/spec/assurance.md)

Run `make ci` and `make docs-check` before handoff. GitHub Actions also runs a seeded `make fuzz` on both small fixtures.
For a change on the verification path, run that target locally.
Use `make standalone-full` for end-to-end coverage of all four published proofs.
The routine PR workflow uses the small fixtures for its whole-proof calls.
[Workflow](.github/workflows/verify.yml) · [Make targets](Makefile)

For a speed change, preserve the verdicts first, then measure the same workload before and after.
Record the fixture, hardware, binaries, worker settings and all samples.
The performance contract specifies the comparison and extended conformance runs. [Performance contract](docs/spec/performance.md)

The implementation plan links open work and its dependencies.
Agents working in this tree should also read the repository instructions. [Implementation plan](docs/plan/implementation.md) · [AGENTS.md](AGENTS.md)
