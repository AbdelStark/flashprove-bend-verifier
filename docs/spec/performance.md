# Performance contract

> Status: living

## What one sample measures

One sample measures how long a CPU verifier takes to check one proof already on disk. Each timed call starts a fresh process. It reads the public configuration, checks the key against the caller's commitment ID, authenticates the selected leaf, verifies the request proof against the supplied tokens, prints the verdict and exits. Downloading the fixtures, generating the model output and producing its proof all happen before this measurement. [Verification stages](verifier.md#what-the-caller-trusts)

The headline workload is one exact-match proof for a model with Llama 4 Maverick's dimensions and synthetic weights. The request contains 24 prompt tokens and 1,000 reply tokens. The proof covers the reply and the proposed next token, ID 52599. Acceptance means that each of those 1,001 tokens ranks first under the committed integer model given the preceding tokens. The request proof alone is 18,779,540 bytes. The same call also checks a 3,290,496-byte key file and a 2,942,944-byte leaf file. [Full-size fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md#what-the-yes-says)

**Wall time** is elapsed time from launch through exit, including startup, file reads, verification and reporting. **CPU time**, where recorded, sums time spent executing in user and kernel mode. **Peak RSS** is the largest amount of resident memory the operating system reports for the timed process. For drivers with child processes, that figure does not give their simultaneous total. MiB and GiB use powers of 1,024.

## Measurements on record

The current full-size head-to-head pairs the fastest measured Bend worker count on each host with native Lean OnBytes. The companion report preserves the worker screen, the quiet paired samples and the before/after comparison at fixed worker counts. [Latest measurements](../research/request-projection.md)

Lean OnBytes is a native executable built from a Lean translation of the C++ file checks. The theorem-linked Linux driver runs the verifier defined in the upstream Lean development. Checking that development's theorem is a separate activity from either timed invocation. Read ratios within a paired experiment; the M4 and Xeon runs use different CPUs and native compilers. [Upstream theorem](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/THEOREM.md) · [Assurance contract](assurance.md)

## Reproduce a measurement

