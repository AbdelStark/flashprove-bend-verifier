# Xeon rerun on main, 2026-11-27

> Status: frozen

The [M4 rerun](rerun-2026-11-26.md) measured the current verification code on one laptop. This run repeats it on the Xeon, where the README's other rows were still from the older `9d00a32`. The revision is `d42bb69`. Its Bend source digest is `0922c00decdebecae5c114f23df0c00be3b3a843bd39c360e2abd8db3c14991e`, the same as the M4 rerun's, so both reports measure the same verification code. [Raw logs and identities](data/rerun-xeon/conformance.json)

Everything ran in one Slurm job on an Intel Xeon Platinum 8480CL node under Linux 6.8, with Ubuntu clang 18.1.3 and g++ 13.3.0. The job held 16 physical cores, and each benchmark was pinned to one logical CPU per core. One other job held 2 CPUs and 1 GB on the node for the whole run. The conformance runs went first. The benchmarks followed one at a time.

## Conformance

All six runs passed. Five of them shared the 16 cores at the same time, and worker parity ran alone afterwards, so these times are not comparable with the M4's.

| Run | Result | Time |
| --- | --- | ---: |
| `make ci` | 151 of 151 files checked, 44 of 44 tests on each Bend lane, no documentation problems. | 841 s |
| `make standalone-full` | All four published proofs verified: `YES` for both exact-match fixtures, `WITHIN LIMITS` for both clipped-gap fixtures. Omitted and mismatched policies, malformed shapes and a truncated request were refused. | 86 s |
| `make standalone-extended` | All 122 altered sets rejected by both Bend and C++: 23 record sets and a leaf from another commitment, 10 + 10 altered copies, and 79 changes covering every kind of item. | 291 s |
| `make stages-full` | Key, leaf and request intermediates match the reference at both model sizes, under both policies. The full-size requests reach EOF after 50 forest and 12 attention projections and 25 batch equations. | 949 s |
| `make worker-parity` | 91 of 91 comparisons gave identical output and exit status at 1 and 16 workers: 6 fixtures, 20 table cases, 64 fuzz cases and 1 failure-ordering case. | 312 s |
| `make fuzz FUZZ_ARGS="-n 128 --seed xeon-rerun-2026-11-27"` | 256 mutations across the two small fixtures. Bend and C++ rejected all of them. | 122 s |

The kernel check was not repeated here. It covers source, not the host, and the [M4 rerun](rerun-2026-11-26.md#conformance) ran it on the same digest.

## Latency

Each row is the median wall time of three fresh processes, after one verified warmup per program, with launch order alternating. Every call matched the fixture's four closing lines.

### Bend and Lean OnBytes, full-size proof

| Bend workers | Bend | Lean OnBytes | Bend vs. Lean | Bend peak RSS | Lean peak RSS | Evidence |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 38.773 s | 93.090 s | 2.40× faster | 1.89 GiB | 4.96 GiB | [Paired calls](data/rerun-xeon/lean-j1.json) |
| 8 | 20.836 s | 92.937 s | 4.46× faster | 2.56 GiB | 4.96 GiB | [Paired calls](data/rerun-xeon/lean-j8.json) |

### Bend and C++, one worker each

| Fixture | Bend | C++ `cp_verify` | Bend vs. C++ | Bend peak RSS | C++ peak RSS | Evidence |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| accepted-proof | 3.766 s | 1.837 s | 2.05× slower | 0.18 GiB | 0.15 GiB | [Paired calls](data/rerun-xeon/cpp.json) |
| full-size | 38.806 s | 20.791 s | 1.87× slower | 1.89 GiB | 3.29 GiB | [Paired calls](data/rerun-xeon/cpp.json) |

### Worker screen

| Workers | 1 | 2 | 4 | 8 | 12 | 16 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Median full-size wall time | 39.347 s | 34.678 s | 24.095 s | 20.650 s | 20.712 s | 21.009 s |

The screen selected 8 workers. Beyond 8, more workers no longer help: 8, 12 and 16 are within 0.36 s of each other. [Screen](data/rerun-xeon/workers.json)

## Against `9d00a32` on the same host

The earlier build, measured in the same job, is the one behind the old README rows. Its executable matches the bundle from the [request projection](request-projection.md) report.

| Fixture | Workers | `9d00a32` | `d42bb69` | Change | Evidence |
| --- | ---: | ---: | ---: | ---: | --- |
| full-size | 1 | 46.008 s | 38.911 s | 15.4% less time | [Paired calls](data/rerun-xeon/rev-j1.json) |
| full-size | 16 | 23.456 s | 21.096 s | 10.1% less time | [Paired calls](data/rerun-xeon/rev-j16.json) |
| accepted-proof | 1 | 3.813 s | 3.816 s | no change | [Paired calls](data/rerun-xeon/rev-small.json) |

The old build reproduced its published time: 46.01 s here against 45.86 s in the earlier report. Lean also held steady at 93.0 s against 93.2 s. So the gain is in Bend's code, not in the machine. The small fixture did not move, which fits the speed pass: its changes cut work that grows with the model size.

## Requirements

- **REQ-PERF-3 is met.** With one worker, Bend takes 1.87× as long as C++ (the budget is 8×), with 1.89 GiB peak RSS (the budget is 7 GB).
- **REQ-PERF-4 is still open, but close.** With 16 workers Bend takes 21.10 s, against 20.79 s for single-thread C++. In the screen, 8 workers took 20.65 s. The two numbers come from different paired runs, so they do not settle the requirement.
- **REQ-PERF-6 is met.** Bend beats Lean OnBytes both at one worker and at the tuned count.

[Performance contract](../spec/performance.md)

## Reproduce

```sh
make bootstrap upstream standalone oracle lean-baseline
make ci standalone-full standalone-extended stages-full worker-parity
make fuzz FUZZ_ARGS="-n 128 --seed xeon-rerun-2026-11-27"
make benchmark-workers BENCH_ARGS="--worker-counts 1 2 4 8 12 16"
for n in 1 8; do make benchmark-onbytes BENCH_ARGS="--workers $n"; done
make benchmark-standalone
```

The comparison with `9d00a32` used `scripts/benchmark-standalone.py --compare bend --before <old verify-bend>` at 1 and 16 workers. `make lean-baseline` builds the Lean OnBytes executable. This run reused the one from the earlier Xeon report, checked by its SHA-256.
