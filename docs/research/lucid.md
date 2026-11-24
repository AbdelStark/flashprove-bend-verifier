# Whole-call measurements on Lucid

> Status: living

How long does a CPU verifier take to accept a proof already on disk? On 2026-11-23 we timed three jobs on the Intel Xeon Platinum 8480CL in Lucid's H100 SXM server. All verification ran on the host CPUs. The GPU proof-generation experiment used a separate allocation. [Fresh-proof experiment](fresh-proof.md)

The full-size input was one 18,779,540-byte proof for a model with synthetic weights and the dimensions of Llama 4 Maverick. The request held a 24-token prompt and 1,000 reply tokens. One acceptance checked all 1,000 reply tokens at positions 24 through 1023 and one further token supplied by the caller, against the integer model's first choices. The timer started after the model had produced the tokens and the prover had written the proof. [Fixture and expected output](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md)

| Slurm job | What ran on the full-size proof | Median elapsed time for one accepted proof |
| --- | --- | --- |
| 7683 | Standalone Bend and upstream C++ alternated within one allocation. This Bend build predates the extension multiplication optimization. | Bend 665.120 s, C++ 19.098 s |
| 7669 | The hybrid prototype and C++ alternated. Lean OnBytes ran afterward in its own series. | Hybrid 91.356 s, C++ 19.761 s, OnBytes 95.482 s |
| 7668 | The theorem-linked Lean shell command ran three times. Its timer included building a parser tool and linking a helper on each call. | 1,141.27 s |

Job 7683 gives the direct Linux comparison for standalone Bend against C++. Comparing the two separate Linux Lean jobs also changes the program and the work inside the timer. The later M4 Max experiment pairs the optimized standalone Bend executable directly with Lean OnBytes. [M4 measurements](m4-standalone.md)

## Independent Bend verification

Job 7683 measured one complete invocation of each executable at a time. Both read the public configuration, verification key and selected leaf, request, next token and proof, and checked the caller's commitment ID. Standalone Bend performed all three proof stages itself. At each fixture size the harness checked file hashes, discarded one verified warmup per program and measured three fresh processes per program. The pair order was C++/Bend, Bend/C++, C++/Bend. Every process ran with an empty executable search path, matched the four expected closing lines including its build ID, and exited 0. [Measurement harness](../../scripts/benchmark-standalone.py)

| Exact fixture | Executable | Wall seconds in sample order | Median (s) | Peak RSS range (MiB) |
| --- | --- | --- | ---: | ---: |
| accepted-proof | C++ | 1.454, 1.509, 1.371 | 1.454 | 151.2 to 151.9 |
| accepted-proof | Standalone Bend | 14.657, 14.784, 14.727 | 14.727 | 801.5 to 803.2 |
| full-size | C++ | 19.115, 19.098, 19.077 | 19.098 | 3,360.3 to 3,361.4 |
| full-size | Standalone Bend | 665.120, 666.087, 659.952 | 665.120 | 11,096.8 to 11,100.2 |

Wall time includes process startup, input reads from a warm filesystem cache, verification and output through process exit. Peak RSS is the maximum resident memory GNU time reported for each invocation. The last column shows the smallest and largest of those peaks across the three samples. The full-size Bend median was 11 min 5 s, or 34.83 times the C++ median, with peak memory of 10.84 GiB. The ratio was 10.13 on the small proof. Job 7683 took 52 min 20 s including setup and all 16 calls, and exited `0:0`. [Raw samples, warmups, checksums and binary identities](notes/lucid-standalone.tsv)

