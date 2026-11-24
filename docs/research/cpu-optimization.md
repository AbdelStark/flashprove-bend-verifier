# Native CPU verification after the request-stage optimization

> Status: frozen

On 24 November 2026 a 16-core Apple M4 Max with 48 GiB of RAM verified the full-size exact-match fixture. The request proof was 18,779,540 bytes. Each sample covers one fresh process from launch to exit, including reading the public files, checking the key, leaf and request, and printing the verdict. Both implementations checked the same caller-supplied commitment and the same 1,001 predicted tokens.

| Experiment | Program | Wall seconds in sample order | Median wall (s) | Median CPU (s) | Largest peak RSS (GiB) |
| --- | --- | --- | ---: | ---: | ---: |
| Three programs | Earlier Bend | 249.289, 249.893, 253.319 | 249.893 | 249.83 | 10.84 |
| Three programs | Optimized Bend, 1 worker | 38.273, 39.390, 39.309 | 39.309 | 39.27 | 2.17 |
| Three programs | Lean OnBytes, 1 worker | 58.645, 59.458, 59.329 | 59.329 | 59.28 | 4.91 |
| 16-worker pair | Optimized Bend, 16 workers | 20.380, 20.063, 20.495 | 20.380 | 40.72 | 3.48 |
| 16-worker pair | Lean OnBytes, 1 worker | 60.037, 59.403, 59.756 | 59.756 | 59.68 | 4.91 |

The optimized single-worker build was 6.36× faster than the earlier Bend build and 1.51× faster than native Lean OnBytes by median wall time. A second experiment paired the same Bend executable at 16 workers with the same sequential Lean executable. The wall-time ratio in that pair was 2.93× in Bend’s favor. CPU seconds sum user and system time across workers. [Three-program samples](notes/m4-cpu-one-worker.json) · [16-worker samples](notes/m4-cpu-16-workers.json)

Each experiment discarded a verified warmup per program on a warm filesystem cache. The three measured triples rotated the launch positions. The measured pairs alternated the first program. Each call had an empty executable search path, used the caller’s commitment ID and matched all four closing lines including the expected implementation marker. The earlier executable used its original default worker setting. We ran the verifiers one at a time on the M4. Other desktop applications remained open. All M4 timings in the table cover the same proof on one host.

Both Bend versions used the pinned Bend 2.0.40 compiler and Apple Clang 21.0.0 with `-std=c11 -O3 -lpthread -lm`. The verification sources were `7200912` before and `ca1297c` after the change. Both experiments used the same optimized binary. Lean 4.29.1 compiled upstream `OnBytes.Main` at the protocol revision in `upstream.lock`. The JSON records include the binary hashes, Bend source digests, fixture manifest and proof hashes, OS and harness identity. [Performance contract](../spec/performance.md) · [Assurance contract](../spec/assurance.md)

## Why the first version was slow

In one full-size exact-match call on the M4 Max, the baseline spent 0.682 s on public inputs, 2.453 s on the key, 0.606 s on the leaf and **293.713 s on the request**. The complete call took 297.454 s on the verifier's internal timer. Eight four-second stack samples, starting 12, 45, 85, 125, 165, 205, 245 and 285 seconds after launch, showed different costs over the life of the same request. During the middle of the run, the working thread repeatedly walked coefficient lists, multiplied field elements and released boxed values. At 245 seconds, list copying and reference counting in row placement dominated the sample. The table records the native executable’s leaf symbols with at least five observations per window. The sampling interval was 3 ms. [Stack samples by window](notes/m4-baseline-stack-samples.tsv)

A CPU-only Lucid run timed the individual operations for all 25 segments. Of 717.848 request seconds, constructing the local equations took 170.614 s, placing them in their physical tables took 141.530 s and carrying them through the group folds took 254.538 s. The 12 feed-forward segments accounted for 462.886 s of those three operations. The remaining request time includes the transcript, openings and subsequent verification. These are instrumented measurements on the earlier implementation. [Per-link timings](notes/request-segment-times.tsv)

