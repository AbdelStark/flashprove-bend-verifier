# Full-size verifier latency after the request-stage optimizations

> Status: frozen

The timed workload is one complete verification of the published H821 full-size exact-match proof. Each verifier starts as a fresh CPU process, authenticates the key and selected leaf, checks the request and prints a verdict. The comparison validates the last four output lines. All programs receive the same commitment ID, configuration, tokens and proof bytes. Bend additionally reads the public schedule and tables for that configuration. The driver checks the fixture's SHA-256 manifest before each experiment. The commitment ID, covered positions, policy and verdict must match the published fixture. Each program has its own build identifier and expected wording for the commitment assumption. [Workload and protocol](../spec/performance.md) · [Benchmark driver](../../scripts/benchmark-standalone.py)

## Measured latency

Each row below is a separate head-to-head experiment. Time is median wall time across three measured pairs. Memory is the largest peak resident set of those three timed processes. The first row for each CPU uses the worker count selected in a separate screen. Both programs used one worker for the second row.

| CPU | Bend workers | Bend wall | Lean wall | Bend peak RSS | Lean peak RSS | Evidence |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Apple M4 Max | 16 | 11.183 s | 59.711 s | 2.61 GiB | 4.91 GiB | [Paired calls](notes/request-m4/lean.json) |
| Apple M4 Max | 1 | 21.336 s | 59.367 s | 1.89 GiB | 4.91 GiB | [Paired calls](notes/request-m4/lean-j1.json) |
| Intel Xeon Platinum 8480CL | 8 | 23.381 s | 93.350 s | 2.57 GiB | 4.96 GiB | [Paired calls](notes/request-xeon/lean.json) |
| Intel Xeon Platinum 8480CL | 1 | 45.863 s | 93.156 s | 1.89 GiB | 4.96 GiB | [Paired calls](notes/request-xeon/lean-j1.json) |

### Worker selection

The candidates had the following full-size median wall times. Several counts are close on the M4. The selected count is the fastest in this screen and can change with load or CPU topology.

| CPU | Workers and median elapsed time | Selected | Evidence |
| --- | --- | ---: | --- |
| Apple M4 Max | 1 at 21.674 s · 2 at 19.370 s · 4 at 13.954 s · 8 at 11.538 s · 12 at 11.404 s · 16 at 11.335 s | 16 | [Screen](notes/request-m4/workers.json) |
| Intel Xeon Platinum 8480CL | 1 at 45.855 s · 2 at 41.947 s · 4 at 27.512 s · 8 at 22.830 s · 16 at 23.316 s | 8 | [Screen](notes/request-xeon/workers.json) |

### Before and after at fixed worker counts

Both programs in each pair were standalone Bend. Both used the same worker count and returned the expected verdict. The reduction is relative to the earlier build’s median. The small proof is the published exact-match fixture.

| CPU | Fixture | Workers | Before | After | Less wall time | Evidence |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Apple M4 Max | full-size | 1 | 33.109 s | 21.361 s | 35.5% | [Paired calls](notes/request-m4/full-size-j1.json) |
| Apple M4 Max | full-size | 16 | 19.490 s | 11.264 s | 42.2% | [Paired calls](notes/request-m4/full-size-j16.json) |
| Apple M4 Max | accepted-proof | 1 | 2.603 s | 1.921 s | 26.2% | [Paired calls](notes/request-m4/accepted-proof-j1.json) |
| Intel Xeon Platinum 8480CL | full-size | 1 | 74.702 s | 46.067 s | 38.3% | [Paired calls](notes/request-xeon/full-size-j1.json) |
| Intel Xeon Platinum 8480CL | full-size | 16 | 41.551 s | 23.570 s | 43.3% | [Paired calls](notes/request-xeon/full-size-j16.json) |
| Intel Xeon Platinum 8480CL | full-size | 8 | 40.932 s | 22.926 s | 44.0% | [Paired calls](notes/request-xeon/full-size-j8.json) |
| Intel Xeon Platinum 8480CL | accepted-proof | 1 | 5.251 s | 3.755 s | 28.5% | [Paired calls](notes/request-xeon/accepted-proof-j1.json) |

## Where time went

