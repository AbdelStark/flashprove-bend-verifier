# Contributing

Thanks for helping. This is a verifier, so one kind of bug matters more than all the others: Bend accepting a proof that the pinned C++ verifier refuses. If you find one, please report it privately. [Security reporting](SECURITY.md)

For any other bug, open an issue with the input or fixture name, the command you ran and what each verifier printed.

## Build a verifier you can check

You need Linux or macOS with Git, curl, make, clang, clang++ and Python 3.11 or newer on your path. On Linux, the C++ reference build also needs g++ 13 or newer and the GNU coreutils and findutils. Run everything from the repository root.

```sh
make bootstrap
make upstream
make standalone-test
```

The last command builds the native Bend verifier and runs it on the two small proofs. The exact-match example must end in `YES`. The clipped-gap example must end in `WITHIN LIMITS` with the published policy values. Generated data and test outputs go in `build/`. Treat the checkout in `.upstream/` as read-only. [Fixtures and expected results](docs/spec/verifier.md#conformance-corpus)

## Change a check

Start from a format rule and an input that exercises it. Choosing that input takes some care. If you change an equation inside a proof, flipping a byte often shows only that the transcript hash changed, and the equation itself never runs. A test that holds the genuine transcript fixed and changes the target or a coefficient reaches the equation directly. For a parser change, a truncated or trailing field usually reaches the rule. [Protocol source map](docs/research/protocol.md) · [Fixed-transcript tests](scripts/test-request-claims.py)

A pull request that changes verification behavior should name the requirement it serves and give a command someone else can run. Include the fixture or seed, the build identity, the exit status and the verdict or intermediate value you saw. Keep the smallest case that shows a disagreement. If the acceptance path changes, run the native verifier on a whole proof. [Verification contract](docs/spec/verifier.md) · [Assurance contract](docs/spec/assurance.md)

## Before you open a pull request

Run `make ci` and `make docs-check`. GitHub Actions runs both, plus a seeded `make fuzz` on the two small fixtures. Its whole-proof calls use only the small fixtures, so:

- for a change on the verification path, run `make fuzz` locally too;
- for end-to-end coverage of all four published proofs, run `make standalone-full`.

[Workflow](.github/workflows/verify.yml) · [Make targets](Makefile)

For a speed change, keep the verdicts identical first, then time the same workload before and after. Record the fixture, the hardware, both binaries, the worker settings and every sample. [Performance contract](docs/spec/performance.md)

## Finding work

The implementation plan links the open issues and their dependencies. If you work with a coding agent, point it at [AGENTS.md](AGENTS.md). [Implementation plan](docs/plan/implementation.md) · [Working with Bend](docs/agents/BEND_NOTES.md)
