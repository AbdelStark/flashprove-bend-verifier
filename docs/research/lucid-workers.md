# Standalone Bend worker scaling on Lucid

> Status: frozen

Sixteen workers verified the full-size exact-match proof in 61.865 s on Lucid, compared with 95.699 s on one worker (medians of three runs, 1.55× speedup). Each process checked the key, the selected leaf and the 18,779,540-byte request proof. The result covered reply tokens 24 through 1023 and the proposed next token under a committed model with synthetic weights. [Proof and expected result](https://github.com/anthropics/FlashProve/blob/9e2bdd8ff5bf9c62f18263d7dac189b0400b260c/examples/full-size/README.md)

| Bend workers | Median wall (s) | Speedup over 1 worker | Median user + system CPU (s) | Highest peak RSS (MiB) |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 95.699 | 1.00× | 95.37 | 2,229 |
| 2 | 96.557 | 0.99× | 109.79 | 2,369 |
| 4 | 72.344 | 1.32× | 113.38 | 2,767 |
| 8 | 61.284 | 1.56× | 115.65 | 3,454 |
| 16 | 61.865 | 1.55× | 124.16 | 3,558 |

At eight and sixteen workers, the verifier prepares at most eight segments in a batch. Their median wall times differed by 0.581 s. The 16-worker pool used 1.30× the total CPU time of the one-worker run. It overlaps independent segment equations and column projections while passing the FOLD state from one segment to the next in order. The ratio of median CPU time to median wall time at 16 workers was 2.01, in units of fully occupied cores. [Segment scheduling](https://github.com/AbdelStark/fv-flashprove-bend-verifier/blob/ca1297cbe4a9ca8d3e8d8baa03bb7b2e2993bbf9/src/segment_chain.bend) · [FOLD transport](https://github.com/AbdelStark/fv-flashprove-bend-verifier/blob/ca1297cbe4a9ca8d3e8d8baa03bb7b2e2993bbf9/src/segment_transport.bend)

## Measurement

Slurm job 7720 ran on `rtx-cc-2` on 2026-11-24. The guest reported 16 KVM virtual CPUs, Intel family 6 model 207 stepping 2, with one thread per core. The process could run on CPUs 0 through 15.

Every timed call started a fresh process with an empty executable search path and warm files. The wall clock included startup, file reads and verdict output. Each worker setting had one discarded warmup with `-timing`, which reported the actual worker count. It matched the requested count at all five settings. The timed calls used `-q`. All twenty executions exited zero and printed the fixture's four expected lines, including the executable's source digest and `YES`. The raw records contain the run order, Linux peak RSS in KiB, user and system CPU times, file hashes and compiler identity. [Raw samples](lucid-workers.json)

In the diagnostic warmups, the request stage accounted for 90% of the internal elapsed time at one worker and 85% at sixteen. It still took 56.041 s with sixteen workers. Issue #20 targets a sixfold speedup at sixteen workers. Timing the request equations inside this build would distinguish the cost of ordered FOLD transitions from work that can run concurrently. [Request-stage issue](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/20) · [Performance tracker](https://github.com/AbdelStark/fv-flashprove-bend-verifier/issues/23)

| Diagnostic stage | 1 worker (s) | 16 workers (s) |
| --- | ---: | ---: |
| public | 1.851 | 2.011 |
| key | 5.510 | 5.852 |
| leaf | 2.122 | 2.187 |
| request | 85.457 | 56.041 |

## Replay on Linux

Use a clean checkout of the measured revision and a 16-CPU allocation. This Bash command set uses GNU time to print wall, user and system seconds and peak RSS in KiB. The original sampler used Python's monotonic clock around the same child process and Linux `getrusage` for CPU and RSS.

```bash
set -euo pipefail
git checkout --detach ca1297cbe4a9ca8d3e8d8baa03bb7b2e2993bbf9
make bootstrap upstream standalone
f=.upstream/FlashProve/examples/full-size
out=$(mktemp -d "$PWD/build/workers.XXXXXXXX")
digest=$(cat build/verify-bend.digest)
sed -n '/^commitment: /,/^YES$/p' "$f/README.md" |
  sed "s/<64 hex digits>/$digest/" > "$out/expected"
verify=("$PWD/build/verify-bend" "$f/config" "$f/ivk" "$f/example.req"
        "$f/example.y" "$f/example.proof" -id "$(cat "$f/ID.txt")" -data build)

run() {
  local n=$1 sample=$2 log="$out/$1-$2"
  local mode=-q
  if [[ $sample == warmup ]]; then mode=-timing; fi
  PATH='' /usr/bin/time -f '%e %U %S %M' -o "$log.time" \
    "${verify[@]}" -j "$n" "$mode" > "$log.stdout" 2> "$log.stderr"
  cmp "$out/expected" "$log.stdout"
  if [[ $sample == warmup ]]; then
    grep -Fx "timing: workers $n" "$log.stderr"
  else
    test ! -s "$log.stderr"
    cat "$log.time"
  fi
}

run 16 warmup
run 16 1
for n in 1 2 4 8; do run "$n" warmup; run "$n" 1; done
run 16 2
run 16 3
for sample in 2 3; do
  for n in 8 4 2 1; do run "$n" "$sample"; done
done
```
