# Working with the pinned Bend compiler

> Status: living

## What the checker establishes

`make check` checks each Bend source and its imports with the pinned compiler. `make test` runs the known-answer tests on the JS backend, and `make test-native` compiles the same expectations and runs them on the CPU. When a change affects acceptance or the generated C interface, run the native whole-call test as well.

Bend's independent BendTT kernel can recheck the translated definitions with `--verdict`. It needs Lean v4.34.0 on `PATH`. The official release archive works; you don't need elan. What it confirms is that the definitions have their declared types. For example, the type of the cubic extension product says that it returns three field coordinates. It does not say *which* coordinates, and the law that would say so is still open. [Kernel check and open arithmetic laws](https://github.com/AbdelStark/flashprove-bend-verifier/issues/28#issuecomment-7126358874) · [Assurance contract](../spec/assurance.md)

## Arithmetic and native calls

A 64-bit word is two U32 limbs. Test a carry out of the low limb, overflow of the high limb, an encoding equal to the field prime, and tree indices that cross 2³². Define helpers before their callers: the checker reads a file in order and does not allow mutual recursion. When a function receives several computed records, destructure them as parameters together. The extension kernel uses this to sum three 128-bit products before reducing a coefficient. [Extension product](../../src/extension.bend) · [Boundary case](../../tests/extension.bend) · [Python reference](../../tests/extension_random.py)

## Writing fast Bend

Most of the request stage's time goes to cubic-extension products and reference counting. Measure before changing anything. These patterns paid off in the [speed pass](../research/speed-pass.md):

- **Sharing has a price.** Taking apart a list that is shared (marked `+x`) bumps and later drops a reference count on each node, and the counts are atomic. A loop that walks a shared list once per element is quadratic in those operations. Walk a list once and pass along what you need, or move it into an array.
- **Arrays are linear.** `Array` is a `Type`, not `Data`, so an array has exactly one owner and every read returns it. Thread it through the loop as a parameter. To read and then keep going, pass `Array.get(buf, i)` as an argument and destructure the pair in the callee. Don't use `Array.fork`: it is marked `@unsafe`.
- **Avoid closures in hot loops.** `Bool.pick` with two lambdas allocates both closures on every call. A small `match` helper with the branch as a parameter costs nothing extra.
- **Skip the product when you can.** Multiplying by one or minus one is the value or its negation. For an equality factor `{1−x, x}`, the low child is `w − w·x`, so one product serves both children.
- **Recursion must visibly shrink.** When an index climbs toward a bound, pass explicit fuel and recurse on `fuel − 1`.

Each of these changes left every computed value unchanged. Keep it that way: an optimization comes with a test that compares the new path to the old one, value by value.

## Tracing a disagreement

- **Transcript.** Compare the domain, nonce, block position and rejection-sampling decisions before comparing the next challenge. The known answers include advancing across hash blocks. [Round driver](../../src/round_io.bend) · [Sampling tests](../../tests/transcript.bend)
- **Merkle openings.** Use the tree kind and depth from the authenticated plan. Track sorted, deduplicated positions and the vertices already seen under the same root. A leaf opening and its path must agree with what was seen before. [Opening session](../../src/opening_bytes.bend) · [Conflicting sibling](../../tests/opening_bytes.bend) · [Deep tree](../../tests/opening.bend)
- **Model equations.** Run `make stages-full` when you change an equation or its layout. Find the first projected row that differs, then compare its public constant, mask substitution and tensor substitution one at a time. `python3 scripts/model-projections.py` regenerates the feed-forward and output-head reference records from the pinned C++ source. [Projection builder](../../scripts/model-projections.py) · [Stage comparison](../../scripts/test-request-stage.py)

For performance work, `-j N` sets the native command's CPU worker count (1 to 128 in the pinned runtime). With `-timing`, the verifier prints the observed worker count and each stage's elapsed time on stderr. On macOS, `make profile FIXTURE=accepted-proof` samples a native call. Note the sampling interval and the stage when you read the result. [Performance contract](../spec/performance.md)

## A compiler limit

Compiling the rectangular tile index to native code once exhausted the pinned compiler. The cause was specializing a single match over two coordinate lists and a six-limb field value. The module passed the source checker. Testing the zero flag separately from the recursive tile, and reading each selector through `F.at_bit`, let the whole program compile. When you change recursive pattern matches on this path, build the complete executable with `make standalone`, not just the module. [Tile traversal](../../src/segment_layout.bend) · [Projection work](https://github.com/AbdelStark/flashprove-bend-verifier/issues/40)