Lean OnBytes compiles this protocol to native code too. For example, its low-variable fold reads adjacent entries from an indexed array. The earlier Bend path computed comparable linear combinations through lists of address factors. The profiles and the before/after timings point to that representation and its repeated traversal. [Lean fold](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/OnBytes/Iop/Fold.lean#L38-L47)

## What changed

The earlier verifier represented a coefficient as a field element and a list of factors, one per address bit. A fixed bit held two cubic field elements even though its endpoints were always zero and one. Placing an entire column could build that address list, copy it to insert a group selector, interpolate its row factors, then walk the result again at the terminal column challenge. Increasing the runtime's worker count alone could not eliminate that work.

- A fixed bit now uses a tag. The scatter operation follows its one live branch. The fold caches the products for short Boolean address prefixes and interpolates general factors directly. Field multiplication uses bounded intermediate products that fit Bend's native 48-bit natural numbers. [Fold](../../src/fold.bend) · [Goldilocks arithmetic](../../src/goldilocks.bend)
- The verifier accumulates geometric U3 reads directly into a coefficient table. It rejects any required live cell whose coefficient is zero before contracting the table. A tied matrix row uses the same factors across many columns. The new tile path evaluates that shared row once per applicable tile. Kept members and layouts outside the fast path retain the general placement. [U3](../../src/segment_u3.bend) · [Shared rows](../../src/segment_outer.bend)
- Once the transcript fixes the challenges, a local segment can prepare its equations independently. The one-worker path processes segments in order. Larger worker pools prepare bounded groups in parallel. Each group contributes a column vector and a carry multiplier. The verifier computes independent contributions concurrently and applies the resulting updates in file order. A later segment cannot override an earlier refusal. [Segment scheduling](../../src/segment_chain.bend) · [Ordered updates](../../src/segment_transport.bend)

## What still costs time

A profiled call of the optimized binary on the M4 Max took 39.681 s on its internal timer with one observed worker. Public inputs took 0.673 s, the key 1.608 s, the leaf 0.556 s and the request 36.844 s. In all four request-stage sampling windows, runtime reference counting and extension-field arithmetic appeared among the most frequent stack leaves. At 5 s the samples also reached power calculation and generic closure application. By 33 s they included LIN factor placement and the FOLD verifier. These are three-second windows sampled every 4 ms. They locate candidates for the next memory-layout and traversal experiments. [Optimized stack samples](notes/m4-optimized-stack-samples.tsv) · [Performance tracker](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/23)

## Repeating the comparison on a Xeon

On a Lucid Xeon Platinum 8480CL the single-worker result was closer. In job 7729, optimized Bend took 90.706 s by median (90.706, 90.713, 89.935 s) and Lean OnBytes took 93.978 s (93.978, 95.602, 92.481 s). Bend used 3.5% less wall time on this host. Peak RSS was 2.17 GiB for Bend and 4.96 GiB for Lean. The host ran Linux x86-64 and Ubuntu Clang 18.1.3 built the native Bend code. Both verification commands ran entirely on CPU, within the same 16-CPU allocation and with one requested worker. The node was shared. The small-proof job below overlapped the end of the Lean comparison on a separate allocation. [Full-size sample records](notes/lucid-onbytes-one-worker.json)

In the same allocation, two additional experiments paired Bend with the C++ reference using one C++ request-stage thread. The serial Bend median met the eight-times-C++ target. The 16-worker median remained above the C++ target. Run `make benchmark-standalone BENCH_ARGS="--fixture full-size --workers 16"` for the parallel pair, or change the count to 1 for the serial pair.

| Bend workers | Bend median (s) | C++ median (s) | Bend / C++ wall time | Evidence |
| ---: | ---: | ---: | ---: | --- |
| 1 | 88.696 | 18.666 | 4.75× | [Sample records](notes/lucid-cpp-one-worker.json) |
| 16 | 45.736 | 18.751 | 2.44× | [Sample records](notes/lucid-cpp-16-workers.json) |

A separate 16-vCPU Lucid node measured the same executable at 1, 2, 4, 8 and 16 workers. The fastest median there was 61.284 s at eight workers. At 16 workers it took 61.865 s and used 124.16 s of CPU time. Those samples belong to a different host from the paired C++ experiment above. [Five worker counts, stage times and raw data](lucid-workers.md)

The small exact-match proof exercises the same verifier with a different model size. In job 7731 on the same Xeon host, all three executables shared a single logical CPU. The earlier Bend took 13.332 s, optimized Bend took 5.687 s and upstream C++ took 1.855 s. Bend’s peak RSS fell from 805 MiB to 219 MiB. These are three-run medians after a warmup per binary, using the 4,145,300-byte proof. To repeat it on Linux, build the earlier worktree shown below, set `cpu` to one logical CPU in your allocation and run `taskset -c "$cpu" make benchmark-standalone BENCH_ARGS="--fixture accepted-proof --before $scratch/before/build/verify-bend"`. Job 7731 used CPU 1. [Small sample records](notes/lucid-small-before-after.json)

## Conformance on the measured builds

The earlier and optimized sources passed `make ci`, `make standalone-full`, `make standalone-extended` and `make fuzz FUZZ_ARGS="-n 32 --seed speed-first-pass"` on Linux. Each build returned the expected result for the four published proofs and rejected 122 altered proof sets, a leaf from a different commitment and all 64 seeded mutations. Jobs 7713 and 7722 tested the earlier and optimized builds respectively. The optimized build also passed `make stages-full` in job 7727.

Jobs 7725 and 7730 compared the native outputs at one and 16 workers. Both runs matched stdout, stderr and exit status in 90 paired cases. With faults in both key and request, all five worker counts reported the key failure first. Run `make worker-parity` to repeat these tests. [Parity record](worker-parity.json) · [Scope of the independent BendTT check](../spec/assurance.md#what-has-been-formally-checked)

## Reproduce the whole calls

Run these commands from the optimized checkout. The first three commands build the earlier executable and its digest in a separate worktree. The two comparisons use the pinned public files and print the directory containing every sample.

```sh
scratch=$(mktemp -d)
git worktree add --detach "$scratch/before" 7200912
make -C "$scratch/before" bootstrap upstream standalone
make benchmark-onbytes BENCH_ARGS="--before $scratch/before/build/verify-bend"
make benchmark-onbytes BENCH_ARGS="--workers 16"
```

For the historical segment breakdown, apply the baseline timing patch to a separate `7200912` worktree, rebuild there and run the full-size command with `-j 1 -timing`. The diagnostic Bend source digest is `09cc1ce4e9b287cf2fb00d393952fa1cf80a421f859641dd7e5b098b58c2d142`. [Instrumentation patch](../../research/spikes/request/baseline-timers.patch) · [Raw per-segment durations](notes/request-segment-times.tsv)
