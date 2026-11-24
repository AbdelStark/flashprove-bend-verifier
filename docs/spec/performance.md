# Performance contract

> Status: living

Measure the time a caller waits for a verified answer. A whole call starts a native process, reads the public configuration, key, request, token and proof, and ends when the process emits the expected verdict and exits. The standalone Bend executable checks every stage. The historical hybrid delegates model checks to a C++ worker and has its own build identity. [Verification contract](verifier.md) · [Hybrid design](../adr/native-kernels.md)

## Measurements on record

| Experiment | Full-size exact-match result | What the comparison covers |
| --- | --- | --- |
| [M4 Max, after the extension multiplication change](../research/m4-standalone.md) | Bend 254.945 s, native Lean OnBytes 58.693 s | Three alternating pairs on the same workstation. Bend used 4.34 times the median wall time. |
| [Lucid Xeon, before that change](../research/lucid.md#independent-bend-verification) | Bend 665.120 s, C++ 19.098 s | Three alternating pairs in one CPU allocation. The standalone verifier executed sequential code with its default worker pool. |
| [Two Linux Lean baselines](../research/lucid.md#theorem-linked-verifier) | OnBytes 95.482 s, theorem-linked command 1,141.270 s | Separate jobs on the same Xeon. The theorem-linked command builds a parser tool and relinks a helper during each call. |

The M4 timings answer how the optimized port compares with native Lean OnBytes. The earlier Lucid measurements also include the theorem-linked Lean command. Changes in hardware, compiler, verifier revision and run conditions prevent using the two experiments to estimate a cross-platform speedup.

## Measurement protocol

1. Build each program before timing. Record the verifier revision, protocol and toolchain pins, compiler flags, executable hashes, and any source digest reported in the verdict. Name the fixture, its checksum and the caller's policy.
2. Use one host or scheduler allocation. Record the CPU, OS, memory measurement method, worker settings and any concurrent load. For scaling tests, observe the runtime worker count. The standalone argument shim leaves Bend's pool at its default. Changing `BEND_THREADS` did not change the pool. [Worker-count probe](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/19#issuecomment-7126288622)
3. Verify the fixture against its checksum manifest. Discard one verified warmup per binary and fixture, then time three fresh processes per binary with a warm filesystem cache. Alternate the order of each pair and give the standalone verifier an empty executable search path.
4. Validate every call. Compare the exit status and four closing lines with the fixture's expected output for that executable. Record each wall time, the median and peak resident memory. Identify any setup inside the timed command.

`make benchmark-standalone` runs the paired Bend/C++ comparison on both exact-match fixtures. The Slurm job runs the same harness on a CPU allocation. `make benchmark-lean` runs OnBytes separately. The paired M4 record includes commands for running Bend and OnBytes together. [Bend/C++ harness](../../scripts/benchmark-standalone.py) · [Slurm job](../../scripts/cluster/standalone-benchmark.sh) · [M4 reproduction](../research/m4-standalone.md#repeat-the-comparison)

## Requirements

| Requirement | Target | Evidence |
| --- | --- | --- |
| **REQ-PERF-2** | `-timing` reports public input, key, leaf, request and total wall time in milliseconds on stderr. | Compare stdout and verdict with and without the option. On macOS, `make profile` records stage timings and samples stacks. On Linux the target prints the corresponding `perf` command. |
| **REQ-PERF-3** | With one Bend worker, median full-size exact-match wall time is at most eight times the C++ median in the same Lucid job. Bend's peak RSS is at most 7 GB. | Run the measurement protocol with one request-stage thread for C++ and record the stage timings. |
| **REQ-PERF-4** | With 16 Bend workers, median full-size exact-match wall time is at most the single-request-thread C++ median in the same job. | Publish a verified scaling series at 1, 2, 4, 8 and 16 workers. |
| **REQ-PAR-1** | Changing the worker count preserves stdout and exit status. When several faults are present, the verifier reports the first failure in sequential stage order (key, leaf, request), then in file order. | Compare all four fixtures, both altered-copy tables and `make fuzz` at 1 and 16 workers. |
| **REQ-PERF-5** | CI fails if a change increases small exact-match CPU time beyond the published tolerance. | Keep the budget relative to a C++ run on the same runner and demonstrate that an injected slowdown trips the check. |

The speed and memory budgets are engineering targets. Early field measurements and a 16-core fork-join hashing benchmark informed them. The latter exposed parallel work explicitly. Change a target here and give the whole-verifier measurement that justifies the change. [Kernel experiments](../research/bend2-assessment.md) · [Performance tracker](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/23)

## Reviewing an optimization

- Identify the expensive operation in a profile. Measure the same whole call before and after. Keep a speed change when it improves that call. Report kernel throughput separately.
- Run `make ci`, `make standalone-full`, `make standalone-extended` and `make fuzz` on both revisions. For each of the four fixtures, only the source build marker may differ between accepted records. Check the exit status as well. Run field, extension, hash and transcript vectors on the JS and native lanes.
- Keep verification logic in checked Bend and the native entry's C shim limited to argument handling. Keep field elements, extension elements and their vectors behind their existing module interfaces. A change that adds parallel work must also satisfy REQ-PAR-1.
