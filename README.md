# FlashProve verifier in Bend 2

This CPU verifier checks a FlashProve inference proof against a model commitment and a sequence of tokens. Under the exact-match policy, each covered token must be the committed integer model’s first choice given the tokens before it. The verifier needs no model weights. [Upstream protocol](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c)

The standalone executable checks the key, the selected leaf and the request in Bend 2. It supports the four published H821 configurations in FlashProve 0.16.0-rc.26, covering two model sizes and two acceptance policies. The examples use synthetic weights. The larger model has the dimensions of Llama 4 Maverick. [Supported configurations](docs/adr/public-plans.md) · [Full-size fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md)

## Verifying one full-size proof

The full-size example has a 24-token prompt. Its 17.91 MiB proof covers the next 1,000 tokens and one proposed next token. A `YES` means all 1,001 predictions match the committed integer model’s first choice. [Published fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md#what-the-yes-says)

Both programs start from the same committed key, leaf, tokens and proof bytes. We time one fresh process from launch through exit, including file reads, all three verification stages and reporting the verdict. Inference and proof generation happen beforehand. **Lean OnBytes** is FlashProve’s native Lean executable for verifying these files.

| CPU | Bend workers | Standalone Bend | Lean OnBytes | Lean time ÷ Bend time |
| --- | ---: | ---: | ---: | ---: |
| Apple M4 Max | 16 | 11.18 s | 59.71 s | 5.34× |
| Intel Xeon Platinum 8480CL | 8 | 23.38 s | 93.35 s | 3.99× |

Times are medians of three alternating runs per program after one warmup each, with the proof in the file cache. We selected the fastest measured Bend worker count on each CPU in a separate run. Lean OnBytes verifies sequentially. [All samples, worker selection and peak memory](docs/research/request-projection.md) · [Measurement protocol](docs/spec/performance.md)

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

A floating-point inference engine and the committed integer model can rank two tokens differently. FlashProve’s *clipped-gap* policy scores each covered reply token by how far its logit falls below the best logit, with a tie rule. The policy bound to the commitment sets limits on the average clipped cost and the number of costs above the clip. The caller supplies the policy they accept. A next token covered by the proof must still be the integer model’s first choice.

In the small clipped-gap example, four of the 32 reply tokens differ from the model’s first choice. The proof passes the stated limits. To see the distinction, run the example with its published policy.

```sh
example=.upstream/FlashProve/examples/accepted-proof-clipped-gap
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$(cat "$example/ID.txt")" \
  -policy clipped-gap,9244130,323343,1,16,8 -data build
```

The last line starts with `WITHIN LIMITS`. The record gives `tokens=16..47 y=no`. This proof covers the reply in the request file and makes no claim about the following token. The ID and policy above belong to this fixture. [Clipped-gap example and cost calculation](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/prover/examples/target_small_f2_gap/README.md)

## What has been checked

Bend and Lean OnBytes agree on all four published fixtures. A fresh proof from the H100 prover also passed both Bend and C++ under a new commitment. Bend’s independent kernel checked the standalone definitions in the measured revision (`9d00a32`) against their declared types. A proof that Bend acceptance implies Lean acceptance for every supported input remains open. The reported `bits=128` is the verifier’s accounting target, with assumptions about proof of work and commitment binding. [Assurance and its limits](docs/spec/assurance.md) · [Checks on the measured build](docs/research/request-projection.md#checking-the-verification-path) · [Fresh-proof record](docs/research/fresh-proof.md) · [Upstream theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md)

## Development

Run `make standalone-full` to check all four published proofs and `make standalone-extended` to compare refusals with the C++ reference. The protocol source map connects the format rules to the implementation and its tests. [Protocol source map](docs/research/protocol.md) · [Implementation plan](docs/plan/implementation.md)

[Contributing](CONTRIBUTING.md) · [Reporting a verifier defect privately](SECURITY.md) · [Apache 2.0 license](LICENSE) · [Upstream notices](NOTICE)
