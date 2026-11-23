# Whole-call measurements on Lucid

> Status: living

This experiment exercises the pinned Linux x86-64 verifier that calls the executable form of Lean's `verify`. The fixture is the exact-match `examples/full-size` synthetic proof. The upstream command reads the configuration, key, request, token, proof and caller's commitment ID. Success requires exit 0 and exactly `VERDICT: ACCEPT (exact match)` on stdout. Its parser, compiler, executable and the actual run sit outside the Lean theorem. The separate native Lean OnBytes executable implements a translation of the C++ checks. [Lean command and verdict contract](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/tools/lean-verify/README.md) · [Theorem scope](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md) · [OnBytes](onbytes.md)

The full-size proof is 18,779,540 bytes with SHA-256 `efa762e20f72b64e183ad6f688eccf5b2b79649928d8e3a2a96645645dd08af9`. Its caller-supplied ID is `7a285919b43961861d9839530c26725accf26aa6d74e3c2afa31b9dc6bcd18fe`. The expected claim covers request tokens 24 through 1023 and the next token. [Fixture and expected output](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md) · [File checksums](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/SHA256SUMS)

## Theorem-linked verifier

All three full-size processes exited 0 and printed exactly `VERDICT: ACCEPT (exact match)`. The median was **1,141.27 seconds** (19 min 1 s). Slurm job 7668 finished with state `COMPLETED` and exit code `0:0` after 1 h 21 min 23 s including setup. The timer for each sample covered the complete six-input `tools/lean-verify/lean_verify.sh` command. [Pinned verifier](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/tools/lean-verify/lean_verify.sh)

| Sample | Wall seconds | Peak RSS (KiB) |
| ---: | ---: | ---: |
| 1 | 1,141.27 | 10,744,408 |
| 2 | 1,118.94 | 10,745,348 |
| 3 | 1,164.27 | 10,754,136 |

Before timing, the repository source-tree checker passed on 29,550 files, Lake built `Johnson.PVR.ProgramGuard` (7,813 tasks), and all 5,056 reusable native helper objects were available. ProgramGuard reported `propext`, `Classical.choice` and `Quot.sound` for `PV.Program.verdictOf_is_verify`. On this full-size fixture, the theorem-linked median was 57.75 times the C++ median, 11.95 times the OnBytes median, and 12.49 times the hybrid median. [Program guard](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/Johnson/PVR/ProgramGuard.lean)

## Compiled baselines

Job 7669 finished with exit 0 in 14 min 19 s. Each sample below started a fresh process, exited zero, and matched the expected closing record and `YES`. The fixture checksums were verified before timing. There was no separate untimed verification warmup. C++ and the hybrid ran in alternating order per fixture, followed by the OnBytes series. The ProgramGuard build used a separate CPU allocation on the same physical host during these samples, so the timings include any shared cache or memory-bandwidth contention. A flipped bit in the small proof produced `NO: proof-refused` from OnBytes, exit 1, after 2.780 s. [Comparison harness](../../scripts/e2e.py) · [OnBytes harness](../../scripts/onbytes-test.py)

| Fixture | Executable | Wall seconds in order | Median (s) | Peak RSS range (MiB) |
| --- | --- | --- | ---: | ---: |
| accepted-proof | C++ | 1.322, 1.322, 1.304 | 1.322 | 151.2–151.9 |
| accepted-proof | Hybrid Bend CLI | 4.533, 4.518, 4.506 | 4.518 | 150.3–151.2 |
| accepted-proof | Lean OnBytes | 6.276, 5.721, 5.814 | 5.814 | 260.2–260.9 |
| full-size | C++ | 21.425, 19.761, 19.377 | 19.761 | 3,363.4–3,365.0 |
| full-size | Hybrid Bend CLI | 92.633, 91.356, 83.124 | 91.356 | 3,360.7–3,361.6 |
| full-size | Lean OnBytes | 94.841, 95.482, 97.891 | 95.482 | 5,070.9–5,075.7 |

| Executable | SHA-256 |
| --- | --- |
| C++ `cp_verify` | `7f9efc1e86a848a3715c6cc870e465ac2a1c5e8fd1eac09e4809023de7604394` |
| Bend `verify` CLI | `4fc44c25330c607f632d8889a467bf797ce4ae692478c20fc3870d7a084bb7c0` |
| Hybrid `bend_verify` worker | `be693435d97e0e4fef43d54b60ff17b9032ac82ad09babcff5b85733b22e123a` |
| Lean `verify-on-bytes` | `7f350fde8cac9e26ac6a654dd51bf796195d6d7f7edaf75ce63bec49cd945e3c` |

