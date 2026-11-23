# Unsigned comparisons in the Goldilocks field

> Status: frozen

On 2026-11-23 we measured the public hybrid verifier before and after a change to carry, borrow and canonicalization in its Bend field arithmetic. A previous request-stage sample had spent 279 of 351 main-thread samples in base-field multiplication. The experiment used the same two stored exact-match proofs as the earlier benchmark. [Baseline c1b975e](https://github.com/AbdelStark/fv-flashprove-bend-verifier/tree/c1b975e25c329f6895c04f0c2c0ca9a5e431be5c) · [Change e07f402](https://github.com/AbdelStark/fv-flashprove-bend-verifier/commit/e07f4028426991d9ff72e3e132dc5f855d15ab90) · [Original sample and timings](whole-call.md)

## Chained multiplications

For unsigned 32-bit limbs, addition wraps exactly when the low word of the sum is smaller than the first addend. Subtraction borrows exactly when the minuend is smaller than the subtrahend. The candidate expresses both conditions as unsigned comparisons and converts each Boolean to a carry or borrow bit. For a 64-bit value to be at least the Goldilocks prime `0xffffffff00000001`, its high limb must equal `0xffffffff` and its low limb must be nonzero. In the cubic extension, `E3.mul` calls the base reduction 17 times in the source. Nine calls reduce base products and eight reduce coefficient additions, including the doublings `d1` and `d2`. [Base field](../../src/goldilocks.bend) · [Cubic product](../../src/extension.bend)

Each build placed its own revision of `src/goldilocks.bend` beside an identical copy of the multiplication harness with `NNN` set to 20000000. Placing the files together binds the harness's relative import to that revision. Bend emitted C with `bend mul.bend -o mul.c`. We compiled with `clang -O2 -std=gnu11 -pthread mul.c -o mul-o2` and ran `./mul-o2 +RTS --threads 1`. After a warm-up for each binary, six pairs of calls alternated their starting revision. All twelve calls computed the same final high and low limbs as the independent C calculation, `328481396 2633645473`. [Harness template](../../research/spikes/goldilocks/mul.bend.in) · [C reference](../../research/spikes/goldilocks/ref.c)

| Field revision | Wall seconds, in sample order | Median (s) |
| --- | --- | ---: |
| c1b975e | 0.256981, 0.259416, 0.257502, 0.259185, 0.260365, 0.255550 | 0.2583435 |
| e07f402 | 0.191228, 0.191759, 0.189608, 0.192365, 0.191990, 0.191807 | 0.191783 |

The chain took 25.8% less time by median (1.347× the baseline throughput). The complete verifier also performs additions, cubic products, hashing, file reads and statement checks.

## Whole-proof verification

| Exact-match fixture | Binary | Wall seconds, in sample order | Median (s) | Peak RSS per sample (MiB) |
| --- | --- | --- | ---: | --- |
| accepted-proof | C++ reference | 0.960, 0.633, 0.644 | 0.644 | 194.4, 193.9, 190.4 |
| accepted-proof | Public hybrid CLI | 2.639, 2.358, 2.377 | 2.377 | 201.9, 190.8, 195.2 |
| full-size | C++ reference | 8.160, 8.100, 8.144 | 8.144 | 4030.2, 4004.1, 4006.2 |
| full-size | Public hybrid CLI | 47.319, 47.225, 47.142 | 47.225 | 3982.4, 3977.8, 3967.6 |

Compared with the earlier hybrid medians of 3.484 s and 74.196 s, the optimized verifier used **31.8% less wall time on the small proof and 36.4% less on the full-size proof**. Its medians were 3.69× and 5.80× the corresponding C++ times in the table. [Earlier whole-proof measurements](whole-call.md)

The same-host functional Lean OnBytes medians were 3.858 s and 59.567 s. The optimized hybrid used 38.4% and 20.7% less wall time, respectively. Each implementation verified the same bytes under the same policy. Lean ran in a separate timing block. A same-host timing for the theorem-linked Lean verifier remains unmeasured. [Lean results, build identity and scope](onbytes.md)

## Measurement conditions

The host was a 16-core Apple M4 Max with 48 GiB of memory running macOS 26.6.2 arm64. Bend 2.0.40 emitted the native kernels. Apple clang 21.0.0 compiled the public CLI at `-O3` and the hybrid worker and reference verifier at `-O2` with libc++ hardening. The public CLI ran one untimed acceptance at each size first. The measurement harness took a private copy of all three executable files from the isolated candidate build. Each timed process exited zero and matched all four closing lines, including verifier build identity, coverage and work accounting.

Within each size the pair order was reference/hybrid, hybrid/reference, reference/hybrid. Wall time includes startup and reporting. RSS is the per-call macOS `/usr/bin/time -l` reading in MiB. Combined peak memory across stages was unmeasured. Each call used `-j 1` for the request stage. The hybrid and C++ drivers may run key and leaf stages concurrently. Lean OnBytes checks stages sequentially.

| Executable | SHA-256 of executable | Protocol build digest |
| --- | --- | --- |
| Public CLI `verify` | `366fce01e0b9ec9783d02bec2a440964c415cb4c73241fb12963a42ea4ca63fc` | Reports worker digest |
| Hybrid worker `bend_verify` | `318a2f1ceb86fc5623aa9ddafaa8ac784a5a0ebd44ceed9bbf0bb2b5ed4146de` | `5e2d0004174b02f83ce3a95b5c4cef2b4a729f6b0a2e390368feaeaf0f14c2e9` |
| C++ reference `cp_verify` | `8a60b57d76271383409d9e9b08d9398df98aa5245897bbcbb989d394042f63d4` | `93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595` |

To reproduce the complete-call comparison at the candidate revision, build with `make verifier oracle` and run `python3 scripts/e2e.py --benchmark 3 --full-size` after warming the fixture reads. [Measurement harness](../../scripts/e2e.py)
