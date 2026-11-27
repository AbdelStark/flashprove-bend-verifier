# Performance contract

> Status: living

## What one sample measures

One sample is the time a CPU verifier takes to check one proof that is already on disk. Each timed call starts a fresh process. The process reads the public configuration, checks the key against the caller's commitment ID, authenticates the selected leaf, verifies the request proof against the supplied tokens, prints the verdict and exits. Downloading the fixtures, generating the model output and proving all happen before the clock starts. [Verification stages](verifier.md#what-the-caller-trusts)

The headline workload is one exact-match proof for a model with Llama 4 Maverick's dimensions and synthetic weights. The request holds 24 prompt tokens and 1,000 reply tokens. The proof covers the reply and the proposed next token, ID 52599. Acceptance means each of those 1,001 tokens ranks first under the committed integer model, given the tokens before it. The request proof alone is 18,779,540 bytes. The same call also checks a 3,290,496-byte key file and a 2,942,944-byte leaf file. [Full-size fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md#what-the-yes-says)

**Wall time** runs from launch to exit and includes startup, file reads, verification and reporting. **CPU time**, where recorded, is the time spent executing in user and kernel mode. **Peak RSS** is the most resident memory the operating system reports for the timed process. For a driver that starts child processes, it does not give their combined total. MiB and GiB are powers of 1,024.

## Measurements on record

The latest M4 Max rerun measures the current build against Lean OnBytes at 1, 12 and 16 workers and against C++, with a fresh worker screen and the full conformance runs. The speed pass holds the before-and-after comparison for the last optimization. The Xeon rerun repeats the same measurements on an Intel Xeon Platinum 8480CL, and compares the build with `9d00a32` on that host. [Latest M4 measurements](../research/rerun-2026-11-26.md) · [Latest Xeon measurements](../research/xeon-rerun-2026-11-27.md) · [Speed pass](../research/speed-pass.md)

Lean OnBytes is a native executable built from a Lean translation of the C++ file checks. The theorem-linked Linux driver runs the verifier defined in the upstream Lean development. Checking that development's theorem is separate from either timed run. Compare ratios only within one paired experiment, because the M4 and Xeon runs use different CPUs and native compilers. [Upstream theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md) · [Assurance contract](assurance.md)

## Reproduce a measurement

