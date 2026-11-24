#!/bin/sh
# Reproduces the feasibility measurements quoted in docs/research/bend2-assessment.md.
# Needs: `make bootstrap upstream`, clang, python3. Builds into a temp dir; prints a report.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
bend="$root/.toolchain/bend/bin/bend"
proof="$root/.upstream/FlashProve/examples/full-size/example.proof"
export BEND_NO_TELEMETRY=1
w=$(mktemp -d "${TMPDIR:-/tmp}/spikes.XXXXXX"); trap 'rm -rf "$w"' EXIT
t() { /usr/bin/time -p "$@" 2>&1 | awk '/^real/{r=$2} /^user/{u=$2} !/^(real|user|sys)/{print} END{printf "  real %ss user %ss\n", r, u}'; }

echo "== BLAKE2b compression, 2,000,000 chained calls =="
python3 "$here/blake2b/gen.py" 2000000 > "$w/chain.bend" && "$bend" "$w/chain.bend" -o "$w/chain"
clang -O2 -o "$w/b2b_ref" "$here/blake2b/ref.c"
echo "bend (1 thread):"; t "$w/chain" +RTS --threads 1
echo "C, native u64:"; t "$w/b2b_ref" 2000000

echo "== BLAKE2b Merkle-shaped fork-join tree, 2^21 leaves (4,194,303 compressions) =="
python3 "$here/blake2b/gen.py" tree 21 > "$w/tree.bend" && "$bend" "$w/tree.bend" -o "$w/tree"
for n in 1 2 4 8 16; do echo "bend ($n threads):"; t "$w/tree" +RTS --threads $n | cut -c1-60; done

echo "== Goldilocks multiplication, 20,000,000 chained calls =="
cp "$root/src/goldilocks.bend" "$w/goldilocks.bend"
sed 's/NNN/20000000/' "$here/goldilocks/mul.bend.in" > "$w/mul.bend" && "$bend" "$w/mul.bend" -o "$w/mul"
clang -O2 -o "$w/gl_ref" "$here/goldilocks/ref.c"
echo "bend (1 thread):"; t "$w/mul" +RTS --threads 1
echo "C, native u64/u128:"; t "$w/gl_ref" 20000000
echo "python reference:"; python3 "$here/goldilocks/ref.py" 20000000

echo "== Cubic-extension multiplication, 20,000,000 chained calls =="
cp "$root/src/extension.bend" "$w/extension.bend"
sed 's/NNN/20000000/' "$here/extension/mul.bend.in" > "$w/emul.bend" && "$bend" "$w/emul.bend" -o "$w/emul"
clang -O2 -o "$w/e3_ref" "$here/extension/ref.c"
echo "bend (1 thread):"
/usr/bin/time -p "$w/emul" +RTS --threads 1 > "$w/e3-bend.out"
cat "$w/e3-bend.out"
echo "C, native u64/u128:"
/usr/bin/time -p "$w/e3_ref" 20000000 > "$w/e3-c.out"
cat "$w/e3-c.out"
cmp "$w/e3-bend.out" "$w/e3-c.out"

echo "== Read and parse the full-size proof (18.8 MB) as 64-bit words =="
"$bend" "$here/parse/parse.bend" -o "$w/parse"
echo "bend (1 thread):"; t "$w/parse" "$proof" +RTS --threads 1
echo "python reference:"; python3 "$here/parse/ref.py" "$proof"

echo "== LIN own-table layout, 81,920 terms with 12 to 23 input coordinates =="
"$bend" "$here/lin/layout.bend" -o "$w/layout"
echo "bend (1 thread), expected 2048000 output coordinates:"; t "$w/layout" +RTS --threads 1
