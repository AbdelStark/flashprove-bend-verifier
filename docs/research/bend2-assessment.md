# Bend 2 as the implementation language: assessment and measurements

> Status: frozen
> Snapshot of 2026-11-23 against Bend 2.0.40 (`toolchain.lock`). First-hand: every claim below was
> read in the then-current Bend sources or measured on this repo's release-toolchain spikes. Not updated after
> acceptance; later facts go to [docs/agents/BEND_NOTES.md](../agents/BEND_NOTES.md) (living).

## Verdict

The release compiler ran the BLAKE2b compression and Goldilocks multiplication spikes within
4.2 to 5.4 times of hand-written C on one core. A separate hash-tree spike scaled to 16 cores.
These runs establish kernel feasibility. Whole-verifier throughput requires an end-to-end measurement. The costs are verbosity, a young toolchain, and no 64-bit integer type yet.

| kernel (one core unless said) | Bend 2.0.40, native | C, `clang -O2` | ratio |
|---|---|---|---|
| BLAKE2b compression | 2.33 M/s (2,000,000 in 0.86 s) | 12.5 M/s (0.16 s) | 5.4x |
| Goldilocks multiplication with full reduction | 80 M/s (20,000,000 in 0.25 s) | 333 M/s (0.06 s) | 4.2x |
| BLAKE2b fork-join tree, 4,194,303 compressions | 1.91 s on 1 thread | n/a | n/a |
| same, 16 threads | 0.15 to 0.18 s wall (12 to 14x) | n/a | n/a |
| read 18.8 MB proof file and parse it as 2,347,442 64-bit words | 0.05 s CPU, 0.3 s wall, 321 MB peak | n/a | n/a |