Start from the repository root with `make bootstrap upstream`. Each command below builds what it needs before timing. On Linux the harness uses GNU `/usr/bin/time`. [Build prerequisites](../../CONTRIBUTING.md#build-a-verifier-you-can-check)

| Question | Command | Where to read the result |
| --- | --- | --- |
| Which Bend worker count is fastest on this CPU? | `make benchmark-workers BENCH_ARGS="--worker-counts 1 2 4 8 16"`. Add counts that suit the host. | The JSON records each verified warmup, every quiet call and the selected count. Publish a fresh OnBytes pairing, not the screen itself. |
| Did a Bend change reduce latency? | Keep the earlier executable with its `.digest` file beside it. On the new checkout, run `make benchmark-revisions BENCH_ARGS="--before /absolute/path/to/verify-bend --workers 1"`, then again with 16 workers. | Both warmups check the observed pool size. Every timed call uses the same explicit worker count and checks the four closing lines. [Harness](../../scripts/benchmark-standalone.py) |
| How do standalone Bend and Lean OnBytes compare on the full-size proof? | `make benchmark-onbytes` on macOS or Linux. To include an earlier Bend build, add `BENCH_ARGS="--before /absolute/path/to/verify-bend"` and keep its `.digest` beside it. | The printed directory holds `report.md`, the per-call timings and closing records in `results.json`, and the raw stdout, stderr and time reports. |
| How does standalone Bend compare with upstream C++? | `make benchmark-standalone` on macOS or Linux. It runs the small and full-size exact-match proofs. | `report.md` in the printed directory gives times, median ratios and peak RSS in KiB. `results.json` holds every sample and verdict record. [Harness](../../scripts/benchmark-standalone.py) |
| How long does Lean OnBytes take on its own? | `make benchmark-lean` runs three consecutive calls at each size, then checks a damaged small proof. | The terminal shows each call and the median for each genuine proof. This harness does not discard a warmup. [Harness](../../scripts/onbytes-test.py) |

## Profiling one call

On macOS, `make profile FIXTURE=full-size` records stage times and samples stacks. The percentages describe the sampling interval. On Linux the target prints a `perf` command instead. `make spikes` times field multiplication and hashing on their own, and `make fresh-proof` makes a new small proof on an H100 and checks it on the CPU. [Profiler](../../scripts/profile.py) · [Where the request spends its time](../research/speed-pass.md#where-time-went) · [H100 procedure](../research/fresh-proof.md)

## Measurement protocol

1. Build each program before timing. Record the verifier revision, the protocol and toolchain pins, the compiler flags, the executable hashes and any source digest the verdict reports. Name the fixture, its checksum and the caller's policy.
2. Use one host or one scheduler allocation. Record the CPU, OS, memory measurement method, worker settings and any other load. For scaling tests, confirm the worker count the runtime actually used: `-j N -timing` prints the pool size on stderr. Leave `-timing` off the measured calls. [Worker-count probe](https://github.com/AbdelStark/flashprove-bend-verifier/issues/19#issuecomment-7126288622)
3. Check the fixture against its checksum manifest. For paired measurements, discard one verified warmup per binary and fixture, then time three fresh processes per binary with a warm file cache. Alternate which program goes first in each pair. When an earlier Bend build is included, rotate all three programs through each launch position. Give the standalone verifier an empty executable search path.
4. Validate every call. For paired Bend comparisons, require exit status zero and the fixture's four expected closing lines for that executable. Record each wall time, peak RSS and any setup inside the timed command. Report the median of each binary's three times. The wall-time ratio is the Bend median divided by the comparator's median.

## Requirements

| Requirement | Target | Evidence | Status |
| --- | --- | --- | --- |
| **REQ-PERF-2** | `-timing` reports public input, key, leaf, request and total wall time in milliseconds on stderr. | Compare stdout and the verdict with and without the option. `make standalone-test` checks the stage lines and that stdout does not change. | Met. |
| **REQ-PERF-3** | With one Bend worker, median full-size exact-match wall time is at most eight times the C++ median on the same host. Bend's peak RSS is at most 7 GB. | `make benchmark-standalone` runs the measurement protocol with one request-stage thread for C++. Record the stage timings. | Met on the M4 Max (2.24× C++, 1.89 GiB) and the Xeon (1.87× C++, 1.89 GiB). [M4](../research/rerun-2026-11-26.md#bend-and-c-one-worker-each) · [Xeon](../research/xeon-rerun-2026-11-27.md#bend-and-c-one-worker-each) |
| **REQ-PERF-4** | With 16 Bend workers, median full-size exact-match wall time is at most the single-thread C++ median on the same host. | `make benchmark-workers` publishes a verified scaling series at 1, 2, 4, 8 and 16 workers. [M4 screen](../research/rerun-2026-11-26.md#worker-screen) · [Xeon screen](../research/xeon-rerun-2026-11-27.md#worker-screen) | Open: 9.90 s against 8.06 s on the M4 Max, 21.10 s against 20.79 s on the Xeon. [#23](https://github.com/AbdelStark/flashprove-bend-verifier/issues/23) |
| **REQ-PAR-1** | Changing the worker count changes neither stdout nor the exit status. When several faults are present, the verifier reports the first failure in stage order (key, leaf, request), then in file order. | `make worker-parity` compares all four fixtures, both altered-copy tables and 64 seeded differential cases at 1 and 16 workers. A copy with a bad key and an empty request proof checks failure order at 1, 2, 4, 8 and 16. Each run keeps the exit code and both output streams per case under `build/worker-parity-*`. [Job 7725 results and build identities](../research/worker-parity.json) | Met. |
| **REQ-PERF-5** | CI fails if a change raises small exact-match CPU time beyond the published tolerance. | Keep the budget relative to a C++ run on the same runner, and show that an injected slowdown trips the check. `make perf-gate` runs on every commit: the median CPU ratio of Bend with one worker to `cp_verify -j 1` on accepted-proof must stay within `scripts/perf-budget.json`. | Met: budget 1.85× + 10%. Ten unchanged calls on Intel Xeon 6975P-C and AMD EPYC 7763 runners measured 1.77–1.84×. A second key-stage check measured 2.12–2.61× and failed on all five runners. [#21](https://github.com/AbdelStark/flashprove-bend-verifier/issues/21) |
| **REQ-PERF-6** | Standalone Bend verifies the full-size exact-match proof in less median wall time than native Lean OnBytes on the same CPU. | `make benchmark-onbytes` follows the measurement protocol. Publish one-worker results separately from tuned worker counts. Report the earlier Bend executable, the candidate and Lean. | Met on the M4 Max and the Xeon. [M4](../research/rerun-2026-11-26.md#bend-and-lean-onbytes-full-size-proof) · [Xeon](../research/xeon-rerun-2026-11-27.md#bend-and-lean-onbytes-full-size-proof) |

These speed and memory budgets are engineering targets. To change one, edit it here and give the whole-verifier measurement that justifies the change. [Performance tracker](https://github.com/AbdelStark/flashprove-bend-verifier/issues/23)

## Reviewing an optimization

- Find the expensive operation in a profile. Time the same whole call before and after, and keep the change only if that call gets faster. Report kernel throughput separately.
- Run `make ci`, `make standalone-full`, `make standalone-extended` and `make fuzz` on both revisions. For each of the four fixtures, the accepted records may differ only in the source build marker. Check the exit status as well. Run the field, extension, hash and transcript vectors on both the JS and native lanes.
- Keep the verification logic in checked Bend, and keep the native entry's C file limited to argument handling. Keep field elements, extension elements and their vectors behind their existing module interfaces. A change that adds parallel work must also meet REQ-PAR-1.
