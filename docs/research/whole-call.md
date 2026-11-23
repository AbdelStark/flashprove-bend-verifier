# Whole-proof verification on Apple M4 Max

> Status: frozen

Experiment date 2026-11-23. The subject is the public Bend CLI `verify`. It checks the statement headers and commitment ID in Bend, then executes its sibling `bend_verify`, which runs the pinned C++ protocol driver with native Bend kernels. The comparator is the unmodified reference `cp_verify`. Each call checks the key, leaf and request, including the proof body. The inputs are upstream's stored proofs for synthetic weights.

The public command and worker were built from [c1b975e](https://github.com/AbdelStark/fv-flashprove-bend-verifier/tree/c1b975e25c329f6895c04f0c2c0ca9a5e431be5c).

## Results

Three exact-match calls at each size produced the following wall times. Every sample returned `YES` and the expected commitment, coverage, policy and accounting.

| Fixture | Executable | Three calls (s) | Median (s) | Range (s) | Max RSS range (MiB) |
| --- | --- | --- | ---: | --- | --- |
| accepted-proof | `cp_verify` | 0.963, 0.636, 0.644 | 0.644 | 0.636–0.963 | 190.8–193.8 |
| accepted-proof | `verify` | 3.893, 3.469, 3.484 | 3.484 | 3.469–3.893 | 191.5–197.2 |
| full-size | `cp_verify` | 8.061, 8.077, 8.253 | 8.077 | 8.061–8.253 | 3,780.9–4,027.0 |
| full-size | `verify` | 74.196, 73.976, 74.256 | 74.196 | 73.976–74.256 | 3,965.1–3,978.0 |

At one request-stage thread, the public Bend path took 5.41× as long on the small proof and 9.19× as long on the full-size proof as the unmodified C++ reference.

One exploratory pair per size used eight request-stage threads (`-j 8`). Each call returned `YES`. These individual observations have no within-setting range.

| Fixture | C++ (s) | Public Bend CLI (s) | C++ max RSS (MiB) | Bend max RSS (MiB) |
| --- | ---: | ---: | ---: | ---: |
| accepted-proof | 0.786 | 3.636 | 193.6 | 192.5 |
| full-size | 6.415 | 56.057 | 4,008.8 | 3,978.4 |

## Reproduction

```sh
make verifier oracle
python3 scripts/e2e.py --full-size
python3 scripts/e2e.py --benchmark 3 --full-size
python3 scripts/e2e.py --benchmark 1 --full-size --threads 8
```

The machine ran macOS 26.6.2 on a 16-core arm64 Apple M4 Max with 48 GiB of memory. Apple clang 21.0.0 compiled the public CLI at `-O3` and both C++ programs at `-O2` with libc++ hardening. The Bend compiler was 2.0.40. The `build=` field identifies the worker used in a verification call. The separately compiled public CLI has its own executable fingerprint.

| Executable | Build digest |
| --- | --- |
| Hybrid worker | `d52d8d292b47e7e62c413b21d147e71b26d3738225d03a15ae1b68eb2d856581` |
| C++ reference | `93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595` |

Executable SHA256 values identify the files used for every sample.

- `cp_verify` – `8a60b57d76271383409d9e9b08d9398df98aa5245897bbcbb989d394042f63d4`
- `bend_verify` – `2c0f2d5cd9d0bbe0b045449238e23ec195a0b4d5b4d7e90446235d83203e5627`
- `verify` – `366fce01e0b9ec9783d02bec2a440964c415cb4c73241fb12963a42ea4ca63fc`

The primary comparison uses one thread in the request stage (`-j 1`). The key and leaf stages can run concurrently. Both executables rely on the upstream driver to schedule these stages and their workers. Timing starts before launching the process and ends after collecting its exit status and output. Each sample must exit zero and match all four closing lines in the fixture documentation, including the tested binary's build digest.

The correctness run precedes the benchmark and warms the filesystem cache. Each timed call starts a fresh process. Run order alternates within each fixture, beginning with the reference, then the hybrid. The harness copies all three executables into a fresh private directory before sampling. Calls include process startup, file reads, verification and reporting. On the public Bend path they also include the preflight and transfer to the worker. Builds and fixture fetches run outside the timing interval. Maximum RSS is the figure for the call reported by macOS `/usr/bin/time -l`, in MiB. The simultaneous total across the three stages was unmeasured.

## Request-stage sample

During a separate correctness call on the full-size clipped-gap fixture, macOS `sample` observed the request process for two seconds at 5 ms intervals, beginning about 31 seconds after launch. Of 351 main-thread samples, 279 ended in the native Bend base-field multiplication function and 37 ended in native Bend cubic-extension multiplication. The sample covers one interval of the request stage. It motivates measuring field multiplication in the same stage after an optimization.

## Lean comparison

On this machine the native Lean OnBytes program verified the same small and full-size exact-match inputs. The runs used the same configuration, request, next token, commitment and proof. OnBytes ran its stages sequentially in a later set of runs. [Native Lean measurements](onbytes.md)

The upstream proved-verifier command requires Linux x86-64. Upstream reports 19–39 minutes per full-size acceptance or late rejection on earlier versions of its Lean and parser sources, across several Linux machines. A same-host comparison with that proved verifier remains unmeasured. [Upstream measurement methods and limits](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/tools/lean-verify/README.md#what-it-costs)