Machine: Apple M4 Max, 16 cores (12 performance), macOS 26, Apple clang 21. Times are user CPU
seconds unless marked wall. Every Bend result was compared with an independent reference (C with
native `uint64_t`/`__uint128_t`, and Python) and matched bit for bit. Reproduce with `make spikes`;
sources are in [research/spikes/](../../research/spikes/). A freshly built binary pays about 0.25 s
of wall time on its first run on macOS (the system's first-launch check), so wall times of single
runs overstate; CPU times do not.

Scaling of the tree (wall seconds): 1 thread 2.16, 2 threads 0.96, 4 threads 0.48, 8 threads 0.24,
16 threads 0.15 to 0.18. Peak memory 2.5 MB.

## What Bend 2 is

Bend 2 (`github.com/bendlang/bend`, Apache-2.0) is a new language, unrelated in implementation to
Bend 1 and HVM: "Bend 1 programs and HVM do not carry over". It is pure, dependently typed and
affine, with Python-shaped syntax. One checker pass verifies types, termination and proofs; the
compiler emits one C file that clang compiles for the CPU and Metal or CUDA compile for the GPU.
Parallelism is a fork-join of independent calls (`a b = f(x) g(y)`).

Facts that shape this project, each from the Bend README, guide, `WONTFIX.txt` or `bend2/comp.ts`:

1. **Numbers are `Nat`, `U32` and `F32` only.** No `U64`, `I64` or `F64`. `U64` is listed under
   "SOON" ("We will add it ourselves"). A `Nat` is a native integer capped at 2^48 - 1 at runtime;
   past it the program fail-stops.
2. **A term is one 64-bit word**; a `U32` is stored inline. Records of scalars travel in
   registers through calls. There is no garbage collector: affine values are freed where they are
   matched; a value used more than once (`+`) is reference counted.
3. **Arrays** are flat blocks with a power-of-two slot count, mutated in place, with exactly one
   owner. An array cannot be shared by two parallel branches without `@unsafe`; it can be split
   into its two halves (`ANode{xs, ys}`) and rejoined, which is the checked way to parallelize
   over one. An `Array<U32>` spends 8 bytes per slot.
4. **Recursion must terminate**: a recursive call must pass a structurally smaller argument, and
   mutual recursion is not allowed. A loop bounded by data counts down a `Nat`. `@unsafe` turns
   the check off and taints every proof that depends on the def.
5. **No destructuring of a computed value.** A `match` or a destructuring `let` reads a parameter
   or a pattern-bound variable only. A function that needs the parts of a call's result passes the
   result to a helper def that takes it as a parameter. Code is therefore written as chains of
   small defs. Scalar `let`s of computed values are fine.
6. **Defs are ordered**: a def may call only defs written above it (a `law` with a later `def` is
   the forward declaration).
7. **A def takes at most 247 words of arguments.** A `match` on `U32` literals compiles to a bit
   tree and is slow; select with arithmetic or a `Bool` match instead.
8. **No common-subexpression elimination**: two calls of `f(p)` run twice.
9. **IO** is a monad with built-in effects for files (open, sized and positioned byte reads and
   writes), arguments, environment, time, processes, TCP and UDP. `File.read_bytes` answers a
   linked list of bytes (16 bytes of heap per byte read). Foreign effects can be written in C and
   JS but track the compiler's internals with no ABI promise.
10. **Laws and proofs.** `law name: for x: T ... claim` states a proposition; a `def` of the same
    name proves it. `bend PROOF.bend` prints ALL PROOFS CHECK or SOME PROOFS FAIL. `--verdict`
    rechecks with a small kernel that has a proof in Lean (it needs Lean 4.34.0 to build that
    kernel once) and refuses `@unsafe` and foreign code. There are no tactics and no proof search.
11. **Tooling.** One binary, `bend`. `bend f.bend` checks and runs on the JS lane (fast start,
    single core, deep non-tail recursion can overflow the host stack); `bend f.bend -o f` builds a
    native binary (clang 14 or newer; gcc is not supported); `./f +RTS --threads N` sets the
    thread count. There is no test framework, debugger, profiler or REPL. Bend's own tests are
    `.bend` files that end in `#|` lines holding the expected output; this repo uses the same
    convention ([scripts/bend-test.py](../../scripts/bend-test.py)).
12. **Maturity.** Releases come every one to two weeks (2.0.36 on 2026-10-07 to 2.0.40 on
    2026-11-06). The README says the compiler "is 99% AI-written and not yet fully audited" and
    "the checker has no proof and may have bugs; `--verdict` uses a proven kernel". The installed
    binary asks `bend-lang.com` for the latest version once a day unless `BEND_NO_TELEMETRY=1`.

## What the spikes establish

**64-bit arithmetic from 32-bit limbs is cheap enough.** A 64-bit word is a pair of `U32`. Carries
are computed branch-free (`((a & b) | ((a | b) & ~s)) >> 31`). The high half of a 32x32 product
comes from four 16-bit multiplications. The whole Goldilocks multiplication, with the standard
reduction by 2^64 = 2^32 - 1 and 2^96 = -1 and a final canonical step, is about 90 `U32`
operations and no branch; clang turns it into code 4.2 times slower than one native `mul` plus
`umulh`. BLAKE2b's rotations by 32, 24, 16 and 63 are limb swaps and paired shifts.

**The style the compiler rewards is the style the checker forces.** Hot kernels written as
straight-line scalar `let`s inside one def, results returned as small `Data` records, and each
destructuring done by the next def in a chain compile to tight loops with no heap traffic. The
BLAKE2b spike is 159 lines of Bend made by a 150-line generator; one compression is 12 round
defs, each a chain of 8 quarter-round steps.

**Divide-and-conquer parallelism works as advertised** for balanced, independent work. A
Merkle-shaped tree of 4.2 million compressions scales 12 to 14 times on 16 cores with no code
beyond the parallel `let`.

**Whole files can be read in memory** at the sizes this project meets (the largest input is the
18.8 MB full-size proof). A byte list costs 16 bytes per byte while it lives; a streaming parser
frees it as it goes. Nested list patterns (`Con{b0, Con{b1, ...}}`) parse fixed-width fields in
one flat loop.

## Risks and how the design answers them

| risk | evidence | answer |
|---|---|---|
| No `U64`; a native one is announced | README limitations; `WONTFIX.txt` "SOON" | Keep all 64-bit code behind two small modules (`U64`, `Gl`); a native type later changes those modules alone |
| Verbose continuation style makes long protocols hard to read and review | guide, "Recursion and Termination"; spike sources | A naming scheme for step defs, one protocol step per def, and generated code only for mechanical kernels with the generator checked in |
| Arrays cannot be shared across parallel branches without `@unsafe` | guide, "Arrays"; `tests/run/array_fork.bend` | Parse files into immutable `Data` (trees and lists), parallelize over trees; no `@unsafe` in the verifier core |
| `Nat` fail-stops past 2^48 - 1 | `comp.ts` `NAT_IMM`; `WONTFIX.txt` | `Nat` only for loop fuel and small sizes; multi-word integers on `U32` limbs wherever a value can exceed 2^32 |
| Young compiler: miscompilation or checker bug | README limitations | Two lanes (JS and native) must agree in tests; differential tests against `cp_verify`; toolchain pinned by hash; upgrades only by a PR that reruns everything |
| No `F64`: four public tables are defined with double-precision `exp`, `pow`, `cos`, `sin` | FlashProve FORMAT 12.6, 17.1 item 8 | The format lets a verifier take the tables as data and check their digests against the parameter file; that is the design here |
| Deep non-tail recursion overflows on the JS lane | `WONTFIX.txt` "SOON" | Large inputs are tested on the native lane; loops are written as tail calls |
| Proofs about `U32` arithmetic may be expensive (bit-list semantics, no tactics) | guide, "Laws and Proofs"; `base.bend` | Laws are a later, separately gated milestone, starting with small kernels; nothing in the verifier's schedule depends on them |

## Not measured

- GPU lanes (`!` calls): the verifier's work is branchy and pointer-heavy, which the Bend guide
  says stays faster on the CPU.
- Linux x86-64 performance: only macOS arm64 was measured.
- Checker time on large files: the largest file checked here is 160 lines.
- Cost of reference-counted (`+`) sharing of large `Data` across parallel branches.
