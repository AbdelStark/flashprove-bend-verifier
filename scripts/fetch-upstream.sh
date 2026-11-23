#!/bin/sh
# Fetches the pinned FlashProve revision into .upstream/FlashProve (read-only reference:
# format spec, C++ verifier, stored example proofs). Of the 450 MB lean/ tree only the
# functional reference (verify-on-bytes: OnBytes/, Fmt/, Run/) is fetched, unless
# --with-lean is given. Idempotent. Usage: scripts/fetch-upstream.sh [--with-lean]
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$root/upstream.lock"
with_lean=0
[ "${1:-}" = "--with-lean" ] && with_lean=1

dir="$root/.upstream/FlashProve"
if [ ! -d "$dir/.git" ]; then
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$FLASHPROVE_REPO"
  git -C "$dir" config extensions.partialClone origin
fi
if [ "$with_lean" = 1 ]; then
  git -C "$dir" sparse-checkout disable 2>/dev/null || true
else
  git -C "$dir" sparse-checkout set --no-cone '/*' '!/lean/*' \
    '/lean/OnBytes/' '/lean/Fmt/' '/lean/Run/' '/lean/README.md' '/lean/THEOREM.md' \
    '/lean/lean-toolchain' '/lean/lakefile.toml' '/lean/lake-manifest.json'
fi
if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$FLASHPROVE_COMMIT" ]; then
  git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$FLASHPROVE_COMMIT"
fi
git -C "$dir" -c advice.detachedHead=false checkout -q "$FLASHPROVE_COMMIT"

# Tests execute the pinned mutation harness and read expectations from its README files.
git -C "$dir" diff --exit-code --stat "$FLASHPROVE_COMMIT" -- examples

# Integrity: every stored example ships its own SHA256SUMS; verify them all.
for sums in "$dir"/examples/*/SHA256SUMS; do
  ( cd "$(dirname "$sums")" && { command -v sha256sum >/dev/null 2>&1 && sha256sum -c --quiet SHA256SUMS || shasum -a 256 -c --quiet SHA256SUMS; } )
done
echo "fetch-upstream: FlashProve $FLASHPROVE_VERSION at $FLASHPROVE_COMMIT in $dir (examples verified)"
