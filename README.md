<div align="center">

# FlashProve × Bend 2

**Check that an LLM's reply came from the model it claims, on a CPU, without the weights.**

[![CI](https://img.shields.io/github/actions/workflow/status/AbdelStark/flashprove-bend-verifier/verify.yml?branch=main&style=for-the-badge&label=conformance)](https://github.com/AbdelStark/flashprove-bend-verifier/actions/workflows/verify.yml)
[![Bend](https://img.shields.io/badge/Bend-2.0.40-7c3aed?style=for-the-badge)](toolchain.lock)
[![FlashProve](https://img.shields.io/badge/FlashProve-0.16.0--rc.26-0ea5e9?style=for-the-badge)](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c)
[![vs Lean](https://img.shields.io/badge/vs%20Lean-5.89%C3%97%20faster-22c55e?style=for-the-badge)](#full-size-proof-17-mib-1001-tokens)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue?style=for-the-badge)](LICENSE)

</div>

---

A [FlashProve](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c) proof says: *given this prompt, every covered token is the committed integer model's first choice.* This repository checks that claim in [Bend 2](https://github.com/bendlang/bend). You give it a model commitment, the tokens and the proof. It answers `YES` or refuses.

- **Type-checked by a proof language.** Bend 2 is a dependently typed language: a function's type can state facts about the values it returns, and the compiler refuses code that does not meet its types. All 151 modules pass that checker, and Bend's independent kernel has rechecked the whole standalone verifier. Today those types pin down shapes, such as an extension-field product returning three coordinates, not full correctness. Proving what the arithmetic computes, and that Bend accepting a proof implies FlashProve's proven Lean verifier accepts it, is open work. [What is and isn't proven](docs/spec/assurance.md#what-has-been-formally-checked)
- **No weights.** The verifier sees only the commitment, the tokens and the proof bytes.
- **Standalone.** Bend checks the key, the selected leaf and the request itself. Nothing else runs at verification time.
- **Parallel.** One executable runs on one worker or many, and prints the same answer either way.
- **Real sizes.** It supports all four published H821 configurations: two model sizes, each under two acceptance policies. The larger model has Llama 4 Maverick's dimensions, with synthetic weights. [Configurations](docs/adr/public-plans.md)

## Full-size proof: 17 MiB, 1,001 tokens

The prompt is 24 tokens. The 17.91 MiB proof covers the next 1,000 tokens plus one proposed next token. `YES` means all 1,001 predictions match the committed model's first choice. [Fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md#what-the-yes-says)

The times below are for one fresh process, from launch to exit: reading the files, all three verification stages and printing the verdict. Inference and proving happen beforehand. **Lean OnBytes** is FlashProve's own native Lean verifier, run on the same files.

| CPU | Bend workers | Bend | Speedup vs. 1 worker | Lean OnBytes | Bend vs. Lean |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apple M4 Max | 1 | 17.64 s | 1.00× | 57.86 s | 3.28× |
| Apple M4 Max | 16 | **9.90 s** | 1.78× | 58.26 s | **5.89×** |
| Intel Xeon Platinum 8480CL | 1 | 38.77 s | 1.00× | 93.09 s | 2.40× |
| Intel Xeon Platinum 8480CL | 8 | **20.84 s** | 1.86× | 92.94 s | **4.46×** |

Each figure is the median of three alternating Bend/Lean pairs, after one warmup per program, with the proof already in the file cache. Both rows for a CPU use the same binary. A separate screen chose each CPU's worker count. On the M4, 12 and 16 workers tie (5.89× in both pairings). The M4 rows measure `05b2268` and the Xeon rows `d42bb69`, which have the same Bend source. [M4 samples and conformance](docs/research/rerun-2026-11-26.md) · [Xeon samples and conformance](docs/research/xeon-rerun-2026-11-27.md) · [Measurement protocol](docs/spec/performance.md)

### Against the C++ verifier

FlashProve's reference verifier, `cp_verify`, is written in C++ and is still faster. Both ran with one thread on the same Apple M4 Max, in alternating pairs:

| Proof | Bend | C++ `cp_verify` | Bend vs. C++ | Bend peak RSS | C++ peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| accepted-proof (small) | 1.87 s | 0.64 s | 2.92× slower | 0.18 GiB | 0.19 GiB |
| full-size | 18.03 s | 8.06 s | 2.24× slower | 1.89 GiB | 3.93 GiB |

With 16 workers Bend takes 9.90 s on the full-size proof, still behind single-thread C++. Closing that gap is [REQ-PERF-4](docs/spec/performance.md). [Samples](docs/research/rerun-2026-11-26.md#bend-and-c-one-worker-each)

## Quick start

You need macOS or Linux with Git, make, Clang, curl and Python 3.11 or newer. The build downloads the pinned Bend compiler into the repository, checks the hashes of the upstream fixtures and writes everything else to `build/`.

```sh
make bootstrap upstream standalone
example=.upstream/FlashProve/examples/accepted-proof
id=79a5a2bc7a469b40df73dedf40abeb740671e8ae8077738bd3743897aeb22183
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$id" -data build
```

The command exits with status 0 and its last line is `YES`. The line above it is the `result-v1` record. There, `tokens=61..63 y=yes` means the proof covers the request's last three tokens and the proposed next token, ID 199. [Expected output](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/accepted-proof/README.md)

| Flag | Effect |
| --- | --- |
| `-j 16` | 16 Bend workers |
| `-j 1` | serial path |
| `-timing` | worker count and per-stage times on stderr |

**Using it for real.** Get the commitment ID from a source you trust, and get it *before* you send the prompt. Pass the tokens you sent and received, the range to check and the policy you accept. Then check the exit status and confirm that the ID, claim, policy and coverage in `result-v1` are the ones you asked for. [Verification contract](docs/spec/verifier.md)

## When the reply isn't the top token

Floating-point inference and the committed integer model can rank two tokens differently. FlashProve's **clipped-gap** policy allows for this. It scores each covered reply token by how far its logit falls below the best one, with a tie rule. It then caps both the average clipped cost and the number of costs above the clip. You choose the policy you accept and pass it in. A covered *next* token must still be the model's first choice.

In this example, 4 of the 32 reply tokens are not the first choice, and the proof still passes:

```sh
example=.upstream/FlashProve/examples/accepted-proof-clipped-gap
build/verify-bend "$example/config" "$example/ivk" "$example/example.req" \
  "$example/example.y" "$example/example.proof" -id "$(cat "$example/ID.txt")" \
  -policy clipped-gap,9244130,323343,1,16,8 -data build
```

The last line is `WITHIN LIMITS`. The record says `tokens=16..47 y=no`: the reply is covered and no next token is claimed. This ID and policy belong to this fixture. [How the cost is computed](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/prover/examples/target_small_f2_gap/README.md)

## How it works

The verifier first hashes the public configuration and finds it in a catalog of the four supported configurations. That fixes every round count, code size and table digest before the proof is read. Then it runs three stages:

1. **Key.** Check the model commitment and rebuild the commitment ID from it. A different ID is refused here.
2. **Leaf.** Check the leaf the proof selects, and its link to the key.
3. **Request.** Replay the transcript, then check the feed-forward, attention and output-head equations for every covered token, and the claims that tie them to the committed weights.

The whole pipeline is ordinary Bend. Bend compiles it to C, and Clang compiles that at `-O3`. The C entry point is a 45-line file that only passes the command-line arguments in.

| Path | Contents |
| --- | --- |
| [`src/`](src) | The verifier: 151 Bend modules and the C entry point. Start at [`standalone.bend`](src/standalone.bend). |
| [`tests/`](tests) | Known-answer tests, run on Bend's JS and native backends. |
| [`scripts/`](scripts) | Build, conformance, fuzzing and benchmark drivers. `scripts/probes/` exposes single stages for comparison. |
| [`profiles/`](profiles) | The four configuration-bound public plans, generated from the pinned upstream source. |
| [`docs/`](docs) | The contracts the code must meet, plus frozen measurement reports. |
| [`research/spikes/`](research/spikes) | Kernel experiments and the patches behind the recorded profiles. |

## What has been checked, and what hasn't

- ✅ Bend and Lean OnBytes agree on all four published fixtures.
- ✅ A fresh proof from the H100 prover passed both Bend and C++ under a new commitment. [Record](docs/research/fresh-proof.md)
- ✅ Bend's independent kernel checked the standalone definitions of the measured revision against their declared types. [Details](docs/spec/assurance.md#what-has-been-formally-checked)
- ✅ On the measured revision, all four published proofs pass, Bend and C++ both reject all 122 altered sets and 256 fuzzed proofs, and 1 and 16 workers agree on 91 of 91 comparisons. [Rerun](docs/research/rerun-2026-11-26.md#conformance)
- ✅ Every commit runs conformance tests and seeded fuzzing. Bend must never accept a mutated proof that C++ refuses.
- ⏳ **Open:** a proof that Bend acceptance implies Lean acceptance for *every* supported input.

`bits=128` in the output is the verifier's accounting target. It assumes proof of work and commitment binding. Read the [assurance contract](docs/spec/assurance.md) and the [upstream theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md) before you rely on it.

## Development

```sh
make help                 # every target
make ci                   # local conformance suite
make standalone-full      # all four published proofs
make standalone-extended  # 122 altered sets vs. the C++ reference
make fuzz                 # random byte mutations, Bend vs. C++
```

The [protocol source map](docs/research/protocol.md) ties each format rule to its code and tests. The [implementation plan](docs/plan/implementation.md) says what comes next, and [Working with Bend](docs/agents/BEND_NOTES.md) covers the compiler's habits.

---

<div align="center">

[Contributing](CONTRIBUTING.md) · [Report a verifier defect privately](SECURITY.md) · [Apache 2.0](LICENSE) · [Upstream notices](NOTICE)

</div>