The job requested four CPU slots, 160 GiB of RAM and zero GPUs. Other cluster users shared the host. Our other jobs finished or stopped before the warmups. The C++ request stage used `-j 1`. The Bend source ran sequentially with the default runtime pool. The job set `BEND_THREADS=1` and did not observe the worker count. A separate probe linked with the same argument shim on 2026-11-24 showed four workers on a four-CPU allocation at both `BEND_THREADS=1` and `BEND_THREADS=16`. The runtime without the shim honored `+RTS --threads N`. [Native argument shim](../../src/native/verify_main.c) · [Worker-count probe](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/19#issuecomment-7126288622)

## Compiled baselines

In job 7669 the hybrid Bend entry point checked the public input and then handed the proof to a C++ worker containing selected Bend kernels. The hybrid times include both processes. Lean OnBytes is upstream's separate Lean translation of the C++ verification logic, compiled ahead of time. [Hybrid design](../adr/native-kernels.md) · [OnBytes program](onbytes.md)

| Exact fixture | Executable | Wall seconds in sample order | Median (s) | Peak RSS range (MiB) |
| --- | --- | --- | ---: | ---: |
| accepted-proof | C++ | 1.322, 1.322, 1.304 | 1.322 | 151.2 to 151.9 |
| accepted-proof | Hybrid Bend CLI | 4.533, 4.518, 4.506 | 4.518 | 150.3 to 151.2 |
| accepted-proof | Lean OnBytes | 6.276, 5.721, 5.814 | 5.814 | 260.2 to 260.9 |
| full-size | C++ | 21.425, 19.761, 19.377 | 19.761 | 3,363.4 to 3,365.0 |
| full-size | Hybrid Bend CLI | 92.633, 91.356, 83.124 | 91.356 | 3,360.7 to 3,361.6 |
| full-size | Lean OnBytes | 94.841, 95.482, 97.891 | 95.482 | 5,070.9 to 5,075.7 |

The harness verified fixture checksums first and timed all three samples without a separate warmup. Each call used `-j 1` for the request stage. The C++ driver can run proof stages in separate processes at the same time. OnBytes runs its stages sequentially. Each C++ and hybrid call exited 0 and matched four expected closing lines. Each OnBytes call exited 0 and matched the final two, the machine-readable record and `YES`. GNU time reported peak RSS for each invocation. Combined memory across simultaneous stage processes was unmeasured. A separate allocation built the Lean ProgramGuard on the same host during this run. Job 7669 finished with exit 0 in 14 min 19 s. [C++ and hybrid harness](../../scripts/e2e.py) · [OnBytes harness](../../scripts/onbytes-test.py)

In this series the full-size hybrid took 4.62 times the C++ median and 0.957 times the OnBytes median. A separate refusal check changed one bit in the small proof. OnBytes returned `NO: proof-refused` and exited 1 after 2.780 s.

## Theorem-linked verifier

Job 7668 timed the Linux x86-64 shell command that applies the executable form of Lean's `verify` to the claim in the caller's files. Each timed command compiled the C++ plan tool, parsed the public inputs and proof, linked a fresh native helper library, ran the Lean evaluation with `-j1` and printed its verdict. The three times give the cost of invoking that entire command. The run did not record separate times for compilation, linking or proof checks. [Driver](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/tools/lean-verify/lean_verify.sh) · [Parser](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/tools/parser/parse_files.sh)

| Sample | Wall seconds | Peak RSS (KiB) |
| ---: | ---: | ---: |
| 1 | 1,141.27 | 10,744,408 |
| 2 | 1,118.94 | 10,745,348 |
| 3 | 1,164.27 | 10,754,136 |

All three full-size calls exited 0 and printed `VERDICT: ACCEPT (exact match)`. The median was 19 min 1 s. The total job duration, 1 h 21 min 23 s with exit `0:0`, includes setup. Before timing, the source-tree checker passed on 29,550 files, Lake built `Johnson.PVR.ProgramGuard` (7,813 tasks), and all 5,056 reusable native helper objects were available. ProgramGuard reported `propext`, `Classical.choice` and `Quot.sound` for `PV.Program.verdictOf_is_verify`. The upstream theorem gives the assumptions on the public setup and hash oracle and specifies which parts of the executable are covered. [Program guard](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/Johnson/PVR/ProgramGuard.lean) · [Theorem scope](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md)

## Build and input identities

The host ran Ubuntu 24.04.4 LTS and Linux 6.8.0-147-generic. All jobs used the same full-size proof, SHA-256 `efa762e20f72b64e183ad6f688eccf5b2b79649928d8e3a2a96645645dd08af9`, and caller-supplied ID `7a285919b43961861d9839530c26725accf26aa6d74e3c2afa31b9dc6bcd18fe`. [File checksums](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/SHA256SUMS) · [Protocol revision](../../upstream.lock)

| Linux executable | SHA-256 |
| --- | --- |
| Standalone Bend `verify-bend` | `ac8feeee3e0f15dec6ef753e6667e8f47b74faea95a40e10b8119f2fc38a0560` |
| C++ `cp_verify` | `7f9efc1e86a848a3715c6cc870e465ac2a1c5e8fd1eac09e4809023de7604394` |
| Hybrid Bend `verify` CLI | `4fc44c25330c607f632d8889a467bf797ce4ae692478c20fc3870d7a084bb7c0` |
| Hybrid `bend_verify` worker | `be693435d97e0e4fef43d54b60ff17b9032ac82ad09babcff5b85733b22e123a` |
| Lean `verify-on-bytes` | `7f350fde8cac9e26ac6a654dd51bf796195d6d7f7edaf75ce63bec49cd945e3c` |

The standalone Linux and macOS builds of verifier checkout `f82965b0f7dd2f8c1bece480381c03025273f404` reported source digest `4bc6ecdd34e1c59e5b65518a3752a1a8b8797f6024bc5cefd5bb906a59f67df5`. Bend 2.0.40 generated C and Ubuntu Clang 18.1.3 compiled it with `-std=c11 -O3 -lpthread -lm`. The compiled baselines came from verifier checkout `f42bacff28aa1a1684e2465a59e7dd4d6f905879`. The hybrid used Clang 18.1.3 at `-O3` for the CLI and `-O2` for its worker. The reference used GCC 13.3.0 with `-O2 -fno-ipa-modref` and the pinned hardening flags. OnBytes used the official Lean 4.29.1 release with Lake and its bundled C toolchain. [Standalone build](../../scripts/build-standalone.py) · [Hybrid worker build](../../scripts/build-verifier.sh) · [Reference build](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/build.sh#L328-L353) · [Lean build](../../scripts/onbytes-build.sh)

A separate conformance job, 7685, checked the same standalone Linux binary against all four published proofs on another CPU node. The job and all four calls exited 0, and the results matched the expected four closing lines. Both exact-match proofs printed `YES`. The small clipped proof printed `WITHIN LIMITS: clipped-gap C=9244130 theta=323343 cap=1 s=16 sh=8` and the full clipped proof printed `WITHIN LIMITS: clipped-gap C=25856 theta=512 cap=1 s=15 sh=8`. Run `make standalone-full` to check those four verdicts. [Conformance harness](../../scripts/standalone-test.py)

## Reproduction

To time standalone Bend and C++ locally, run `make benchmark-standalone`. On the Lucid login node, submit the following from a committed checkout. Use the recorded verifier revision for the historical executable. The job writes `results.json`, `report.md`, per-call output and timing files under `build/standalone-JOBID/measurements/`. [Standalone batch script](../../scripts/cluster/standalone-benchmark.sh)

```sh
sinfo -o '%P %a %f %c %m %l'
job=$(sbatch --parsable --nodelist=h100-sxm-8-0 scripts/cluster/standalone-benchmark.sh)
sacct -j "$job" --format=JobID,State,Elapsed,ExitCode
```

To repeat the compiled baselines and theorem-linked driver workloads, the following script runs them in one allocation. It writes the revision, compiler and command logs, and the theorem driver's stdout, stderr and timing for each sample under `build/lucid-JOBID/`. Both batch scripts build on node-local disk. On the measurement date, the scheduler listed the `main` partition for CPU jobs on this node. [Lean batch script](../../scripts/cluster/lean-benchmark.sh) · [Lucid CPU jobs](https://docs.vcf.lucidcomputing.ai/guides/running-jobs/cpu-jobs/)

```sh
job=$(sbatch --parsable --nodelist=h100-sxm-8-0 scripts/cluster/lean-benchmark.sh)
squeue -j "$job"
sacct -j "$job" --format=JobID,State,ExitCode,Elapsed,AllocCPUS,MaxRSS
```
