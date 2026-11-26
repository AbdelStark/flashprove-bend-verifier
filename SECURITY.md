# Reporting a verifier defect

Please send a [private vulnerability report](https://github.com/AbdelStark/flashprove-bend-verifier/security/advisories/new) if:

- Bend accepts a proof that the pinned FlashProve verifier refuses;
- an accepted result contradicts the format; or
- a crafted file crashes the verifier or makes it use unbounded time or memory.

A genuine proof that Bend refuses under one of the four supported configurations also deserves investigation. If the inputs are safe to publish, a public issue is fine for that and for other compatibility problems.

In the report, include the repository revision, configuration, operating system and command. Give the exit status and the last lines of output from both `build/verify-bend` and the pinned C++ `build/cp_verify`. Say which commitment, policy and token range you expected. For a case found by `make fuzz`, include the fixture, seed and case index. If you can, reproduce the problem on a small synthetic fixture or an edited copy of a published example. That lets someone else repeat it without seeing your private prompts, keys or weights.

The verification contract lists the four supported configurations. The assurance contract records what has been tested and what still needs a proof, including how this verifier relates to the upstream Lean development. [Verification contract](docs/spec/verifier.md) · [Assurance contract](docs/spec/assurance.md)
