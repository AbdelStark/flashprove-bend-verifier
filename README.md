# FlashProve verification with Bend 2

`build/verify-bend` verifies FlashProve H821 inference proofs on a CPU. The native Bend executable reads the caller’s configuration, verification key, selected leaf, request, next token and proof. It computes the commitment ID, verifies all three proof stages and emits the covered token range and policy. It runs with the packaged public data and an empty executable search path.

## Verify a proof

Building requires the pinned Bend 2 compiler, clang, Python 3 and make. The upstream checkout supplies the examples and independent test oracles. The packaged plan and table data can be installed offline once the toolchain is available.

```sh
make standalone upstream
example=.upstream/FlashProve/examples/accepted-proof
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$(cat "$example/ID.txt")" -data build
```

The small exact-match example covers tokens 61 through 63 and the requested next token. Its last line is `YES`. In an application, supply the model commitment and acceptable policy chosen by the caller. Verify the exit status, commitment, policy and coverage in the closing `result-v1` record. The build field identifies the transitive Bend sources and build inputs. [Verifier output contract](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/docs/output.md)

```sh
example=.upstream/FlashProve/examples/accepted-proof-clipped-gap
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$(cat "$example/ID.txt")" \
  -policy clipped-gap,9244130,323343,1,16,8 -data build
```

This proof covers tokens 16 through 47. Its next token lies outside the requested interval. A successful call ends with `WITHIN LIMITS: clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8`.

## Supported configurations

The independent verifier admits the four H821 configurations bundled with FlashProve, the small and full-size models under exact match and clipped gap. It hashes the complete configuration, authenticates all seven chain plans and four public tables, and checks each stage’s largest dyadic error at each work factor against the 128-bit target. The release embeds public geometry. Key bytes, proof bytes, transcript challenges, layer equations and verdicts are computed at verification time. A new configuration requires reproducing and reviewing its public catalog entries. [Public plan contract](docs/adr/public-plans.md) · [Verification requirements](docs/spec/verifier.md)

The request stage checks the feed-forward, attention and output-head relations, their lookup forests and smallness constraints, the folded codewords, and the shared and request-specific linear claims that bind the model weights. The accounting includes proof of work and assumes the upstream theorem on codes. The formal theorem for the Lean verifier applies to the Lean implementation. [Protocol research and source map](docs/research/protocol.md) · [Release tracker](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/12)

## Reproduce the evidence

| Command | What it checks |
|---|---|
| `make ci` | Type and proof checks, JS and native unit tests, the small proof matrix and differential checks. |
| `make standalone-full` | All four real proofs with the freestanding binary and caller-selected public inputs. Compares all four closing lines and the exit status. |
| `make standalone-extended` | Compares both small altered-copy tables, 79 item mutations and 23 altered record sets with C++. Also substitutes a valid leaf from another commitment. |
| `make stages-full` | Intermediate evidence against upstream, including all three model families and both model sizes. |
| `make plans-reproduce` | Re-exports schedules, shapes and exact accounting from the pinned configuration-only planner and compares the packaged data. |
| `make benchmark-lean` | Reproduces the native Lean OnBytes comparator. |
| `make help` | Lists all build, test and benchmark targets. |

The original hybrid prototype remains available through `make verifier` as `build/verify`. It links Bend kernels into a C++ worker and has its own build identity. The standalone build, tests and verdicts are independent of that worker. Whole-call measurements identify the executable, hardware, fixture and concurrency. [Lucid benchmark results](docs/research/lucid.md) · [M4 hybrid benchmarks](docs/research/field-performance.md) · [Native integration decision](docs/adr/native-kernels.md)

[Contribution workflow](AGENTS.md) · [Implementation plan](docs/plan/implementation.md) · [License](LICENSE) · [Upstream notices](NOTICE)
