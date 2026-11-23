#!/usr/bin/env bash
#SBATCH --job-name=flashprove-lean
#SBATCH --partition=main
#SBATCH --constraint=h100
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=160G
#SBATCH --time=08:00:00
# Submit from a committed checkout. Only the small logs use the shared home quota.
set -euo pipefail
umask 077
cd "${SLURM_SUBMIT_DIR:?submit through Slurm}"
out=$PWD/build/lucid-$SLURM_JOB_ID
mkdir -p "$out"
run=$(mktemp -d "${SLURM_TMPDIR:-/tmp}/flashprove.XXXXXXXX")
git rev-parse HEAD > "$out/revision"
git archive "$(cat "$out/revision")" | tar -xf - -C "$run"
cd "$run"
. ./upstream.lock
export LEAN_NUM_THREADS="$SLURM_CPUS_PER_TASK" LEAN_ABORT_ON_PANIC=1
export TMPDIR=$run/build/tmp XDG_CACHE_HOME=$run/build/cache
mkdir -p "$TMPDIR" "$XDG_CACHE_HOME"
printf 'Node-local workspace %s\n' "$run"
uname -srm
lscpu | grep -E '^Model name:|^Architecture:'
grep '^PRETTY_NAME=' /etc/os-release
g++ --version | head -1
printf 'cpus=%s mem_MiB=%s FlashProve=%s\n' "$SLURM_CPUS_PER_TASK" "$SLURM_MEM_PER_NODE" "$FLASHPROVE_COMMIT"
make bootstrap upstream
if ! command -v clang++ >/dev/null; then
    # The Lucid Ubuntu image has LLVM 18's shared libraries but lacks the compiler driver.
    mkdir build/clang-18
    cd build/clang-18
    apt-get download clang-18 libclang-common-18-dev
    for package in *.deb; do dpkg-deb -x "$package" .; done
    ln -s clang-18 usr/bin/clang
    ln -s clang++-18 usr/bin/clang++
    export PATH="$PWD/usr/bin:$PATH"
    cd "$run"
fi
clang++ --version | head -1
make lean-baseline oracle verifier > "$out/baseline-build.log" 2>&1
make benchmark benchmark-lean | tee "$out/baselines.log"

# Lake writes into its source tree. Give it a private unpack of the pinned git object.
reference=$PWD/.upstream/FlashProve
tree=$PWD/build/theorem
git -C "$reference" fetch --refetch --depth=1 --no-filter origin "$FLASHPROVE_COMMIT"
mkdir "$tree"
git -C "$reference" archive "$FLASHPROVE_COMMIT" | tar -xf - -C "$tree"
cd "$tree/lean"
export PATH="$run/.toolchain/lean-4.29.1-linux/bin:$PATH"
lean --version
python3 -B scripts/check.py --only tree > "$out/tree.log" 2>&1
lake exe cache get > "$out/cache.log" 2>&1
lake build Johnson.PVR.ProgramGuard > "$out/guard.log" 2>&1
# The upstream CLI links the helper and compiles its parser per call. Build the reusable
# native objects before timing so the first measurement has the same scope as the others.
targets=()
while IFS= read -r module; do
    [[ -z $module || $module == '#'* ]] || targets+=("+$module:c.o.export")
done < "$tree/tools/lean-verify/native-modules.txt"
lake build "${targets[@]}" > "$out/native-objects.log" 2>&1
cd "$tree"
fixture=examples/full-size
(cd "$fixture" && sha256sum --quiet -c SHA256SUMS)
for sample in 1 2 3; do
    /usr/bin/time -f 'wall=%e seconds peak=%M KiB exit=%x' -o "$out/theorem-$sample.time" \
        tools/lean-verify/lean_verify.sh "$fixture/config" "$fixture/ivk" "$fixture/example.req" \
        "$fixture/example.y" "$fixture/example.proof" "$fixture/ID.txt" \
        > "$out/theorem-$sample.stdout" 2> "$out/theorem-$sample.stderr"
    cmp "$out/theorem-$sample.stdout" <(printf '%s\n' 'VERDICT: ACCEPT (exact match)')
    cat "$out/theorem-$sample.time" "$out/theorem-$sample.stdout"
done
