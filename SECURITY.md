# Reporting a verifier defect

If Bend accepts a proof that the pinned FlashProve verifier refuses, or an accepted result contradicts the format, please send a [private vulnerability report](https://github.com/AbdelStark/flashprove-bend-verifier/security/advisories/new). Use the same channel for a crafted file that crashes the verifier or causes unbounded resource use. A genuine proof refused under one of the four supported configurations also deserves investigation. Use a public issue for an ordinary compatibility problem when the inputs and details are safe to publish.

Include the repository revision, configuration, operating system and command. Record the exit status and last output lines from both `build/verify-bend` and the pinned C++ `build/cp_verify`. Say which commitment, policy and token range you expected. For a case from `make fuzz`, include the fixture, seed and case index. A small synthetic fixture or a change to a published example lets someone else repeat the observation while keeping private prompts, keys and weights out of the report.

The verification contract lists the four supported configurations. The assurance contract records the conformance evidence and the outstanding proof obligations, including the relationship to upstream Lean. [Verification contract](docs/spec/verifier.md) · [Assurance contract](docs/spec/assurance.md)
