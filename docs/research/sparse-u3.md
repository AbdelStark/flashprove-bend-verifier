# Checking sparse U3 reads at their integer addresses

> Status: frozen

On 25 November 2026 we compared the standalone verifier on `main` before this change (`c86fd9e`) with `d623abe`. Each timed process read the same full-size exact-match proof and public inputs from disk, checked the key, leaf and request, and returned the four published closing lines. The request proof is 18,779,540 bytes and covers 1,000 reply tokens and one proposed next token. These timings measure CPU verification of an existing proof. [Fixture and commitment](https://github.com/anthropics/FlashProve/tree/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size)

## Why an address helps

The feed-forward and attention equations produce weighted reads of individual cells in a segment's U3 oracle. The previous build had the integer address at construction time. It expanded that address into a list of low/high selectors, applied the batch coefficient, then walked the selectors to recover the same address. The new build carries the address and weight through batching and adds the scaled weight directly to its cell. Other tensor reads can contribute to that cell too. [Sparse read representation](../../src/u3_cells.bend) · [Request-stage placement](../../src/segment_u3.bend)

Two details affect which proofs pass. First, a selector of width `b` uses the low `b` address bits, so different indices can name the same cell. Second, the protocol checks that each genuine cell has a nonzero coefficient **after** all contributions have been added. Two nonzero reads can cancel. The direct path checks the owner, width and physical tile layout. Where that path does not apply, general placement reconstructs the original selectors. The regression cases cover a padded last row, an index beyond 32 bits, mixed sparse and tensor reads, and cancellation in the cubic extension field. [Executable cases](../../tests/u3_cells.bend) · [Coverage check](../../src/segment_local.bend)

## Wall time and memory

| Host | Workers | Comparator | Median wall, comparator → candidate | Reduction | Peak RSS, comparator → candidate | All samples |
| --- | ---: | --- | ---: | ---: | ---: | --- |
| Apple M4 Max | 1 | Previous Bend | 46.034 → 38.279 s | 16.8% | 2.17 → 2.00 GiB | [JSON](notes/sparse-m4-1.json) |
| Apple M4 Max | 16 | Previous Bend | 22.639 → 22.184 s | 2.0% | 3.47 → 2.73 GiB | [JSON](notes/sparse-m4-16.json) |
| Lucid Xeon | 1 | Previous Bend | 88.879 → 74.625 s | 16.0% | 2.18 → 2.00 GiB | [JSON](notes/sparse-xeon-1.json) |
| Lucid Xeon | 16 | Previous Bend | 45.236 → 41.122 s | 9.1% | 3.48 → 2.69 GiB | [JSON](notes/sparse-xeon-16.json) |
| Apple M4 Max | 1 | Lean OnBytes | 64.619 → 38.412 s | 40.6% | 4.91 → 2.00 GiB | [JSON](notes/sparse-m4-lean.json) |

Each row is a separate paired experiment. Wall time includes process startup, file reads, all verification stages and the closing record. The reduction compares the two medians in that row. Peak RSS is the largest measured resident set among the three timed processes. The JSON includes CPU seconds, which count work across threads and can exceed wall time. Compilation, fixture preparation and the warmup processes are outside the sample.

Both builds used Bend 2.0.40. Apple Clang 21.0.0 compiled the M4 binaries and Ubuntu Clang 18.1.3 compiled the Linux binaries, each with `-std=c11 -O3 -lpthread -lm`. The M4 was a desktop with other applications running. Slurm job 7742 ran both Xeon builds in one shared-node allocation. It pinned the one-worker processes to logical CPU 1 and the 16-worker processes to one logical CPU per physical core. A separate two-CPU allocation was present when the job started. No GPU performed verification. The Bend source digests in every accepted record were `e11adc7155647c5f30c7b0d6af95d4fa2d8b06da0e90660abb71876a29ce7fb2` before and `58e7885d9d83a1cce8998f6c6d59e0d5f61440f24c2f91f3ac9f67b0004036d2` after. In the JSON, `host.git` identifies the harness checkout. The Lucid harness snapshot has the same script bytes as `d623abe`. [Build flags](../../scripts/compile_bend.py) · [Toolchain pin](../../toolchain.lock) · [Protocol pin](../../upstream.lock)

The Lean row uses native Lean 4.29.1 running upstream OnBytes. Its timer also includes reading and verifying the same public byte files. The upstream theorem-linked driver is a separate command. [Benchmark definitions](../spec/performance.md)

## Checking the verdicts

On Linux, both revisions returned the published records for the two model sizes under exact-match and clipped-gap policies. Both rejected 122 altered proof sets and a leaf borrowed from another commitment. Both agreed with upstream C++ on all 128 byte mutations generated with `make fuzz FUZZ_ARGS="-n 64 --seed speed-second-pass"`. Jobs 7732 and 7740 exercised the baseline and candidate respectively. The focused U3 tests also compare the fast and general paths on a cancellation and check the actual six-limb result of a sparse update. [Regression cases](../../tests/u3_cells.bend) · [Release checks](https://github.com/AbdelStark/fv-flashprove-bend-verifier/pull/43)

The separate BendTT kernel accepted the standalone definitions at their declared types. Proving that every Bend acceptance implies acceptance by the theorem-linked Lean verifier remains open. [Kernel command and result](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/28#issuecomment-7157638941) · [Assurance contract](../spec/assurance.md)

## Where the request still spends time

A separate instrumented Xeon run used one observed worker on the same full-size proof. Across the 25 links it spent 31.236 s forming local equations, 3.595 s placing them, and 9.219 s advancing the carried state. Within local equations, the smallness checks took 11.956 s and U3 accumulation and contraction together took 3.619 s. Those last two figures are included in the 31.236 s. The request took 69.006 s and the whole call took 74.790 s on the internal timer. After accounting for local equations, placement, advancement and the final FOLD and BATT steps, 22.753 s of the request falls outside those timers. The next profiling issue tracks that remaining time. The patch contains the replay command and expected source digest. [Profiling issue](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/44) · [All 25 links](notes/sparse-request-segments.tsv) · [Diagnostic patch](../../research/spikes/request/sparse-segment-timers.patch)

Three experiments helped narrow the next pass. Interpolating the formula-defined lookup tables directly gave mixed whole-proof timings on the M4. Factoring shared nonzero axes out of the matrix coverage check passed the focused JS and native tests and both the small and full-size exact-match proofs. On a separate Lucid VM, its first full-size call took 82.600 s against 79.580 s with sparse U3 alone. A different traversal of the remaining tensor selectors also gave a mixed result on a Lucid VM. The full-size median moved from 80.109 to 78.661 s and the small-proof median from 7.269 to 7.367 s, with nearly identical peak memory at full size. All three experiments were left out of the release.

## Reproduce the comparison

From the checkout containing this report, build the two source revisions in separate worktrees. The harness uses one verified warmup and three timed calls per program. With `--compare bend`, it requests the same worker count from both binaries and checks the reported counts during warmup. The measured calls alternate launch order and omit instrumentation. Each runs with an empty executable search path.

```sh
scratch=$(mktemp -d)
git worktree add --detach "$scratch/before" c86fd9e
git worktree add --detach "$scratch/after" d623abe
make -C "$scratch/before" bootstrap upstream standalone
make -C "$scratch/after" bootstrap upstream standalone
make -C "$scratch/after" benchmark-revisions BENCH_ARGS="--before $scratch/before/build/verify-bend --workers 1"
make -C "$scratch/after" benchmark-revisions BENCH_ARGS="--before $scratch/before/build/verify-bend --workers 16"
make -C "$scratch/after" benchmark-onbytes BENCH_ARGS="--workers 1"
```

On Linux, prefix each comparison with `taskset -c "$cpus"` to reproduce the recorded CPU affinity. Set `cpus` to one allowed logical CPU for the one-worker run, or one logical CPU on each of 16 distinct physical cores for the 16-worker run. The JSON records identify the CPU, affinity, fixture and executable hashes, source digests, warmups, all timed calls and the reported verdicts.