Start from the repository root with `make bootstrap upstream`. Each command below builds its prerequisites before timing. Linux uses GNU `/usr/bin/time`. [Build prerequisites](../../CONTRIBUTING.md#build-a-verifier-you-can-check)

| Question | Command or recipe | Where to read the result |
| --- | --- | --- |
| Which Bend worker count gives the lowest median on this CPU? | Run `make benchmark-workers BENCH_ARGS="--worker-counts 1 2 4 8 16"`. Add counts suited to the host. | The JSON records each verified warmup, every quiet call and the selected worker count. Use a fresh OnBytes pairing for the result you publish. |
| Did a Bend change reduce latency? | Keep the earlier executable and its adjacent `.digest`, then run `make benchmark-revisions BENCH_ARGS="--before /absolute/path/to/verify-bend --workers 1"` on the new checkout. Repeat with 16 workers for the parallel case. | Both warmups check the observed pool size. Each timed call uses the same explicit worker count and checks the four-line verdict. [Harness](../../scripts/benchmark-standalone.py) |
| How long do standalone Bend and Lean OnBytes take on the same full-size proof? | Run `make benchmark-onbytes` on macOS or Linux. To include an earlier Bend build, supply `BENCH_ARGS="--before /absolute/path/to/verify-bend"`. Keep its `.digest` beside it. | The printed directory contains `report.md`, the per-call timings and closing records in `results.json`, and raw stdout, stderr and system time reports. |
| How does standalone Bend compare with upstream C++? | `make benchmark-standalone` on macOS or Linux. It checks the small and full-size exact-match proofs. | Open `report.md` in the printed results directory for the times, median ratios and peak RSS in KiB. The individual samples and verdict records are in `results.json`. [Harness](../../scripts/benchmark-standalone.py) |
| How long does Lean OnBytes take on its own? | `make benchmark-lean` runs three consecutive calls at each size, then checks a damaged small proof. | The terminal shows each call and the median for each genuine proof. This harness uses no discarded warmup. [Harness](../../scripts/onbytes-test.py) |

## Profiling one call

`make profile FIXTURE=full-size` records stage times and samples stacks on macOS. The percentages describe the sampling interval. On Linux the target prints a `perf` command. The kernel experiments from `make spikes` time field multiplication and hashing in isolation. The H100 experiment uses `make fresh-proof` to create a new small proof and check it on CPU. [Profiler](../../scripts/profile.py) · [Where the request spends its time](../research/request-projection.md#where-time-went) · [H100 procedure](../research/fresh-proof.md)

## Measurement protocol

1. Build each program before timing. Record the verifier revision, protocol and toolchain pins, compiler flags, executable hashes, and any source digest reported in the verdict. Name the fixture, its checksum and the caller's policy.
2. Use one host or scheduler allocation. Record the CPU, OS, memory measurement method, worker settings and any concurrent load. For scaling tests, observe the runtime worker count. Use `-j N -timing` to read the actual pool size on stderr. Omit `-timing` from the measured calls. [Worker-count probe](https://github.com/AbdelStark/flashprove-bend-verifier/issues/19#issuecomment-7126288622)
3. Verify the fixture against its checksum manifest. For paired measurements, discard one verified warmup per binary and fixture. Then time three fresh processes per binary with a warm filesystem cache. Alternate which program goes first in each pair. When including an earlier Bend build, rotate all three programs through each launch position. Give the standalone verifier an empty executable search path.
4. Validate every call. For the paired Bend comparisons, require exit zero and match the four closing lines with the fixture's expected output for that executable. Record each wall time, peak resident memory and any setup inside the timed command. For each binary, report the middle of its three measured times. Divide the Bend median by the comparator median to get the wall-time ratio.

## Requirements

| Requirement | Target | Evidence |
| --- | --- | --- |
| **REQ-PERF-2** | `-timing` reports public input, key, leaf, request and total wall time in milliseconds on stderr. | Compare stdout and verdict with and without the option. On macOS, `make profile` records stage timings and samples stacks. On Linux the target prints the corresponding `perf` command. |
| **REQ-PERF-3** | With one Bend worker, median full-size exact-match wall time is at most eight times the C++ median in the same Lucid job. Bend's peak RSS is at most 7 GB. | Run the measurement protocol with one request-stage thread for C++ and record the stage timings. |
| **REQ-PERF-4** | With 16 Bend workers, median full-size exact-match wall time is at most the single-request-thread C++ median in the same job. | Publish a verified scaling series at 1, 2, 4, 8 and 16 workers. [Recorded worker screens](../research/request-projection.md#worker-selection) |
| **REQ-PAR-1** | Changing the worker count preserves stdout and exit status. When several faults are present, the verifier reports the first failure in sequential stage order (key, leaf, request), then in file order. | `make worker-parity` compares all four fixtures, both altered-copy tables and 64 seeded differential cases at 1 and 16 workers. A copy with a bad key and empty request proof checks failure order at 1, 2, 4, 8 and 16. Each run saves the exit code and both output streams per case under `build/worker-parity-*`. [Job 7725 results and build identities](../research/worker-parity.json) |
| **REQ-PERF-5** | CI fails if a change increases small exact-match CPU time beyond the published tolerance. | Keep the budget relative to a C++ run on the same runner and demonstrate that an injected slowdown trips the check. |
| **REQ-PERF-6** | Standalone Bend verifies the full-size exact-match proof in less median wall time than native Lean OnBytes on the same CPU. | Use the measurement protocol and publish results for one Bend worker separately from tuned worker counts. Report the earlier Bend executable, the candidate, and Lean. Met on the M4 Max and the Xeon. [Measured latency](../research/request-projection.md#measured-latency) |

The speed and memory budgets are engineering targets. Change a target here and give the whole-verifier measurement that justifies the change. [Performance tracker](https://github.com/AbdelStark/flashprove-bend-verifier/issues/23)

## Reviewing an optimization

- Identify the expensive operation in a profile. Measure the same whole call before and after. Keep a speed change when it improves that call. Report kernel throughput separately.
- Run `make ci`, `make standalone-full`, `make standalone-extended` and `make fuzz` on both revisions. For each of the four fixtures, only the source build marker may differ between accepted records. Check the exit status as well. Run field, extension, hash and transcript vectors on the JS and native lanes.
- Keep verification logic in checked Bend and the native entry's C shim limited to argument handling. Keep field elements, extension elements and their vectors behind their existing module interfaces. A change that adds parallel work must also satisfy REQ-PAR-1.
