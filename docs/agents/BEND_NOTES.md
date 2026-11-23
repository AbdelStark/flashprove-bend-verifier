# Working with the pinned Bend compiler

> Status: living

Start with `make bootstrap`. The compiler lives inside the checkout and writes native CPU binaries using Clang. Run `make check` for type and proof checks, `make test` for small interpreter expectations and `make test-native` for their compiled counterparts. Native end-to-end tests must also exercise any generated C or build integration used by the verifier.

Model 64-bit words with two U32 limbs in this toolchain. Include boundary cases for low-word carry, high-word wraparound, a value equal to the field prime, final-block handling and indices crossing 2³². Match on parameters or pattern-bound values and define helpers before callers. Use the existing spike references to cross-check arithmetic. [Compiler assessment](../research/bend2-assessment.md)

A type check, the checker’s proof status and a known-answer test answer different questions. Report which was run and which property it covered. For changes to FFI or generated-C bindings, record the compiler pin and prove the symbol on the real verifier path was exercised. Recheck bindings after a toolchain change.

The standalone verifier builds each Fiat–Shamir round in Bend, checks the nonce and samples the resulting stream. The shared predicates cover work bits, canonical field candidates and positions. The transcript tests also cover rejection sampling and advancement across hash blocks. [Round driver](../../src/round_io.bend) · [Transcript](../../src/transcript.bend) · [Known answers](../../tests/transcript.bend)

For a multi-opening, the authenticated plan supplies the depth and tree kind. The verifier consumes the columns and siblings for the sorted, deduplicated positions, checks the root, and carries the per-root vertex record across key, leaf and request stages. A failed opening returns no updated session. Regression vectors include a conflict with an earlier vertex and positions above 2³². [Opening bytes and session](../../src/opening_bytes.bend) · [Opening tests](../../tests/opening_bytes.bend) · [Deep tree test](../../tests/opening.bend)

Run `make stages-full` when changing a model equation or its layout. The native probe compares the ordered local rows, evaluation tables, deferred weight claims and physical batch projections on genuine inputs. If a projection differs, compare the public constant, mask substitution and tensor substitution separately at the first differing stage. To reproduce the G and H reference records from a clean copy of the pinned verifier source, run `python3 scripts/model-projections.py`. [C++ projection builder](../../scripts/model-projections.py) · [Bend stage comparison](../../scripts/test-request-stage.py)

The standalone entry reads proof bytes in Bend and is built by `make standalone`. The earlier hybrid entry uses the host effect `Backend.exec` to launch its C++ worker. The source checker admits the precise foreign-effect diagnostic at the hybrid entry. [Standalone entry](../../src/standalone.bend) · [Hybrid entry](../../src/verify.bend) · [Checker](../../scripts/bend-check.py)
