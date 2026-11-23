#!/bin/sh
set -eu
export BEND_NO_TELEMETRY=1
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p build
work=$(mktemp -d "$root/build/cli.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
.toolchain/bend/bin/bend src/verify.bend -o "$work/verify_generated.c"
clang -std=c11 -O3 -fstack-protector-strong -I"$work" src/native/verify_main.c -lpthread -lm -o "$work/verify"
mv "$work/verify" build/verify
