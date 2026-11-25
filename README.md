# FlashProve verifier in Bend 2

This is a CPU verifier for FlashProve inference proofs. Given a model commitment, a token sequence and a proof, it checks whether the specified tokens satisfy the caller’s policy under the committed integer model. Under exact match, each checked token must be the model’s first choice at that position. The weights stay with the prover. [Upstream protocol](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c)

We built the verifier to measure how Bend 2 handles the same proof as FlashProve’s C++ and Lean implementations. The standalone executable checks the key, the selected leaf and the request in Bend. It supports four H821 configurations, covering two model sizes and two acceptance policies. The published examples use synthetic weights. The largest has the dimensions of Llama 4 Maverick. [Supported configurations](docs/adr/public-plans.md) · [Full-size fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md)

## How long does it take to verify one proof?

The benchmark measures the time a client waits to check **one existing proof on its CPU**. In the full-size example, the first 24 tokens are the prompt. The proof covers the next 1,000 tokens in the reply and one proposed next token. A single `YES` means all 1,001 predictions match the committed integer model's first choice at their respective positions. [What the fixture proves](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md#what-the-yes-says)

We start the clock when the compiled verifier launches. It reads the 17.91 MiB proof and public inputs from local files, checks the commitment and token claims, prints its verdict and exits. The timer excludes compilation, downloads, model inference and proof generation.

The request proof includes equations that read individual cells of a table called U3. Bend now keeps each cell’s integer address when it combines those equations, saving a list allocation and traversal for each read. The table compares that change with the previous revision. Each result is the median of three fresh processes after a verified warmup per executable. Both builds used the same worker count within a row.

| CPU | Bend workers | Previous Bend | Bend with sparse U3 reads | Peak RSS, previous → new |
| --- | ---: | ---: | ---: | ---: |
| Apple M4 Max | 1 | 46.034 s | 38.279 s | 2.17 → 2.00 GiB |
| Apple M4 Max | 16 | 22.639 s | 22.184 s | 3.47 → 2.73 GiB |
| Lucid Xeon Platinum 8480CL | 1 | 88.879 s | 74.625 s | 2.18 → 2.00 GiB |
| Lucid Xeon Platinum 8480CL | 16 | 45.236 s | 41.122 s | 3.48 → 2.69 GiB |

**Against Lean on the same proof**, a separate one-worker M4 run took **38.412 s in Bend** and **64.619 s in native Lean OnBytes**. Lean took 1.68× as long by median wall time. The benchmark record includes every sample, verdict, binary hash and command. [Latest measurements](docs/research/sparse-u3.md) · [Earlier Bend, Lean and C++ comparisons](docs/research/cpu-optimization.md)

OnBytes is FlashProve’s Lean implementation of the byte-level checks performed by its C++ verifier. The often-quoted **19-minute Lean result** times a different command on the Xeon. That driver builds a parser tool, links a helper and evaluates the verifier defined in the upstream soundness development. [Theorem-linked Linux measurements](docs/research/lucid.md#theorem-linked-verifier) · [Which benchmark to run](docs/spec/performance.md#reproduce-a-measurement)

## Verify the small example

From the repository root on macOS or Linux, with Git, make, Clang, curl and Python 3.11 or newer on your path, run the following commands. The build installs the pinned Bend compiler locally, checks the upstream fixture hashes and writes the executable and its public data to `build/`.

```sh
make bootstrap upstream standalone
example=.upstream/FlashProve/examples/accepted-proof
id=79a5a2bc7a469b40df73dedf40abeb740671e8ae8077738bd3743897aeb22183
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$id" -data build
```

Append `-j 16` to use 16 Bend workers, or `-j 1` for the serial path. Add `-timing` to see the observed worker count and stage times on stderr.

The command exits 0 and prints `YES`. Look one line above it for `result-v1`. In this example, `tokens=61..63 y=yes` means the proof covers the final three tokens of the request and the proposed next token, ID 199. Each is the integer model’s first choice given the preceding tokens. [Fixture and expected output](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/accepted-proof/README.md)

For your own verification, get the commitment ID from a source you trust before sending the prompt. Supply the tokens you sent and received, the range you want checked and the policy you accept. Check the process exit status and confirm the ID, claim, policy and coverage in `result-v1`. [Verification contract](docs/spec/verifier.md)

## When a reply uses a different token

A floating-point inference engine and the committed integer model can rank two tokens differently. FlashProve’s *clipped-gap* policy scores each covered reply token by how far its logit falls below the best logit, with a tie rule. The caller chooses limits on the average clipped cost and the number of costs above the clip. A next token covered by the proof must still be the integer model’s first choice.

In the small clipped-gap example, four of the 32 reply tokens differ from the model’s first choice. The proof passes the stated limits. To see the distinction, run the example with its published policy.

```sh
example=.upstream/FlashProve/examples/accepted-proof-clipped-gap
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$(cat "$example/ID.txt")" \
  -policy clipped-gap,9244130,323343,1,16,8 -data build
```

The last line starts with `WITHIN LIMITS`. The record gives `tokens=16..47 y=no`. This proof covers the reply in the request file and makes no claim about the following token. The ID and policy above belong to this fixture. [Clipped-gap example and cost calculation](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/prover/examples/target_small_f2_gap/README.md)

## What has been checked

Bend and Lean OnBytes agree on all four published fixtures. A fresh proof from the H100 prover also passed both Bend and C++ under a new commitment. Bend’s independent kernel checked the standalone definitions against their declared types. A proof that Bend acceptance implies Lean acceptance for every supported input remains open. The reported `bits=128` is the verifier’s accounting target, with assumptions about proof of work and commitment binding. [Assurance and its limits](docs/spec/assurance.md) · [Fresh-proof record](docs/research/fresh-proof.md) · [Upstream theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md)

## Development

Run `make standalone-full` to check all four published proofs and `make standalone-extended` to compare refusals with the C++ reference. The [protocol source map](docs/research/protocol.md) connects the format rules to the implementation and its tests. For the earlier hybrid executable, see the [native kernel design](docs/adr/native-kernels.md).

[Contributing](CONTRIBUTING.md) · [Reporting a verifier defect privately](SECURITY.md) · [Apache 2.0 license](LICENSE) · [Upstream notices](NOTICE)
