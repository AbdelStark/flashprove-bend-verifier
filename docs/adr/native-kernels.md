# Bend kernels in the hybrid verifier

> Status: living

The first prototype put individual Bend kernels inside the pinned C++ verifier. We wanted to measure a kernel on a real proof while the upstream driver handled the rest of the protocol. The standalone verifier now implements the three stages in Bend. We keep the hybrid for comparisons with those early measurements. [Hybrid measurements](../research/field-performance.md) · [Standalone entry](../../src/standalone.bend)

The hybrid command, `build/verify`, checks the public statement and derives the commitment ID in Bend. It passes the arguments to the sibling `build/bend_verify` worker. The worker reads its own snapshot of the files, rechecks the binding and runs the proof stages. Both binaries are needed for a hybrid call. [Hybrid entry](../../src/verify.bend) · [Verification contract](../spec/verifier.md)

The worker build takes the C++ sources from the pinned Git object and patches the chosen primitives to call compiler-generated Bend routines. A C adapter passes word limbs and output buffers across that boundary. An upgrade to the Bend compiler must pass the field tests and format vectors through the compiled adapter. The hybrid build digest identifies the protocol revision, compiler lock and port sources. Benchmark records give separate executable hashes for the CLI, its worker and the unmodified oracle. [Worker build](../../scripts/build-verifier.sh) · [C adapter](../../src/native/bridge.c)
