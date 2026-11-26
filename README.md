<div align="center">

# FlashProve × Bend 2

**Check that an LLM's reply came from the model it claims, on a CPU, without the weights.**

[![CI](https://img.shields.io/github/actions/workflow/status/AbdelStark/flashprove-bend-verifier/verify.yml?branch=main&style=for-the-badge&label=conformance)](https://github.com/AbdelStark/flashprove-bend-verifier/actions/workflows/verify.yml)
[![Bend](https://img.shields.io/badge/Bend-2.0.40-7c3aed?style=for-the-badge)](toolchain.lock)
[![FlashProve](https://img.shields.io/badge/FlashProve-0.16.0--rc.26-0ea5e9?style=for-the-badge)](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c)
[![vs Lean](https://img.shields.io/badge/vs%20Lean-5.87%C3%97%20faster-22c55e?style=for-the-badge)](#full-size-proof-17-mib-1001-tokens)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue?style=for-the-badge)](LICENSE)

</div>

---

A [FlashProve](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c) proof says: *given this prompt, every covered token is the committed integer model's first choice.* This repo checks that claim in [Bend 2](https://github.com/bendlang/bend). You hand it a model commitment, the tokens and the proof. It hands back `YES` or a refusal.

- **No weights.** The verifier only sees the commitment, the tokens and the proof bytes.
- **Standalone.** The key, the selected leaf and the request are all checked in Bend. No external verifier at runtime.
- **Parallel.** The same executable runs on one worker or many.
- **Real sizes.** Supports the four published H821 configurations: two model sizes, two acceptance policies. The larger model has Llama 4 Maverick's dimensions (synthetic weights). [Configurations](docs/adr/public-plans.md)

## Full-size proof: 17 MiB, 1,001 tokens

A 24-token prompt, a 17.91 MiB proof covering the next 1,000 tokens plus one proposed next token. `YES` means all 1,001 predictions match the committed model's first choice. [Fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md#what-the-yes-says)

Wall time for one fresh process, launch to exit: file reads, all three verification stages, the verdict. Inference and proving happen beforehand. **Lean OnBytes** is FlashProve's own native Lean verifier for the same files.

| CPU | Bend workers | Bend | Speedup vs. 1 worker | Lean OnBytes | Bend vs. Lean |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apple M4 Max | 1 | 18.60 s | 1.00× | 60.11 s | 3.23× |
| Apple M4 Max | 16 | **10.24 s** | 1.82× | 60.14 s | **5.87×** |
| Intel Xeon Platinum 8480CL | 1 | 45.86 s | 1.00× | 93.16 s | 2.03× |
| Intel Xeon Platinum 8480CL | 8 | **23.38 s** | 1.96× | 93.35 s | **3.99×** |

Medians of three alternating Bend/Lean pairs after one warmup each, proof in the file cache. Both worker counts on a CPU use the same binary; a separate trial picked the parallel count. The M4 rows measure `b4a8c4b`; the Xeon rows measure the earlier `9d00a32`. [M4 samples](docs/research/speed-pass.md) · [Xeon samples, worker selection](docs/research/request-projection.md) · [Measurement protocol](docs/spec/performance.md)

## Quick start

You need macOS or Linux, Git, make, Clang, curl and Python 3.11+. The build pulls the pinned Bend compiler into the repo, checks the upstream fixture hashes and writes everything to `build/`.

```sh
make bootstrap upstream standalone
example=.upstream/FlashProve/examples/accepted-proof
id=79a5a2bc7a469b40df73dedf40abeb740671e8ae8077738bd3743897aeb22183
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$id" -data build
```

Exit code 0, last line `YES`. The line above it is the `result-v1` record: `tokens=61..63 y=yes` means the proof covers the request's last three tokens and the proposed next token, ID 199. [Expected output](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/accepted-proof/README.md)

| Flag | Effect |
| --- | --- |
| `-j 16` | 16 Bend workers |
| `-j 1` | serial path |
| `-timing` | worker count and per-stage times on stderr |

**Using it for real:** get the commitment ID from a source you trust *before* you send the prompt. Pass the tokens you sent and received, the range to check and the policy you accept. Then check the exit status and confirm the ID, claim, policy and coverage in `result-v1`. [Verification contract](docs/spec/verifier.md)

## When the reply isn't the top token

Floating-point inference and the committed integer model can rank two tokens differently. FlashProve's **clipped-gap** policy tolerates that: it scores each covered reply token by how far its logit falls below the best one (with a tie rule), then caps the average clipped cost and the count of costs above the clip. You pass the policy you accept. A covered *next* token must still be the model's first choice.

In this example, 4 of 32 reply tokens aren't the first choice, and the proof still passes:

```sh
example=.upstream/FlashProve/examples/accepted-proof-clipped-gap
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$(cat "$example/ID.txt")" \
  -policy clipped-gap,9244130,323343,1,16,8 -data build
```

Last line: `WITHIN LIMITS`. The record says `tokens=16..47 y=no`: the reply is covered, the following token isn't claimed. The ID and policy belong to this fixture. [How the cost is computed](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/prover/examples/target_small_f2_gap/README.md)

## What's been checked, and what hasn't

- ✅ Bend and Lean OnBytes agree on all four published fixtures.
- ✅ A fresh proof from the H100 prover passed both Bend and C++ under a new commitment. [Record](docs/research/fresh-proof.md)
- ✅ Bend's kernel checked the standalone definitions in the measured revision (`9d00a32`) against their declared types. [Details](docs/research/request-projection.md#checking-the-verification-path)
- ✅ Every commit runs conformance plus seeded fuzzing: Bend must never accept a mutated proof that C++ refuses.
- ⏳ **Open:** a proof that Bend acceptance implies Lean acceptance for *every* supported input.

`bits=128` in the output is the verifier's accounting target and assumes proof-of-work and commitment binding. Read the [assurance contract](docs/spec/assurance.md) and the [upstream theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md) before you rely on it.

## Development

```sh
make help                 # every target
make ci                   # local conformance suite
make standalone-full      # all four published proofs
make standalone-extended  # 122 altered sets vs. the C++ reference
make fuzz                 # random byte mutations, Bend vs. C++
```

Start with the [protocol source map](docs/research/protocol.md), which ties each format rule to its code and tests, and the [implementation plan](docs/plan/implementation.md) for what's next.

---

<div align="center">

[Contributing](CONTRIBUTING.md) · [Report a verifier defect privately](SECURITY.md) · [Apache 2.0](LICENSE) · [Upstream notices](NOTICE)

</div>
