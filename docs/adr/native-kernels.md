# Run Bend kernels inside the H821 protocol driver

> Status: living

The first executable milestone needs to check complete inference proofs and isolate the cost of ported operations. H821 ties its public configuration, sampled positions, model equations and final accounting together across three stages. Checking only a header, a fixture digest or a sequence of Merkle paths cannot establish its inference statement. [Verification contract](../spec/verifier.md)

Use a Bend entry point to check the public statement and independently derive the caller-named commitment. Hand the unchanged argument vector to the sibling worker. The worker reads the public inputs into its own snapshot, rechecks their binding and runs every required proof stage. Ship the entry point and worker together.

Build the worker from an archive of the locked upstream Git object. Apply reviewed patches that replace the selected primitives with native Bend implementations. The pinned compiler exposes these pure functions as internal C routines with an output buffer. The build entry keeps them reachable during C generation. The adapter converts word limbs and aborts on a failed kernel call. A compiler upgrade must exercise the compiled adapter, including the field reference and format-vector suites, before using the new ABI. [Build](../../scripts/build-verifier.sh) · [Adapter](../../src/native/bridge.c)

The worker's build digest identifies the protocol revision, compiler lock and native port sources. The benchmark records separate executable hashes for the public CLI, worker and unmodified oracle. The hybrid shares its model checks with the oracle. An independent verifier needs the remaining plan, transcript, opening-consistency, model and accounting checks in Bend. [Implementation order](../plan/implementation.md)
