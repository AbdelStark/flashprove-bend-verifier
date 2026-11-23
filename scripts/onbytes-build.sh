#!/usr/bin/env bash
# Optional native Lean baseline; compile only the imports of the pinned OnBytes.Main.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
. "$root/upstream.lock"
up="$root/.upstream/FlashProve"
version=4.29.1
requested=$(git -C "$up" show "$FLASHPROVE_COMMIT:lean/lean-toolchain")
[[ $requested == "leanprover/lean4:v$version" ]] || { echo "unexpected upstream Lean pin: $requested" >&2; exit 1; }
# SHA256 digests published on the leanprover/lean4 v4.29.1 release assets.
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=darwin_aarch64; sum=73bccb392ca7d8ab3d62a1e328bb7d057815f088dbdbfb6574f194ae505797af ;;
  Darwin-x86_64) platform=darwin; sum=3585ab34d20c53cf915169aa5c0d2efbd9993a78b9dc08516641510eef08fab0 ;;
  Linux-aarch64) platform=linux_aarch64; sum=1ccdfb7f924901f4b73a4b4eb169e5b3dc74f6836521b47e733ea25f2abfc0dc ;;
  Linux-x86_64) platform=linux; sum=bf062d29556d655685fb287563c249ad6a8fde34352c18b5e32568a595c1aec1 ;;
  *) echo "unsupported Lean release platform" >&2; exit 2 ;;
esac
release="lean-$version-$platform"
install="$root/.toolchain/$release"
mkdir -p "$root/.toolchain" "$root/build"
work=$(mktemp -d "$root/build/onbytes.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
if [[ ! -x "$install/bin/lake" ]]; then
  archive="$work/$release.tar.zst"
  curl --proto '=https' --tlsv1.2 -fLsS --retry 2 -o "$archive" \
    "https://github.com/leanprover/lean4/releases/download/v$version/$release.tar.zst"
  if command -v sha256sum >/dev/null; then
    printf '%s  %s\n' "$sum" "$archive" | sha256sum -c
  else
    printf '%s  %s\n' "$sum" "$archive" | shasum -a 256 -c
  fi
  if command -v zstd >/dev/null; then
    zstd -dc "$archive" | tar -xf - -C "$work"
  elif python3 -c 'from compression import zstd' 2>/dev/null; then
    python3 - "$archive" <<'PY' | tar -xf - -C "$work"
from compression import zstd
import shutil, sys
with zstd.open(sys.argv[1], "rb") as source:
    shutil.copyfileobj(source, sys.stdout.buffer)
PY
  else
    echo 'Extracting the Lean archive requires zstd or Python 3.14+ with compression.zstd' >&2
    exit 2
  fi
  python3 - "$work/$release" "$install" <<'PY'
import errno, os, sys
try:
    os.rename(sys.argv[1], sys.argv[2])
except OSError as exc:
    if exc.errno not in (errno.EEXIST, errno.ENOTEMPTY) or not os.access(sys.argv[2] + "/bin/lake", os.X_OK):
        raise
PY
fi

git -C "$up" archive "$FLASHPROVE_COMMIT:lean" Fmt OnBytes Run | tar -xf - -C "$work"
cat > "$work/lakefile.toml" <<'LAKE'
name = "onbytesBaseline"
defaultTargets = ["verify-on-bytes"]

[leanOptions]
pp.unicode.fun = true
relaxedAutoImplicit = false
autoImplicit = false

[[lean_lib]]
name = "Library"
globs = ["Fmt.+", "OnBytes.+", "Run.+"]

[[lean_exe]]
name = "verify-on-bytes"
root = "OnBytes.Main"
LAKE
cd "$work"
export PATH="$install/bin:$PATH" LEAN_SYSROOT="$install" LAKE_NO_CACHE=true
toolchain=$("$install/bin/lean" --version)
case "$toolchain" in
  "Lean (version $version,"*"commit f72c35b3f637c8c6571d353742168ab66cc22c00, Release)") ;;
  *) echo "unexpected cached compiler: $toolchain" >&2; exit 1 ;;
esac
echo "$toolchain"
"$install/bin/lake" build verify-on-bytes
mv .lake/build/bin/verify-on-bytes "$root/build/verify-on-bytes"
