#!/usr/bin/env bash
# Build shared libev into lib/<os>-<arch>/ (Unix only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBEV_VERSION="${LIBEV_VERSION:-4.33}"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) echo "libev is Unix-only" >&2; exit 1 ;;
esac
case "$uname_m" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "unsupported arch: $uname_m" >&2; exit 1 ;;
esac

OUT="${DEST_DIR:-$ROOT/lib/${os}-${arch}}"
BUILD="$ROOT/build/libev-${LIBEV_VERSION}-${os}-${arch}"
SRC_TGZ="$ROOT/build/libev-${LIBEV_VERSION}.tar.gz"
SRC_URL="http://dist.schmorp.de/libev/Attic/libev-${LIBEV_VERSION}.tar.gz"
# mirror
SRC_URL2="https://github.com/enki/libev/archive/refs/tags/${LIBEV_VERSION}.tar.gz"

mkdir -p "$ROOT/build" "$OUT"
if [[ ! -f "$SRC_TGZ" ]]; then
  echo "==> download libev ${LIBEV_VERSION}"
  curl -fsSL "$SRC_URL" -o "$SRC_TGZ" || curl -fsSL "$SRC_URL2" -o "$SRC_TGZ"
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"
tar -xzf "$SRC_TGZ" -C "$BUILD" --strip-components=1

echo "==> configure/build libev ${LIBEV_VERSION} -> $OUT"
cd "$BUILD"
if [[ -x ./configure ]]; then
  ./configure --prefix="$BUILD/prefix" --enable-shared --disable-static
  make -j"$JOBS"
  make install
else
  echo "no configure; install libev via apt/brew for local-dev" >&2
  exit 1
fi

mkdir -p "$OUT"
shopt -s nullglob
for f in "$BUILD/prefix/lib"/libev.so* "$BUILD/prefix/lib"/libev.*.dylib "$BUILD/prefix/lib"/libev.dylib; do
  cp -a "$f" "$OUT/"
done
export EVENT_PROTOCOL_EV_INCLUDE="$BUILD/prefix/include"
echo "EVENT_PROTOCOL_EV_INCLUDE=$EVENT_PROTOCOL_EV_INCLUDE"
ls -la "$OUT"
