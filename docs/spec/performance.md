# Performance contract

> Status: living

## What one sample measures

One sample measures how long a CPU verifier takes to check one proof already on disk. Each timed call starts a fresh process. It reads the public configuration, checks the key against the caller's commitment ID, authenticates the selected leaf, verifies the request proof against the supplied tokens, prints the verdict and exits. Downloading the fixtures, generating the model output and producing its proof all happen before this measurement. [Verification stages](verifier.md#what-the-caller-trusts)

The headline workload is one exact-match proof for a model with Llama 4 Maverick's dimensions and synthetic weights. The request contains 24 prompt tokens and 1,000 reply tokens. The proof covers the reply and the proposed next token, ID 52599. Acceptance means that each of those 1,001 tokens ranks first under the committed integer model given the preceding tokens. The request proof alone is 18,779,540 bytes. The same call also checks a 3,290,496-byte key file and a 2,942,944-byte leaf file. [Full-size fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md#what-the-yes-says)

**Wall time** is elapsed time from launch through exit, including startup, file reads, verification and reporting. **CPU time**, where recorded, sums time spent executing in user and kernel mode. **Peak RSS** is the largest amount of resident memory the operating system reports for the timed process. For drivers with child processes, that figure does not give their simultaneous total. MiB and GiB use powers of 1,024.

## Measurements on record

