# FlashProve verification with Bend 2

Verify a FlashProve H821 inference proof on a CPU using a native Bend command. The verifier reads the configuration, key, selected leaf, request, next token and proof. A successful whole call reports the commitment, verified token range, acceptance policy and security accounting.

**The MVP is a hybrid.** Bend independently checks public input headers and derives the commitment ID. Its native code also runs inside all three proof stages. The pinned C++ verifier supplies the remaining protocol checks, model constraints, accounting and final verdict. An unmodified C++ binary is built separately for differential testing. The [verification contract](docs/spec/verifier.md) and [issue plan](docs/plan/implementation.md) track the independent Bend implementation.

## Independent Bend stages

The standalone stage tests reconstruct the public statement, authenticate the seven configuration-bound plans and consume the genuine key, leaf and request proof bytes. The leaf checker implements the full LINK relation given the anchor table. It derives both tables’ record and column claims, compares the folded messages before their padding, and follows the batched claim through each code switch to the final BASE equality. The key and request probes currently report transcript evidence and authenticated final symbols. The independent whole-call verdict depends on completing the remaining key and request equations. [Release tracker](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/12) · [Public plan contract](docs/adr/public-plans.md)

```sh
make public-input-test plans-reproduce stages-full
```

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

The [native integration decision](docs/adr/native-kernels.md) describes the trust boundary. The hot-path bindings are small patches applied to an archive of the pinned Git object in a temporary build directory. The build runs upstream arithmetic and transcript-vector tests against the linked Bend code before installing the worker. Pure Bend modules and the native adapter have distinct trust boundaries. [Native bindings](src/native) · [Bend implementation](src) · [Compiler notes](docs/agents/BEND_NOTES.md)

## Whole-proof performance

Median wall time over three fresh processes per executable and fixture, on one Apple M4 Max. Every call verified the published exact-match commitment and returned the expected coverage and accounting.

| Verifier | Small proof | Full-size proof |
|---|---:|---:|
| Bend 2 hybrid, public CLI | 2.377 s | 47.225 s |
| Lean OnBytes | 3.858 s | 59.567 s |
| FlashProve C++ | 0.644 s | 8.144 s |

Simplifying field multiplication in Bend reduced the full-size median from 74.196 s to 47.225 s. At full size the optimized hybrid took 20.7% less time than Lean OnBytes and 5.80 times as long as C++. The hybrid and C++ used one request-stage thread and could overlap stages. OnBytes ran them sequentially. FlashProve's theorem-linked Linux verifier is a separate executable with no timing in this comparison. [Optimized measurements](docs/research/field-performance.md) · [Original field profile](docs/research/whole-call.md) · [Lean measurements](docs/research/onbytes.md)

## Reproduce the evidence

| Command | Coverage |
|---|---|
| `make ci` | Documentation drift checks, generated source check, JS and native Bend tests, two small inference proof sets and rejection cases. |
| `make e2e-full` | Small and full-size exact-match and clipped-gap proofs. Compares the worker's whole-call record with the pinned oracle and exercises the public Bend command. Allow at least 4 GiB free for a full-size worker. |
| `make e2e-extended` | Compare the oracle and hybrid worker on 79 altered proof items and 23 altered stored-record cases from the upstream corpus. |
| `make benchmark` | Three alternating single-thread exact-match measurements at each model size. Every measured call checks the expected verdict and closing record. |
| `make benchmark-lean` | Fetch the optional pinned Lean toolchain, build the native OnBytes executable, measure exact-match proofs on the same inputs, and check a damaged proof. |
| `make spikes` | The original isolated kernel and I/O measurements. |
| `make help` | All command targets. |

The measurements establish behavior for the tested files. The Lean verifier's theorem belongs to its own implementation. The [research index](docs/research/protocol.md) distinguishes the theorem-linked runner from Lean's verifier on raw bytes and indexes the recovered protocol research. [Contribution workflow](AGENTS.md) · [License](LICENSE) · [Upstream notices](NOTICE)
