# Working with the pinned Bend compiler

> Status: living

## What the checker establishes

`make check` checks each Bend source and its imports with the pinned compiler. `make test` runs the known-answer tests on the JS backend. `make test-native` compiles and runs the same expectations on the CPU. Use the native whole-call test as well when a change affects acceptance or the generated C interface.

An independent BendTT kernel can recheck the translated definitions with `--verdict`. Its result is about their declared types. At the revision reviewed in PR #37, the type of the cubic extension product says that it returns three field coordinates. The mathematical law specifying those coordinates remains open. The issue records the exact commands for building the kernel from the pinned Bend distribution and checking the standalone entry. [Kernel check and open arithmetic laws](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/28#issuecomment-7126358874) · [Assurance contract](../spec/assurance.md)

## Arithmetic and native calls

Represent a 64-bit word with two U32 limbs. Test a carry out of the low limb, overflow of the high limb, an encoding equal to the field prime, and tree indices that cross 2³². Define helpers before their callers. In a function that receives several computed records, destructure the parameters together. The extension kernel uses this pattern to sum three 128-bit products before reducing a coefficient. [Extension product](../../src/extension.bend) · [Boundary case](../../tests/extension.bend) · [Python reference](../../tests/extension_random.py)

Only the hybrid worker calls these generated kernel routines from C. When changing the interface, use `make verifier` to exercise the compiled adapter and its field and format vectors with the actual toolchain. The standalone binary reads the proof and computes the verdict in Bend. [Adapter decision](../adr/native-kernels.md) · [Compiler assessment](../research/bend2-assessment.md)

## Tracing a disagreement

- **Transcript.** Compare the domain, nonce, block position and rejection-sampling decisions before comparing the next challenge. The known answers include advancing across hash blocks. [Round driver](../../src/round_io.bend) · [Sampling tests](../../tests/transcript.bend)
- **Merkle openings.** Use the tree kind and depth in the authenticated plan. Track sorted, deduplicated positions and the vertices already seen under the same root. The leaf opening and its path must agree with those earlier observations. [Opening session](../../src/opening_bytes.bend) · [Conflicting sibling](../../tests/opening_bytes.bend) · [Deep tree](../../tests/opening.bend)
- **Model equations.** Run `make stages-full` when changing an equation or its layout. Locate the first differing projected row and compare its public constant, mask substitution and tensor substitution separately. `python3 scripts/model-projections.py` regenerates the feed-forward and output-head reference records from the pinned C++ source. [Projection builder](../../scripts/model-projections.py) · [Stage comparison](../../scripts/test-request-stage.py)

For performance work, pass `-j N` to the standalone native command to select its CPU worker count (1 to 128 in the pinned runtime). With `-timing` the verifier reports the observed worker count and elapsed time per stage on stderr. On macOS, `make profile FIXTURE=accepted-proof` samples a native call. Record the sampling interval and stage when interpreting the result. [Performance contract](../spec/performance.md)

A native compilation of the rectangular tile index exhausted the pinned compiler while specializing a match over two coordinate lists and a six-limb field value. The module passed the source checker. Testing the zero flag separately from the recursive tile and reading each selector through `F.at_bit` allowed native code generation for the whole program. When changing recursive pattern matches on this path, build the complete executable with `make standalone`. [Tile traversal](../../src/segment_layout.bend) · [Projection work](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/40)
