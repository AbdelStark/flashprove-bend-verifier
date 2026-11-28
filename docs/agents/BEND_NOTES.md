# Working with the pinned Bend compiler

> Status: living

## What the checker establishes

`make check` checks each Bend source and its imports with the pinned compiler. `make test` runs the known-answer tests on the JS backend, and `make test-native` compiles the same expectations and runs them on the CPU. When a change affects acceptance or the generated C interface, run the native whole-call test as well.

Bend's independent BendTT kernel can recheck the translated definitions with `--verdict`. It needs Lean v4.34.0 on `PATH`. The official release archive works; you don't need elan. What it confirms is that the definitions have their declared types. For example, the type of the cubic extension product says that it returns three field coordinates. It does not say *which* coordinates, and the law that would say so is still open. [Kernel check and open arithmetic laws](https://github.com/AbdelStark/flashprove-bend-verifier/issues/28#issuecomment-7126358874) · [Assurance contract](../spec/assurance.md)

## Proving laws

`LAWS.bend` states each law and `PROOF.bend` proves it; `make laws` checks both and `make kernel-check` rechecks them with the independent kernel. Write a law about the code in `src/`, not about a copy of it. What we learned proving the limb laws:

- **The checker writes naturals in unary.** A literal above 2^32 − 1 is rejected, and asking it to compute 2^32 overflows the stack. Name the quantity (`pow2(32n)`) and never let the checker unfold it.
- **Keep both sides of every step syntactically identical to the lemma that proves it.** When a comparison fails its quick check, the checker normalizes whole terms, and a term that holds `pow2(32n)` then overflows. Bridge different spellings of the same value (`U32.add` and `Word.adc`, `bits(U32{x})` and `x`) with a small `{==}` lemma that contains no large number.
- **Prove over any width, then apply at 32.** `Word(n)` is a list of bits, lowest first, so an adder law is an induction over `n` with one case per row of the full-adder table. The 32-bit instance is then one application.
- **Base has almost no arithmetic.** `proofs/words.bend` builds what it needs: adding zero or one on the right and doubling a sum.
- **A def may not call a later def, and a match cannot take apart a computed pair.** Compute a carry with its own function (`maj`) instead of destructuring `Bool.full_add`.

Both checks are fast: `make laws` takes under a second, and the kernel rechecks the laws and the standalone verifier in about a minute on an M4 Max.

## Arithmetic and native calls

A 64-bit word is two U32 limbs. Test a carry out of the low limb, overflow of the high limb, an encoding equal to the field prime, and tree indices that cross 2³². Define helpers before their callers: the checker reads a file in order and does not allow mutual recursion. When a function receives several computed records, destructure them as parameters together. The extension kernel uses this to sum three 128-bit products before reducing a coefficient. [Extension product](../../src/extension.bend) · [Boundary case](../../tests/extension.bend) · [Python reference](../../tests/extension_random.py)

## Writing fast Bend

Most of the request stage's time goes to cubic-extension products and reference counting. Measure before changing anything. These patterns paid off in the [speed pass](../research/speed-pass.md):

- **Sharing has a price.** Taking apart a list that is shared (marked `+x`) bumps and later drops a reference count on each node, and the counts are atomic. A loop that walks a shared list once per element is quadratic in those operations. Walk a list once and pass along what you need, or move it into an array.
- **Arrays are linear.** `Array` is a `Type`, not `Data`, so an array has exactly one owner and every read returns it. Thread it through the loop as a parameter. To read and then keep going, pass `Array.get(buf, i)` as an argument and destructure the pair in the callee. Don't use `Array.fork`: it is marked `@unsafe`.
- **Avoid closures in hot loops, but count them first.** `Bool.pick` with two lambdas allocates both closures on every call. A small `match` helper with the branch as a parameter costs nothing extra. A closure call costs about 19 ns on the M4. The profile charges it to `Clo_apply` without its caller, so count calls per target before rewriting. To count them, add a counter to the `Clo_apply` case of the generated C. At `1ac7cbe` the full-size call made 22 M closure calls, about 2.7% of its time. A continuation that recurses through a helper cannot become a template, because it captures a local. Rewriting one into lists of 2^k cells removed 5.7 M calls but slowed the whole call by 7% (#16).
- **Skip the product when you can.** Multiplying by one or minus one is the value or its negation. For an equality factor `{1−x, x}`, the low child is `w − w·x`, so one product serves both children.
- **Recursion must visibly shrink.** When an index climbs toward a bound, pass explicit fuel and recurse on `fuel − 1`.

- **Fork where the tree grows.** The native runtime deals a parallel call's tasks to idle cores while a fork tree grows. A parallel call nested inside a long-running branch, or inside an IO action evaluated purely (`Workers.observe`), tends to run on that branch's core. Keep forks at the top of an IO step, and gather independent work into one balanced tree there. The event loop also runs one computation's pure code at a time, so `IO.fork` does not overlap CPU work. [16-worker report](../research/perf4-2026-11-28.md)

Each of these changes left every computed value unchanged. Keep it that way: an optimization comes with a test that compares the new path to the old one, value by value.

## Tracing a disagreement

- **Transcript.** Compare the domain, nonce, block position and rejection-sampling decisions before comparing the next challenge. The known answers include advancing across hash blocks. [Round driver](../../src/round_io.bend) · [Sampling tests](../../tests/transcript.bend)
- **Merkle openings.** Use the tree kind and depth from the authenticated plan. Track sorted, deduplicated positions and the vertices already seen under the same root. A leaf opening and its path must agree with what was seen before. [Opening session](../../src/opening_bytes.bend) · [Conflicting sibling](../../tests/opening_bytes.bend) · [Deep tree](../../tests/opening.bend)
- **Model equations.** Run `make stages-full` when you change an equation or its layout. Find the first projected row that differs, then compare its public constant, mask substitution and tensor substitution one at a time. `python3 scripts/model-projections.py` regenerates the feed-forward and output-head reference records from the pinned C++ source. [Projection builder](../../scripts/model-projections.py) · [Stage comparison](../../scripts/test-request-stage.py)

For performance work, `-j N` sets the native command's CPU worker count (1 to 128 in the pinned runtime). With `-timing`, the verifier prints the observed worker count and each stage's elapsed time on stderr. On macOS, `make profile FIXTURE=accepted-proof` samples a native call. Note the sampling interval and the stage when you read the result. [Performance contract](../spec/performance.md)

## A compiler limit

Compiling the rectangular tile index to native code once exhausted the pinned compiler. The cause was specializing a single match over two coordinate lists and a six-limb field value. The module passed the source checker. Testing the zero flag separately from the recursive tile, and reading each selector through `F.at_bit`, let the whole program compile. When you change recursive pattern matches on this path, build the complete executable with `make standalone`, not just the module. [Tile traversal](../../src/segment_layout.bend) · [Projection work](https://github.com/AbdelStark/flashprove-bend-verifier/issues/40)