| CPU and experiment | Median wall seconds per full-size proof | How to read the result |
| --- | --- | --- |
| Apple M4 Max, paired runs | Standalone Bend **254.945**, Lean OnBytes **58.693** | Both binaries verified the same proof in three alternating pairs. Bend took 4.34 times as long by median. [Samples and binary identities](../research/m4-standalone.md) |
| Same M4 Max and binaries, repeated experiment | Standalone Bend **287.03**, Lean OnBytes **64.58** | The repeat gave a wall-time ratio of 4.44. [Replay samples](https://github.com/AbdelStark/fv-flashprove-bend-verifier/pull/38) |
| Lucid Xeon, paired runs | Earlier standalone Bend **665.120**, C++ **19.098** | Both ran in one CPU allocation before the Bend field arithmetic optimization. [Job 7683](../research/lucid.md#independent-bend-verification) |
| Same Xeon, separate Lean jobs | Lean OnBytes **95.482**, theorem-linked Lean command **1,141.270** | These jobs timed different programs under different loads. The theorem-linked command rebuilt its parser tool and relinked a helper inside each timed call. [Jobs 7668 and 7669](../research/lucid.md#theorem-linked-verifier) |

Both M4 experiments discarded a verified warmup per program, then alternated the order of three measured pairs on a warm filesystem cache. The original measured wall time with a monotonic clock around the timed subprocess. The replay read the `real` seconds reported by macOS `/usr/bin/time -l`. Each row gives the medians of that experiment's three samples per program.

Lean OnBytes is a native executable built from a Lean translation of the C++ file checks. The theorem-linked Linux driver runs the verifier defined in the upstream Lean development. Checking that development's theorem is a separate activity from either timed invocation. Read ratios within a paired experiment. The Lucid and M4 runs differ in CPU, native compiler and Bend revision. [Upstream theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md) · [Assurance contract](assurance.md)

## Reproduce a measurement

Start from the repository root with `make bootstrap upstream`. The full-size Bend process peaked around 10.84 GiB in the recorded runs. Each command below builds its prerequisites before timing. Linux uses GNU `/usr/bin/time`. [Build prerequisites](../../CONTRIBUTING.md#build-a-verifier-you-can-check)

| Question | Command or recipe | Where to read the result |
| --- | --- | --- |
| How long do standalone Bend and Lean OnBytes take on the same full-size proof? | Run `make benchmark-onbytes` on macOS or Linux. To include an earlier Bend build, supply `BENCH_ARGS="--before /absolute/path/to/verify-bend"`. Keep its `.digest` beside it. | The printed directory contains `report.md`, the per-call timings and closing records in `results.json`, and raw stdout, stderr and system time reports. The [original M4 recipe](../research/m4-standalone.md#repeat-the-comparison) reproduces the historical pairing. |
| How does standalone Bend compare with upstream C++? | `make benchmark-standalone` on macOS or Linux. It checks the small and full-size exact-match proofs. | Open `report.md` in the printed results directory for the times, median ratios and peak RSS in KiB. The individual samples and verdict records are in `results.json`. [Harness](../../scripts/benchmark-standalone.py) |
| How long does Lean OnBytes take on its own? | `make benchmark-lean` runs three consecutive calls at each size, then checks a damaged small proof. | The terminal shows each call and the median for each genuine proof. This harness uses no discarded warmup. [Harness](../../scripts/onbytes-test.py) |
| What did the older hybrid verifier measure? | `make benchmark` pairs the hybrid CLI with upstream C++ at both sizes. | The terminal prints per-program medians. The hybrid runs a C++ protocol driver with Bend kernels. [Hybrid design](../adr/native-kernels.md) |

## Where Bend spends the time

In a separate full-size M4 call, Bend's own timers recorded 0.7 s for public inputs, 2.6 s for the key, 0.7 s for the leaf and 287.8 s for the request proof. The request stage accounted for most of that call. These times came from one run with `-timing`. The headline table uses medians measured from outside the process. [Stage timings from the optimization](https://github.com/AbdelStark/fv-flashprove-bend-verifier/pull/37) · [Timer implementation](../../src/standalone.bend)

To inspect one call, `make profile FIXTURE=full-size` records stage times and samples stacks on macOS. The percentages describe the sampling interval. On Linux the target prints a `perf` command. The kernel experiments from `make spikes` measure operations such as field multiplication or hashing in isolation. The H100 experiment uses `make fresh-proof` to create a new small proof and check it on CPU. [Profiler](../../scripts/profile.py) · [Kernel measurements](../research/bend2-assessment.md) · [H100 procedure](../research/fresh-proof.md)

## Measurement protocol

1. Build each program before timing. Record the verifier revision, protocol and toolchain pins, compiler flags, executable hashes, and any source digest reported in the verdict. Name the fixture, its checksum and the caller's policy.
2. Use one host or scheduler allocation. Record the CPU, OS, memory measurement method, worker settings and any concurrent load. For scaling tests, observe the runtime worker count. Use `-j N -timing` to read the actual pool size on stderr. Omit `-timing` from the measured calls. Earlier standalone builds used the runtime default and ignored `BEND_THREADS`. [Worker-count probe](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/19#issuecomment-7126288622)
3. Verify the fixture against its checksum manifest. For paired measurements, discard one verified warmup per binary and fixture. Then time three fresh processes per binary with a warm filesystem cache. Alternate which program goes first in each pair. When including an earlier Bend build, rotate all three programs through each launch position. Give the standalone verifier an empty executable search path.
4. Validate every call. For the paired Bend comparisons, require exit zero and match the four closing lines with the fixture's expected output for that executable. Record each wall time, peak resident memory and any setup inside the timed command. For each binary, report the middle of its three measured times. Divide the Bend median by the comparator median to get the wall-time ratio.

## Requirements

| Requirement | Target | Evidence |
| --- | --- | --- |
| **REQ-PERF-2** | `-timing` reports public input, key, leaf, request and total wall time in milliseconds on stderr. | Compare stdout and verdict with and without the option. On macOS, `make profile` records stage timings and samples stacks. On Linux the target prints the corresponding `perf` command. |
| **REQ-PERF-3** | With one Bend worker, median full-size exact-match wall time is at most eight times the C++ median in the same Lucid job. Bend's peak RSS is at most 7 GB. | Run the measurement protocol with one request-stage thread for C++ and record the stage timings. |
| **REQ-PERF-4** | With 16 Bend workers, median full-size exact-match wall time is at most the single-request-thread C++ median in the same job. | Publish a verified scaling series at 1, 2, 4, 8 and 16 workers. |
| **REQ-PAR-1** | Changing the worker count preserves stdout and exit status. When several faults are present, the verifier reports the first failure in sequential stage order (key, leaf, request), then in file order. | `make worker-parity` compares all four fixtures, both altered-copy tables and 64 seeded differential cases at 1 and 16 workers. A copy with a bad key and empty request proof checks failure order at 1, 2, 4, 8 and 16. Each run saves the exit code and both output streams per case under `build/worker-parity-*`. [Job 7725 results and build identities](../research/worker-parity.json) |
| **REQ-PERF-5** | CI fails if a change increases small exact-match CPU time beyond the published tolerance. | Keep the budget relative to a C++ run on the same runner and demonstrate that an injected slowdown trips the check. |
| **REQ-PERF-6** | Standalone Bend verifies the full-size exact-match proof in less median wall time than native Lean OnBytes on the same CPU. | Use the measurement protocol and publish results for one Bend worker separately from tuned worker counts. Report the earlier Bend executable, the candidate, and Lean. [Comparison tracker](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/39) |

The speed and memory budgets are engineering targets. Early field measurements and a 16-core fork-join hashing benchmark informed them. The latter exposed parallel work explicitly. Change a target here and give the whole-verifier measurement that justifies the change. [Kernel experiments](../research/bend2-assessment.md) · [Performance tracker](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/23)

## Reviewing an optimization

- Identify the expensive operation in a profile. Measure the same whole call before and after. Keep a speed change when it improves that call. Report kernel throughput separately.
- Run `make ci`, `make standalone-full`, `make standalone-extended` and `make fuzz` on both revisions. For each of the four fixtures, only the source build marker may differ between accepted records. Check the exit status as well. Run field, extension, hash and transcript vectors on the JS and native lanes.
- Keep verification logic in checked Bend and the native entry's C shim limited to argument handling. Keep field elements, extension elements and their vectors behind their existing module interfaces. A change that adds parallel work must also satisfy REQ-PAR-1.
