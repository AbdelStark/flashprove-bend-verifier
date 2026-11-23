# Native Lean OnBytes baseline

> Status: frozen

On 2026-11-23, the Apple M4 Max benchmark used the unmodified `OnBytes.Main` program from the FlashProve revision in [upstream.lock](../../upstream.lock). It is a separate Lean translation of the C++ checks. The theorem-linked `tools/lean-verify` program requires Linux x86-64 and has a different execution path. [OnBytes command and scope](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/OnBytes/README.md) · [Known differences from C++](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/OnBytes/LIMITS.md)

## Results

All six exact-match calls exited zero and produced the expected result-v1 fields and closing YES. Each full-size call covered request tokens 24 through 1023 and the next token under the caller's named commitment. The small public proof covered tokens 61 through 63 and the next token.

| Stored fixture | Wall seconds, in order | Median (s) | Max RSS per call (MiB) |
|---|---|---:|---|
| accepted-proof | 4.160, 3.858, 3.851 | 3.858 | 243.4, 243.2, 243.6 |
| full-size | 59.488, 59.567, 59.641 | 59.567 | 5,028.5, 5,029.1, 5,028.5 |

The changed small proof returned `NO: proof-refused` with exit 1 in 1.987 s and reached 112.0 MiB peak RSS.

On the same M4 Max the public hybrid command with `-j 1` took 3.484 s at small size and 74.196 s at full size by median. It took 9.7% less time than native OnBytes on the small fixture and 24.6% more time on the full fixture. The unmodified C++ medians were 0.644 s and 8.077 s, respectively. These figures cover these builds, machine and exact-match synthetic proofs. [Hybrid measurements and build identities](whole-call.md)

## Reproduction

```sh
make upstream
bash scripts/onbytes-build.sh
python3 scripts/onbytes-test.py --samples 3
```

The optional build uses Git, Bash, curl, tar and either zstd or Python 3.14+ with the standard zstd module. It downloads the official Lean 4.29.1 release into a temporary directory, checks its published SHA-256 and installs it under the repository's ignored toolchain directory. The script checks the compiler version and release commit on reuse. The isolated Lake project builds the 200 imported source modules from Fmt, OnBytes and Run with Lean's bundled standard library. It retains the upstream Lean options and invokes the compiler's bundled C toolchain. No external Lake packages are required. [Official Lean release](https://github.com/leanprover/lean4/releases/tag/v4.29.1) · [Build script](../../scripts/onbytes-build.sh)

With the release already extracted, the isolated build completed 402 Lake jobs in 48.93 s wall, using 149.81 s user and 21.25 s system CPU time. The build ran with LEAN_NUM_THREADS=4 and nice level 5. The peak RSS reported by macOS time was 3,664 MiB. The installed executable was 10,246,896 bytes. Its dynamic dependencies were the system libc++ and libSystem, as reported by otool after moving it out of the build directory. Its SHA-256 was `8f2f864ba261dbd37d01eb38f90f19542729e5fcacf808d182c64310e7a4e086`.

The build script includes release checksums for Linux and macOS on x86-64 and arm64. This run tested macOS arm64. The release download was 526,032,638 bytes, and the extracted toolchain used 2,578 MiB on this machine. Allow additional temporary space for the download, source and compiled objects.

The harness starts a fresh native process per proof. Both model sizes use the upstream exact-match policy, an explicit trusted fixture ID and `-j 1`. OnBytes ignores the thread option and runs its checks sequentially. Every accepted call must exit zero and produce the complete expected result-v1 record with its own build marker, followed by YES. The request range, policy, stage coverage, work accounting and ID all participate in that comparison. A separate small proof with one bit changed must exit one and finish with a rejection. Wall time includes process startup, reads and verdict output. The harness obtains peak resident memory via the host's time program and raises the process stack limit to at least 10 MiB for these runs. The Lean calls ran after the other verifier measurements had finished and the filesystem cache was warm. They ran consecutively in their own measurement block. No Lean warm-up was discarded. [Measurement harness](../../scripts/onbytes-test.py)