The earlier profile left part of the request unaccounted for. We instrumented the release at `89e1df4` and recorded consecutive timestamps from request entry to return, on one observed worker. The intervals sum to **80.174 s** in this run. Across 25 links, constructing the segment equations took 32.495 s, placing them in the physical layout took 3.950 s and advancing the carried claim took 12.154 s. At the end, constructing the deferred linear weight claim (LIN) took 3.491 s and verifying its FOLD, code-switch and BASE rounds took 16.487 s. Reading the first transcript took 5.295 s. The remaining intervals, including destruction of the request state, are in the table. These times include instrumentation and come from a separate run. [Every interval](notes/request-outer-timing.tsv) · [Replay patch and source digest](../../research/spikes/request/outer-timers.patch)

On a second VM, we ran the instrumented baseline (`89e1df4`) and candidate (`9d00a32`) back to back on the same logical CPU. The full request fell from 74.658 to 47.055 s. Constructing the deferred claim took 2.952 s before and 2.940 s after. Checking its FOLD, code-switch and BASE rounds fell from 13.733 to 0.050 s. The largest remaining costs were constructing local segment equations (22.713 s) and advancing the carried claim (10.882 s). Together they account for 71% of the optimized request in this run. [Paired intervals](notes/third-request-outer.tsv) · [Replay instructions](../../research/spikes/request/third-lin-timers.patch)

To isolate the LIN change, we also compiled the baseline with only the terminal contraction applied. With one worker, full-size median wall time fell from 87.327 to 65.717 s. With 16, it fell from 51.829 to 36.966 s. Each result uses three alternating, uninstrumented pairs after a verified warmup on the same CPU allocation. To build this variant, cherry-pick `bd976de` onto `89e1df4`. These runs used a different VM from the headline Xeon comparison. [One-worker samples](notes/request-lin/one-worker.json) · [16-worker samples](notes/request-lin/16-workers.json)

## Changes to the verifier

**Deferred linear weights (LIN).** The verifier used to place every term in a wide multilinear table and carry it through successive folds. For an exactly sized form, we now contract each term at the row and place coordinates already drawn from the authenticated transcript. Only the coordinates still free at BASE need a table. The prefix is common to all terms in an aligned member, so its equality weight can be multiplied into the result once. Lifting this table back into the group uses a constant factor on each consumed coordinate. That identity also holds when a coordinate is zero or one. All scheduled rounds still check their targets, masks, widths and opened columns. Other term widths use the original placement path. The regression test evaluates the old placed table by dense interpolation, includes non-base-field challenges and tests both sides of a code switch. [Implementation](../../src/lin_projection.bend) · [Dense oracle](../../tests/lin_projection.bend)

**Feed-forward and attention reads.** Consecutive addresses share most of their multilinear equality weight. If the parent weight is `w` and the next coordinate is `x`, the two children have weights `w − w·x` and `w·x`. The verifier expands just the subtree intervals requested by the layout and clips the first and last pair to the requested bounds. Across the twelve full-size feed-forward groups, the wide lookups use 2,558,472 of the 16,674,816 leaf weights that the previous code generated. To recover those counts from the catalog, use the segment width and the block width (log₂ stride 0 and 6 respectively). Keep the 55 segment/stride pairs with a divisible length and at least 64 logical columns per group. For each pair, the old count is the padded table capacity divided by stride. The new count is the sum of the run lengths divided by stride, rounding down for each run. Attention now visits each real causal tile once per marginal and adds its contribution to the relevant row or column. The scalar oracle checks range boundaries, index wraparound, clipped runs, and off-Boolean row and column weights. [Full-size layouts](../../src/ff_catalog.bend) · [Interval evaluator](../../src/segment_attention_aff.bend) · [Oracle cases](../../tests/affine_weights.bend)

**FOLD code switches.** Two mask generators use the same evaluation point and coefficients separated by a common multiplier θ. Summing their geometric series once gives the first vector, then scaling the result by θ gives the second. The verifier still incorporates each sampled column in transcript order, including repeated draws, and puts the two vectors into their specified positions. A known-answer case uses a cubic extension coefficient so an accidental base-field shortcut would change the result. [Generator and reconstruction](../../src/fold_cs.bend) · [Known-answer vectors](../../tests/fold_mask_weights.bend)

