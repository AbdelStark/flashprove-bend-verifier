#!/usr/bin/env bash
#SBATCH --job-name=flashprove-bend
#SBATCH --partition=main
#SBATCH --constraint=h100
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=160G
#SBATCH --time=1-00:00:00
set -euo pipefail
umask 077
cd "${SLURM_SUBMIT_DIR:?submit through Slurm}"
out=$PWD/build/standalone-${SLURM_JOB_ID:?}
mkdir -p "$out"
export BEND_NO_TELEMETRY=1 BEND_THREADS=1
export BENCH_CHECKOUT_REVISION
BENCH_CHECKOUT_REVISION=$(git rev-parse HEAD)
work=$(mktemp -d "${SLURM_TMPDIR:-/tmp}/bend-benchmark.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
git archive "$BENCH_CHECKOUT_REVISION" | tar -xf - -C "$work"
cd "$work"
uname -srm
lscpu | grep -E '^Model name:|^Architecture:'
g++ --version | head -1
make bootstrap upstream standalone oracle > "$out/build.log" 2>&1
python3 -B scripts/benchmark-standalone.py --output "$out/measurements" | tee "$out/samples.log"
