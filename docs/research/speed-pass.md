# Full-size latency after removing products and shared-list walks

> Status: frozen

This pass measured where one full-size verification spends its time, then removed work from the request stage without changing any value it computes. Each change replaces a computation with an exact equivalent over the field. The candidate is `b4a8c4b` with Bend source digest `e75422f90d98ca6a753ec7b127b4e0ed020374dda005cac70c827cfd79032163`. The baseline is `c80cb65` with digest `daa7aa96b5b76f7053f9b2c59b844cd766ca2b3ad4ae770ddeae814934e754de`. [Workload and protocol](../spec/performance.md) · [Earlier release](request-projection.md)

## Measured latency

All runs used one Apple M4 Max (12 performance and 4 efficiency cores) on macOS 26.6.2 with Apple Clang 21.0.0, normal desktop services and no CPU pinning. Each row reports the median wall time of three fresh processes after one verified warmup per program, with launch order alternating. Every call matched the fixture's four closing lines.

| Fixture | Workers | Before | After | Less wall time | Evidence |
| --- | ---: | ---: | ---: | ---: | --- |
| full-size | 1 | 21.811 s | 18.706 s | 14.2% | [Paired calls](data/speed-m4/full-size-j1.json) |
| full-size | 16 | 11.570 s | 10.365 s | 10.4% | [Paired calls](data/speed-m4/full-size-j16.json) |
| accepted-proof | 1 | 1.958 s | 1.929 s | 1.5% | [Paired calls](data/speed-m4/accepted-proof-j1.json) |

Peak RSS did not change: about 1.88 GiB with one worker and 2.6 GiB with 16.

| Comparator | Bend workers | Bend | Comparator | Ratio | Evidence |
| --- | ---: | ---: | ---: | ---: | --- |
| Lean OnBytes | 1 | 18.597 s | 60.105 s | Bend 3.23× faster | [Paired calls](data/speed-m4/lean-j1.json) |
| Lean OnBytes | 16 | 10.240 s | 60.139 s | Bend 5.87× faster | [Paired calls](data/speed-m4/lean.json) |
| C++ `cp_verify`, full-size | 1 | 18.570 s | 8.188 s | Bend 2.27× slower | [Paired calls](data/speed-m4/cpp.json) |
| C++ `cp_verify`, accepted-proof | 1 | 1.925 s | 0.649 s | Bend 2.97× slower | [Paired calls](data/speed-m4/cpp.json) |

The single-worker C++ comparison is within the REQ-PERF-3 budget of eight times C++. With 16 workers Bend does not yet meet REQ-PERF-4 (single-thread C++ time).

## Where time went

Temporary timestamps around each stage of the 25 serial links (`-j 1`) partitioned the request. The deltas below are summed over all links; the instrumentation was removed before measuring.

| Interval | Before | After |
| --- | ---: | ---: |
| Smallness equations | 5.19 s | 2.45 s |
| Feed-forward equations | 2.82 s | 2.66 s |
| Carried-claim transport | 4.45 s | 4.37 s |
| Physical placement | 1.59 s | 1.57 s |
| Dense U3 coverage | 1.37 s | 1.35 s |
| Whole request (instrumented) | 19.71 s | 16.50 s |

Within smallness, the ZZ read coverage check fell from 2.48 to 1.34 s and the column folds from about 2.4 to 0.86 s.

The projection rewrite cut its own share of the profile from about 9% to under 2%. The commit interval did not move, because its cost is the per-term multiplications and list allocation that remain. The remaining time is spread out: the largest items are placing about 75,000 terms per link (1.7 s), the physical layout (1.6 s), reading the first transcript (1.6 s) and dense U3 coverage (1.4 s). Cubic-extension products take about a quarter of the samples and reference counting about a third.

## Changes to the verifier

**Equality factors.** When a factor is `{1−x, x}`, the low child weight is `w − w·x`, so one product serves both children. This applies to the scatter into tables and to the new dense fill. [Implementation](../../src/fold.bend) · [List-expansion oracle](../../tests/sparse_form.bend)

**Dense fill.** A term made of six or more general factors covers its whole table. It is now doubled in place one factor at a time, highest bit first, in an array the loop owns. The tree walk took a shared reference count on the factor list at every node. Entries are the same products. [Oracle](../../tests/sparse_form.bend)

**One-term coverage.** A coverage check over one tensor term on a full power-of-two table now reads the weight and the factor endpoints. Every entry is their product, and `F_p[X]/(X³−2)` is a field because `2^((p−1)/3) = 2^32 − 1 ≠ 1` modulo the Goldilocks prime, so a product is zero exactly when a factor is. Sums of several terms still use the full table, because they can cancel. [Implementation](../../src/segment_coverage.bend) · [Full-table comparison](../../tests/segment_coverage.bend)

**Projection.** Fixing a term's first coordinates walked a tree of prefix products shared by every term, taking a reference on each node per bit. The verifier now builds one array per projection loop: Boolean prefix products for each four-bit chunk, then the gammas. Each step reads one entry. A general factor fixes the rest of its chunk by interpolation, as before. [Implementation](../../src/fold.bend) · [Coordinate-by-coordinate oracle](../../tests/fold_selectors.bend)

**Smallness columns.** Each 64-bit word of ternary challenges took 32- and 16-element prefixes of the shared powers of χ. The 128 powers now sit in an array threaded through every column. [Implementation](../../src/smallness_columns.bend) · [Known answers](../../tests/smallness_columns.bend)

**Unit scales and branches.** Scaling by one or minus one returns the value or its negation, which equals the product. Per-term branches that allocated two closures now use a `match` helper. [Known answers](../../tests/unit_scale.bend)

## Checking the verification path

The candidate passed `make ci` (44 expectation tests on each Bend lane, 151 files checked), `make standalone-full`, `make standalone-extended` and `make worker-parity`. It also passed `make fuzz` with seeds `hardcore-1` and `hardcore-2`: 256 mutations, all rejected by both Bend and C++. Each new test was run once against a deliberately broken implementation and failed. The independent kernel (`bend src/standalone.bend --verdict`) was not run on this host: it needs Lean v4.34.0, which is not installed here. The last kernel check covers `9d00a32`. [Assurance contract](../spec/assurance.md)

## Reproduce the runs

```sh
scratch=$(mktemp -d)
git worktree add --detach "$scratch/before" c80cb65
git worktree add --detach "$scratch/after" b4a8c4b
make -C "$scratch/before" bootstrap upstream standalone
make -C "$scratch/after" bootstrap upstream standalone lean-baseline
cd "$scratch/after"
for n in 1 16; do
  make benchmark-revisions BENCH_ARGS="--before $scratch/before/build/verify-bend --workers $n"
done
python3 -B scripts/benchmark-standalone.py --compare bend --fixture accepted-proof \
  --before "$scratch/before/build/verify-bend" --workers 1
for n in 1 16; do make benchmark-onbytes BENCH_ARGS="--workers $n"; done
make benchmark-standalone
```