**Reading and hashing.** Large proof records often consume an entire refill. Giving the caller that buffer directly avoids copying the prefix and walking it a second time. Streaming BLAKE2b now consumes each complete 128-byte block directly as 32 little-endian words. The final block stays buffered until the final compression, including when the byte count is an exact multiple of 128. The tests cover block boundaries and three updates to a nonzero byte pattern with a Python hashlib reference digest. [Reader](../../src/wire_reader.bend) · [Hash](../../src/hash_bytes.bend) · [Boundary cases](../../tests/hash_bytes.bend)

## Checking the verification path

Both source revisions passed `make ci`, `make stages-full`, `make standalone-full`, `make standalone-extended` and `make fuzz FUZZ_ARGS="-n 64 --seed speed-third-pass"` on Linux. The candidate passed 42 expectation tests on each Bend lane. Both revisions returned the published verdicts under both policies at both model sizes, rejected the extended altered-file corpus, and agreed with C++ on all 128 seeded mutations. `make worker-parity` confirmed the candidate’s output and exit status across the scheduling checks. On the same candidate sources, `bend src/standalone.bend --verdict` returned `ALL PROOFS CHECK` using the independent kernel. The larger proof obligation relating Bend acceptance to the upstream Lean theorem remains open. [Validation jobs and checker identity](notes/request-xeon/conformance.json) · [Assurance contract](../spec/assurance.md)

A separate diagnostic takes the third FOLD round of the authenticated key transcript and changes its message, length, name, multiplicity or challenge. It checks the same round sequence with the original and projected LIN weights. On both the small and full-size exact-match keys, both paths accepted the genuine transcript and rejected every one of the seven alterations. Holding the authenticated input fixed reaches checks that a byte flip could mask behind an earlier hash failure. [Replay and expected results](../../research/spikes/request/lin-transcript-check.patch)

## Reproduce the runs

Use a checkout containing both commits. Keep the baseline executable and its adjacent source digest together. The candidate is `9d00a32` and reports Bend source digest `4b01d0242a311d69ff3c3dce5637d695d1350030172ea51c7ff9873527d9c896` on both hosts. The protocol and Bend compiler pins are identical for both builds. Bend emits C, compiled here with Clang at `-O3`. Native Lean OnBytes comes from the upstream project built with its pinned Lean 4.29.1 release. [Native build command](../../scripts/compile_bend.py) · [OnBytes build](../../scripts/onbytes-build.sh)

```sh
scratch=$(mktemp -d)
git worktree add --detach "$scratch/before" 89e1df4
git worktree add --detach "$scratch/after" 9d00a32
make -C "$scratch/before" bootstrap upstream standalone
make -C "$scratch/after" bootstrap upstream standalone lean-baseline
cd "$scratch/after"

make benchmark-workers BENCH_ARGS="--worker-counts 1 2 4 8 12 16 --output build/worker-screen"
workers=$(python3 -c 'import json; print(json.load(open("build/worker-screen/results.json"))["selected_workers"])')
make benchmark-onbytes BENCH_ARGS="--workers $workers"

for n in 1 16; do
  make benchmark-revisions BENCH_ARGS="--before $scratch/before/build/verify-bend --workers $n"
done
python3 -B scripts/benchmark-standalone.py --compare bend --fixture accepted-proof \
  --before "$scratch/before/build/verify-bend" --workers 1
```

The M4 Max has 12 performance cores and four efficiency cores. These runs used macOS 26.6.2 and Apple Clang 21.0.0, with normal desktop services running and no CPU pinning. On the Lucid Xeon Platinum 8480CL, job 7766 used Ubuntu Clang 18.1.3 and CPU cores only. The screen and tuned comparison shared a fixed affinity mask spanning 16 physical cores (logical CPUs 1–16). The serial revision pair used logical CPU 1. One other job held two CPUs at the start, at the end and at each of 42 intermediate scheduler snapshots. The JSON records include the processor, OS, affinity, fixture hashes, executable hashes and per-call results.

For the Xeon screen, omit 12 from the example above and run the benchmark under `taskset` with one logical CPU on each of 16 physical cores. For the serial pair on Linux, pin both processes to the same single core. The screen discards one verified warmup at each count. It then times three quiet processes per count, reversing the order between rounds. The smallest median selects the Bend configuration for a fresh head-to-head comparison. The paired driver checks the worker count during the Bend warmup, alternates launch order and validates the full closing record after every call. The Lean runner processes this workload sequentially. The ratio of median wall times compares how long a caller waits for these builds and worker settings. [Pinned Lean command](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/OnBytes/Shell/Whole.lean)
