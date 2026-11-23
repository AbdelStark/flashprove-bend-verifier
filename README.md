# FlashProve verification with Bend 2

Verify a FlashProve H821 inference proof on a CPU using a native Bend command. The verifier reads the configuration, key, selected leaf, request, next token and proof. A successful whole call reports the commitment, verified token range, acceptance policy and security accounting.

**The MVP is a hybrid.** Bend independently checks public input headers and derives the commitment ID. Its native code also runs inside all three proof stages. The pinned C++ verifier supplies the remaining protocol checks, model constraints, accounting and final verdict. An unmodified C++ binary is built separately for differential testing. The [verification contract](docs/spec/verifier.md) and [issue plan](docs/plan/implementation.md) track the independent Bend implementation.

## Run a proof

Use macOS or Linux with Git, Make, Python 3.10+, Clang, a C++17 standard library, curl, patch and tar. Building the reference verifier on Linux also uses GCC 13+ and GNU coreutils/findutils. Download and build requirements are pinned in [toolchain.lock](toolchain.lock) and [upstream.lock](upstream.lock).

```sh
make verifier
example=.upstream/FlashProve/examples/accepted-proof
build/verify "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$(cat "$example/ID.txt")"
```

Expect exit 0 and a final line of `YES`. This example checks three request tokens and the next token for an eight-layer model with synthetic weights. Its bundled ID is the known answer for this demonstration. For a caller's own request, supply the independently trusted model commitment and the request and reply tokens you intend to check.

The second small example checks a bounded-cost policy. Supply the policy explicitly.

```sh
example=.upstream/FlashProve/examples/accepted-proof-clipped-gap
build/verify "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$(cat "$example/ID.txt")" \
  -policy clipped-gap,9244130,323343,1,16,8
```

Expect exit 0 and `WITHIN LIMITS: clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8`. Check the exit status and the complete `result-v1` record. The two installed executables, `build/verify` and its sibling `build/bend_verify`, run together. File or child-process errors yield a non-accepting result. The `build=` field identifies the proof worker's source, including the Bend kernels.

## What executes in Bend

| Component | Work performed |
|---|---|
| Public input | Decode the request interval and token, inspect file headers, select the leaf, hash the configuration files, expand the record seeds and compute the published commitment ID. The worker rechecks the binding on the bytes it actually verifies. |
| Hashes and openings | Both FlashProve hash families call Bend BLAKE2b compression. Bend constructs and hashes the two-child messages used for Merkle vertices. The worker manages the multiproof traversal and records cross-opening consistency. |
| Arithmetic and challenges | Bend implements Goldilocks product and reduction, cubic extension multiplication, work-bit tests, canonical field candidate tests and position extraction. |
| Sub-proofs | Bend evaluates the masked sumcheck contributions and Horner steps. The worker supplies transcript values, enforces round order, checks final equations and applies the feed-forward, attention and output-head constraints. |

The hot-path bindings are small patches applied to an archive of the pinned Git object in a temporary build directory. The build runs upstream arithmetic and transcript-vector tests against the linked Bend code before installing the worker. Pure Bend modules and the native adapter have distinct trust boundaries. [Native bindings](src/native) · [Bend implementation](src) · [Compiler notes](docs/agents/BEND_NOTES.md)

## Reproduce the evidence

| Command | Coverage |
|---|---|
| `make ci` | Documentation drift checks, generated source check, JS and native Bend tests, two small inference proof sets and rejection cases. |
| `make e2e-full` | Small and full-size exact-match and clipped-gap proofs. Compares the worker's whole-call record with the pinned oracle and exercises the public Bend command. Allow at least 4 GiB free for a full-size worker. |
| `make benchmark` | Three alternating single-thread exact-match measurements at each model size. Every measured call checks the expected verdict and closing record. |
| `make spikes` | The original isolated kernel and I/O measurements. |
| `make help` | All command targets. |

The measurements establish behavior for the tested files. The Lean verifier's theorem belongs to its own implementation. The [research index](docs/research/protocol.md) distinguishes the theorem-linked runner from Lean's verifier on raw bytes and indexes the recovered protocol research. [Contribution workflow](AGENTS.md) · [License](LICENSE) · [Upstream notices](NOTICE)
