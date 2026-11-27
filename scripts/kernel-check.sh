#!/usr/bin/env bash
# Recheck PROOF.bend and the standalone verifier with Bend's independent BendTT kernel.
# The kernel builds itself once with Lean v4.34.0, installed here from the official release.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
version=4.34.0
# SHA256 digests published on the leanprover/lean4 v4.34.0 release assets.
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=darwin_aarch64; sum=69f263fa6e21bbc2466bbfb1affcd92479ee2714c883a07de548e099a5922932 ;;
  Linux-x86_64) platform=linux; sum=caaa98356098c85dc0fcbbd28e1ec66f39eb6551829972b752ff20e1286b646b ;;
  *) echo "kernel-check: no pinned Lean v$version archive for this platform" >&2; exit 2 ;;
esac
release="lean-$version-$platform"
install="$root/.toolchain/$release"
if [[ ! -x "$install/bin/lean" ]]; then
  mkdir -p "$root/.toolchain" "$root/build"
  work=$(mktemp -d "$root/build/lean.XXXXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  archive="$work/$release.tar.zst"
  curl --proto '=https' --tlsv1.2 -fLsS --retry 2 -o "$archive" \
    "https://github.com/leanprover/lean4/releases/download/v$version/$release.tar.zst"
  if command -v sha256sum >/dev/null; then
    printf '%s  %s\n' "$sum" "$archive" | sha256sum -c --quiet
  else
    printf '%s  %s\n' "$sum" "$archive" | shasum -a 256 -c --quiet
  fi
  zstd -dc "$archive" | tar -xf - -C "$work"
  mv "$work/$release" "$install"
fi
export PATH="$install/bin:$PATH"
cd "$root"
for source in PROOF.bend src/standalone.bend; do
  printf '%s: ' "$source"
  .toolchain/bend/bin/bend "$source" --verdict | tail -1
done
