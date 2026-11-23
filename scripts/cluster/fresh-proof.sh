#!/usr/bin/env bash
#SBATCH --job-name=flashprove-fresh
#SBATCH --partition=main
#SBATCH --constraint=h100
#SBATCH --gpus=1
#SBATCH --cpus-per-task=12
#SBATCH --mem=96G
#SBATCH --time=02:00:00
# Submit from the verifier checkout after make standalone upstream on Linux.
# BEND_BUILD_DIR defaults to build/, containing verify-bend, its digest, plans/ and tables/.
set -euo pipefail
umask 077
root=${SLURM_SUBMIT_DIR:?submit through Slurm from the checkout}
bundle=$(realpath "${BEND_BUILD_DIR:-$root/build}")
ref=$(realpath "${FLASHPROVE_UPSTREAM:-$root/.upstream/FlashProve}")
test -x "$bundle/verify-bend"
test -s "$bundle/verify-bend.digest"
test -d "$bundle/plans"
test -d "$bundle/tables"
job=$(mktemp -d "${SLURM_TMPDIR:-/tmp}/fp-gpu.XXXXXXXX")
trap 'rm -rf -- "${job:?}"' EXIT
export APPTAINER_CACHEDIR="$job/cache" APPTAINER_TMPDIR="$job"
image='docker://docker.io/library/buildpack-deps@sha256:e7fdb09e2aacd2a32875a44be9caa1c18f3098b88620ac6a4bde84c0732c9f87'
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
apptainer pull --disable-cache "$job/base.sif" "$image"
mkdir "$job/packages" "$job/sdk"
cd "$job/packages"
manifest="$root/scripts/cluster/cuda-13.2-ubuntu2404.sha256"
repo=https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64
awk '{print $2}' "$manifest" | xargs -P4 -I{} curl -fsSL --retry 3 "$repo/{}" -o '{}'
sha256sum --check "$manifest"
while read -r _ package; do dpkg-deb -x "$package" "$job/sdk"; done < "$manifest"
cuda="$job/sdk/usr/local/cuda-13.2"
if [[ ! -e $cuda/lib64 ]]; then ln -s targets/x86_64-linux/lib "$cuda/lib64"; fi
cd "$job"
# nvidia-container-cli assembles the kernel driver's user-space dependencies.
# The container-local loader cache also serves binaries that clear their environment.
mapfile -t visible < <(nvidia-smi --query-gpu=uuid --format=csv,noheader)
if (( ${#visible[@]} == 1 )); then
    export NVIDIA_VISIBLE_DEVICES="${visible[0]}"
else
    assigned="${SLURM_JOB_GPUS:-${SLURM_STEP_GPUS:-${CUDA_VISIBLE_DEVICES:?}}}"
    NVIDIA_VISIBLE_DEVICES=$(nvidia-smi -i "$assigned" --query-gpu=uuid --format=csv,noheader)
    export NVIDIA_VISIBLE_DEVICES
fi
export APPTAINERENV_CUDA_VISIBLE_DEVICES=0
apptainer exec --contain --nvccli \
  --bind "$cuda:/opt/flashprove-cuda:ro" --bind "$job:/node" \
  --bind "$root:/project:ro" --bind "$bundle:/bend:ro" --bind "$ref:/reference:ro" \
  "$job/base.sif" /bin/bash -euc '
    export PATH=/opt/flashprove-cuda/bin:/usr/bin:/bin
    printf "/opt/flashprove-cuda/targets/x86_64-linux/lib\n" > /etc/ld.so.conf.d/00-flashprove.conf
    /sbin/ldconfig -X
    nvcc --version >&2
    python3 -B /project/scripts/fresh-proof.py --scratch /node --upstream /reference --bend /bend/verify-bend --data /bend > /node/result.json
  '
out="$root/build/fresh-proof-${SLURM_JOB_ID:?}.json"
cp "$job/result.json" "$out"
echo "Verified. Public hashes, source identities and closing lines are in $out."
