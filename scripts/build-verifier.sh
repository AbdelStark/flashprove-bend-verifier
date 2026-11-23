#!/bin/sh
# Stage immutable git objects. The build never patches the oracle's checkout.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
. ./upstream.lock
export LC_ALL=C BEND_NO_TELEMETRY=1
mkdir -p build
work=$(mktemp -d "$root/build/bend.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
native="$root/src/native"
up="$root/.upstream/FlashProve"
git -C "$up" archive --output="$work/source.tar" "$FLASHPROVE_COMMIT" verifier/src blocks docs/format/format-vectors.txt \
    prover/attn/plan_rounds.h prover/head/plan_rounds.h prover/prover/plan_rounds.h prover/hiding/token_plan.h
cd "$work"
tar -xf source.tar
for component in kernels chain sumcheck; do
    patch -s -p1 < "$native/$component.patch"
done
cp "$root/src/hashlib.bend" "$root/src/goldilocks.bend" "$root/src/extension.bend" "$root/src/merkle.bend" \
   "$root/src/chain.bend" "$root/src/sumcheck.bend" .
cp "$native/entry.bend.in" entry.bend
"$root/.toolchain/bend/bin/bend" entry.bend -o entry.c
# Fingerprint the pinned upstream object plus every input to the native port.
digest=$(python3 - "$FLASHPROVE_COMMIT" "$root/toolchain.lock" "$root/scripts/build-verifier.sh" \
    "$native"/*.h "$native/bridge.c" "$native"/*.patch "$native"/*.inc *.bend <<'PY'
import hashlib, pathlib, sys
digest = hashlib.sha256(sys.argv[1].encode())
for path in sys.argv[2:]:
    digest.update(hashlib.sha256(pathlib.Path(path).read_bytes()).digest())
print(digest.hexdigest())
PY
)
set -- -O2 -fstack-protector-strong -ftrivial-auto-var-init=zero -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fPIE
clang "$@" -std=gnu11 -I. -c "$native/bridge.c" -o bridge.o
case $(uname -s) in
  Darwin) set -- "$@" -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE -Wl,-dead_strip ;;
  Linux) set -- "$@" -D_GLIBCXX_ASSERTIONS -fstack-clash-protection -pie -Wl,-z,relro,-z,now,-z,noexecstack ;;
  *) echo 'Supported hosts are Linux and macOS' >&2; exit 1 ;;
esac
# Exercise the emitted C ABI before installing the binary.
for suite in field/tests/field_test chain/tests/border_test chain/tests/format_vectors_test; do
    clang++ "$@" -std=c++17 -pthread -Iblocks -DBLK_FIELD=2 -include "$native/bridge.h" \
        "blocks/$suite.cpp" bridge.o -lm -o kernel_test
    ./kernel_test docs/format/format-vectors.txt
done
clang++ "$@" -std=c++17 -pthread -Wall -Wextra -Wuninitialized -Werror=unused-result \
    -Wno-misleading-indentation -include "$native/bridge.h" -Iverifier/src -Iblocks -Iprover \
    -DBLK_FIELD=2 -DBLK_COUNT_HASH_CALLS=1 -DSERVING_BUILD=1 -DDIGEST_WORDS=8 "-DVF_SOURCE_DIGEST=\"$digest\"" \
    verifier/src/cp_verify.cpp bridge.o -lm -o bend_verify
printf '%s\n' "$digest" > bend_verify.digest
mv bend_verify.digest "$root/build/bend_verify.digest"
mv bend_verify "$root/build/bend_verify"
echo "Built build/bend_verify (build=$digest)"
