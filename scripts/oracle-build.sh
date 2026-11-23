#!/bin/sh
# Build the byte-for-byte upstream verifier from the object named in upstream.lock.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$root/upstream.lock"
up="$root/.upstream/FlashProve"
out="$root/build"
mkdir -p "$out"
work=$(mktemp -d "$out/oracle.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
git -C "$up" archive --output="$work/src.tar" "$FLASHPROVE_COMMIT" verifier blocks \
    prover/attn/plan_rounds.h prover/head/plan_rounds.h prover/prover/plan_rounds.h prover/hiding/token_plan.h
tar -xf "$work/src.tar" -C "$work"
cd "$work"
case $(uname -s) in
    Linux)
        bash verifier/build.sh
        mv bin/cp_verify "$out/cp_verify"
        ;;
    Darwin)
        # Same source digest and preprocessor settings as verifier/build.sh. Apple uses libc++.
        cd verifier/src
        export LC_ALL=C
        shasum -a 256 * ../../prover/*/plan_rounds.h ../../prover/hiding/token_plan.h > "$work/sums"
        (cd ../../blocks && find . -type f -name '*.h' ! -path '*/tests/*' | sort | xargs shasum -a 256) >> "$work/sums"
        source_digest=$(shasum -a 256 "$work/sums" | cut -c1-64)
        /usr/bin/clang++ -O2 -std=c++17 -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE \
            -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fstack-protector-strong -ftrivial-auto-var-init=zero \
            -Wall -Wextra -Wuninitialized -Werror=unused-result -Wno-misleading-indentation -pthread \
            -I. -I../../blocks -I../../prover -DBLK_FIELD=2 -DBLK_COUNT_HASH_CALLS=1 -DSERVING_BUILD=1 \
            -DDIGEST_WORDS=8 "-DVF_SOURCE_DIGEST=\"$source_digest\"" cp_verify.cpp -o "$work/cp_verify"
        mv "$work/cp_verify" "$out/cp_verify"
        ;;
    *) echo "Unsupported reference build host: $(uname -s)" >&2; exit 1 ;;
esac
echo "Built $out/cp_verify"
