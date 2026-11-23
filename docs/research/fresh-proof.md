# A freshly generated next-token proof

> Status: frozen

On 2026-11-23 we generated a new commitment to FlashProve’s small H821 synthetic model and proved inference on a 64-token prompt. The production C++ verifier and the standalone Bend verifier both exited 0 with `YES`. They agreed on all four closing lines once each implementation’s source digest was accounted for. [Public input hashes and closing lines](fresh-proof.json)

| Field | Observed value |
|---|---|
| Caller’s commitment ID | `b3dc79c87ecd3ec1b3adcdeca7671965ae1fed9490f31ad95862b4a6cee6de83` |
| Request | `r=63 e=64 T=64 tokens=none y=yes` |
| Next token | 301 |
| Request proof length | 4,154,796 bytes |
| Request proof SHA-256 | `3d187cc1df95a9db004877221d806758fc7f49bb5bdb08a13967740be56fd908` |
| C++ source digest | `93afdaf592393a54ebd17b681d1c03295eb883f0161ff0e6ab872a3b39939595` |
| Bend source digest | `4bc6ecdd34e1c59e5b65518a3752a1a8b8797f6024bc5cefd5bb906a59f67df5` |

The recorded run built the serving programs on Lucid’s H100 NVL and generated the proof on an NVIDIA H100 80GB HBM3 SXM with driver 580.173.02. The batch script below builds and runs on the SXM. The allocated GPU matched all 324 CPU values in the upstream compiler control before generation. The public record includes SHA-256 digests of the three serving executables built with nvcc 13.2.86 and g++ 13.

The provider used the three public files from `examples/accepted-proof/config`. The pinned serving `cp_commit` drew its own randomness with `-weights made-up-blocks -M 1`. Upstream’s request generator selected `r=T−1` and `e=T`, so the evidence covers the token after the prompt. The same ID, request, response, key, leaf and proof went into both whole verification calls. The request, proof and provider secrets stayed on the compute node. [Pinned GPU procedure](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/prover/examples/run_target_example.sh)

## Reproduce

On Linux with an available H100, g++ 13 and CUDA 13.2 Update 2, run the following command. Each run generates a fresh ID and proof. The public configuration hashes, coverage checks and agreement between the two independent verifiers are the repeatable conditions. [Harness](../../scripts/fresh-proof.py) · [Compiler release](https://docs.nvidia.com/cuda/archive/13.2.2/cuda-toolkit-release-notes/index.html)

```sh
make fresh-proof
```

To run on Lucid, prepare the Linux standalone binary and public data with `make standalone upstream`, then submit `sbatch scripts/cluster/fresh-proof.sh` from the checkout. The job uses one regular H100 and a private node-local work directory. It records public evidence under `build/fresh-proof-JOBID.json`. Lucid’s confidential H100 NVL returned `operation not supported` when the production committer registered host memory at `hf_commit_weights.cuh:145`. The measured proof came from the non-confidential H100 SXM. [Batch script](../../scripts/cluster/fresh-proof.sh) · [Required registration](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/prover/hash_commitment/hf_commit_weights.cuh#L145)
