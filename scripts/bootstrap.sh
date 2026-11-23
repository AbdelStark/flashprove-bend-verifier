#!/bin/sh
# Installs the pinned Bend toolchain into .toolchain/ (repo-local, nothing global).
# A cached installation must report the pinned version. Usage: scripts/bootstrap.sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$root/toolchain.lock"

case $(uname -s) in
  Darwin) os=darwin;;
  Linux) os=linux;;
  *) echo "bootstrap: unsupported OS $(uname -s) (Bend runs on Linux and macOS)" >&2; exit 1;;
esac
case $(uname -m) in
  arm64|aarch64) arch=arm64;;
  x86_64|amd64) arch=x64;;
  *) echo "bootstrap: unsupported CPU $(uname -m)" >&2; exit 1;;
esac
case $os-$arch in
  darwin-arm64) sum=$BEND_SHA256_DARWIN_ARM64;;
  darwin-x64) sum=$BEND_SHA256_DARWIN_X64;;
  linux-arm64) sum=$BEND_SHA256_LINUX_ARM64;;
  linux-x64) sum=$BEND_SHA256_LINUX_X64;;
esac

dest="$root/.toolchain/bend-$BEND_VERSION"
link="$root/.toolchain/bend"
if [ -x "$dest/bin/bend" ]; then
  version=$("$dest/bin/bend" version)
  if [ "$version" != "bend $BEND_VERSION" ]; then
    echo "bootstrap: $dest reports '$version', expected bend $BEND_VERSION" >&2
    exit 1
  fi
  ln -sfn "bend-$BEND_VERSION" "$link"
  echo "bootstrap: bend $BEND_VERSION already installed at $link"
  exit 0
fi

name="bend-$BEND_VERSION-$os-$arch.tar.gz"
url="https://github.com/bendlang/bend/releases/download/v$BEND_VERSION/$name"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/bend-bootstrap.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
echo "bootstrap: downloading $url"
curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/$name" "$url"
if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$tmp/$name" | cut -d' ' -f1)
else
  got=$(shasum -a 256 "$tmp/$name" | cut -d' ' -f1)
fi
if [ "$got" != "$sum" ]; then
  echo "bootstrap: sha256 mismatch for $name: got $got, toolchain.lock says $sum" >&2
  exit 1
fi
mkdir -p "$tmp/x" "$root/.toolchain"
tar -xzf "$tmp/$name" -C "$tmp/x"
rm -rf "$dest"
mv "$tmp/x/bend" "$dest"
ln -sfn "bend-$BEND_VERSION" "$link"
echo "bootstrap: installed bend $("$link/bin/bend" version) at $link"
