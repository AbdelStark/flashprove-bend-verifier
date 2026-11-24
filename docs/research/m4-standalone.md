# Standalone Bend and Lean OnBytes on the M4 Max

> Status: frozen

Measured 2026-11-24 during review of [PR #37](https://github.com/AbdelStark/fv-flashprove-bend-verifier/pull/37#issuecomment-7126797931).

On the same full-size exact-match proof, standalone Bend took **254.945 s** by median and native Lean OnBytes took **58.693 s**. Bend used 4.34 times the wall time and 2.21 times the peak resident memory. Both programs accepted the same commitment, request tokens 24 through 1023 and the next token. The proof covers inference under synthetic weights at the full model's dimensions. [Fixture](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md)

| Native CPU program | Wall seconds in sample order | Median wall (s) | Median user + system CPU (s) | Peak RSS range (MiB) |
| --- | --- | ---: | ---: | ---: |
| Bend standalone | 259.320, 254.945, 252.165 | 254.945 | 254.66 | 11,099.0–11,099.2 |
| Lean OnBytes | 61.318, 58.595, 58.693 | 58.693 | 58.64 | 5,028.2–5,029.0 |

## What was timed

A 16-core Apple M4 Max running macOS 26.6.2 (arm64) ran one verifier at a time. Each executable completed a discarded warmup, Lean first. The three measured pairs then ran Lean/Bend, Bend/Lean, Lean/Bend. Every call started a fresh process with an empty executable search path and read the same files. The timer covered invocation through exit, including I/O and verdict output. macOS `/usr/bin/time -l` supplied CPU time and peak RSS. Local CI shared the machine during the first pair. These are three observations on a warm filesystem cache.

Each run exited zero and matched all four expected closing lines, including the executable's build marker and its wording of the commitment assumption. OnBytes received `-j 1` and executes sequentially. The Bend source also ran sequentially, with its default runtime pool. The worker count was unmeasured. [OnBytes output source](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/lean/OnBytes/Shell/Lines.lean) · [Worker-count experiment](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/19#issuecomment-7126288622)

An 18-second stack sample during Bend's discarded warmup captured 7,800 stacks on its working thread. Reference counting and freeing accounted for 40.7% of the samples, closure application for 19.2%, and two field multiplication routines for 19.3%. These shares describe that interval. The three timed pairs ran without instrumentation. The earlier Lucid measurements used a different CPU and an earlier Bend kernel. [Profile and measurement log](https://github.com/AbdelStark/fv-flashprove-bend-verifier/pull/37#issuecomment-7126797931) · [Lucid runs](lucid.md)

## Build and input identities

Bend 2.0.40 emitted C from verifier revision `e64e31ab4d51205d3e57bbfb5060267c3e15aedf`. Apple Clang 21.0.0 compiled it with `-std=c11 -O3 -lpthread -lm`. Lake built `OnBytes.Main` with the official arm64 Lean 4.29.1 release from FlashProve revision `9e2bdd8ff5bf9c62f18263d7dac189b0400b260c`. [Native build](../../scripts/compile_bend.py) · [Lean build](../../scripts/onbytes-build.sh)

| Identifier | Value |
| --- | --- |
| Proof SHA-256 (18,779,540 bytes) | `efa762e20f72b64e183ad6f688eccf5b2b79649928d8e3a2a96645645dd08af9` |
| Fixture commitment ID | `7a285919b43961861d9839530c26725accf26aa6d74e3c2afa31b9dc6bcd18fe` |
| Bend source digest in the verdict | `1abbca5b9721895469b4b1ada016b3f999acedeaf4be537b3995a376aa81d9db` |
| Bend executable SHA-256 | `c3cc9dbbec0e35303fc42360a59d01df950b3761d1fd748f3fc3581de9b66fbe` |
| Lean OnBytes executable SHA-256 | `8f2f864ba261dbd37d01eb38f90f19542729e5fcacf808d182c64310e7a4e086` |

## Repeat the comparison

Run this Bash block on macOS from a checkout of the measured revision to repeat the workload. The fixture supplies the ID for this experiment. The script checks the exit status and the final four lines of every call before keeping its timing. `*.time` files contain wall and CPU seconds and peak RSS in bytes.

```bash
set -eu
make bootstrap upstream standalone lean-baseline
ulimit -s 10240
proof_dir="$PWD/.upstream/FlashProve/examples/full-size"
out=$(mktemp -d "$PWD/build/m4-benchmark.XXXXXX")
mkdir "$out/empty-path"
inputs=("$proof_dir/config" "$proof_dir/ivk" "$proof_dir/example.req"
        "$proof_dir/example.y" "$proof_dir/example.proof" -id "$(cat "$proof_dir/ID.txt")" -q)

sed -n '/^commitment: /,/^YES$/p' "$proof_dir/README.md" > "$out/fixture"
sed "s/<64 hex digits>/$(cat build/verify-bend.digest)/" "$out/fixture" > "$out/bend.expected"
sed -e 's/<64 hex digits>/lean-verify-on-bytes/' \
    -e 's/the bound within a third of the distance/the proved lemma/' "$out/fixture" > "$out/lean.expected"

for call in warmup-lean warmup-bend 1-lean 1-bend 2-bend 2-lean 3-lean 3-bend; do
  program=${call#*-}
  if [[ "$program" == bend ]]; then
    cmd=("$PWD/build/verify-bend" "${inputs[@]}" -data "$PWD/build")
  else
    cmd=("$PWD/build/verify-on-bytes" verify "${inputs[@]}" -j 1)
  fi
  PATH="$out/empty-path" LC_ALL=C LEAN_ABORT_ON_PANIC=1 /usr/bin/time -l -o "$out/$call.time" \
    "${cmd[@]}" > "$out/$call.stdout"
  tail -n 4 "$out/$call.stdout" | diff - "$out/$program.expected"
done
echo "$out"
```