The hybrid used Ubuntu Clang 18.1.3, `-O3` for its public entry and `-O2` for its worker. The reference used GCC 13.3.0 with the pinned Linux flags (`-O2 -fno-ipa-modref` and hardening). Native OnBytes used the official Lean 4.29.1 release with Lake and the bundled C toolchain. The full-size hybrid took 4.62 times the C++ median and 0.957 times the OnBytes median on this host. [Hybrid worker build](../../scripts/build-verifier.sh) · [Public CLI build](../../scripts/build-cli.sh) · [Reference build](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/verifier/build.sh) · [Lean build](../../scripts/onbytes-build.sh)

## Reproduction

Submit from a committed repository checkout on the login node. Read the job state and exit status from `sacct`. The script saves the compiler and command logs, per-call stdout and stderr, process timing and checkout revision under `build/lucid-JOBID`. It builds on node-local disk because the compiled packages and Lean artifacts can exceed the space remaining in a shared home. [Batch script](../../scripts/cluster/lean-benchmark.sh) · [Lucid CPU jobs](https://docs.vcf.lucidcomputing.ai/guides/running-jobs/cpu-jobs/) · [Storage](https://docs.vcf.lucidcomputing.ai/storage/)

```sh
sinfo -o '%P %a %f %c %m %l'
job=$(sbatch --parsable --nodelist=h100-sxm-8-0 scripts/cluster/lean-benchmark.sh)
squeue -j "$job"
sacct -j "$job" --format=JobID,State,ExitCode,Elapsed,AllocCPUS,MaxRSS
```

On 2026-11-23 the live scheduler listed `main` for batch jobs on the H100 SXM server. The documented `cpu` partition was absent. The allocation requested CPUs and memory with zero GPUs. The host reported Intel Xeon Platinum 8480CL, Ubuntu 24.04.4 LTS, Linux 6.8.0-147-generic and g++ 13.3.0. The verifier baseline source was `f42bacff28aa1a1684e2465a59e7dd4d6f905879`. The upstream revision is in [upstream.lock](../../upstream.lock). [Cluster overview](https://docs.vcf.lucidcomputing.ai/)

Both compiled comparators receive `-j 1` for the request stage. OnBytes runs sequentially. Each process reads identical fixture bytes, including the named ID. The C++ and hybrid harness checks all four closing output lines against the published fixture, including the source build digest. The OnBytes harness checks both final lines. All three report per-process wall time and Linux GNU time maximum RSS in KiB, converted to MiB. The theorem-linked command always compiles the parser's plan tool and links a new helper library inside its whole call. Package setup, the `Johnson.PVR.ProgramGuard` build and creation of reusable native objects happen before its timer starts. Its Lean evaluation runs with `-j1`. [C++ and hybrid harness](../../scripts/e2e.py) · [OnBytes harness](../../scripts/onbytes-test.py) · [Theorem-linked driver](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/tools/lean-verify/lean_verify.sh)

## Independent Bend verification

The standalone comparison builds the native `verify-bend` CLI and the pinned C++ oracle before timing. It copies the executables and public parameters into an isolated directory, checks every file listed in the fixture's `SHA256SUMS`, and alternates three fresh processes per executable at each exact fixture size. Each process starts with an empty executable search path. The complete command reads the caller's files and verifies the public statement, key, leaf and request. Every sample must return the four published closing lines with its own source identity and exit 0. [Measurement harness](../../scripts/benchmark-standalone.py) · [Slurm job](../../scripts/cluster/standalone-benchmark.sh)

```sh
make benchmark-standalone
# On the Lucid login node, submit the same measurement on the H100 SXM CPU.
job=$(sbatch --parsable --nodelist=h100-sxm-8-0 scripts/cluster/standalone-benchmark.sh)
sacct -j "$job" --format=JobID,State,Elapsed,ExitCode
```

Each result directory contains per-process stdout, stderr and time output, `results.json` with source and binary identities, and `report.md` with the measured wall times and peak RSS. The worker uses `BEND_THREADS=1` for Bend and `-j 1` for C++. [Benchmark target](../../Makefile)
