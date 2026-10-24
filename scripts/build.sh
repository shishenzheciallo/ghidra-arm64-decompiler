#!/bin/bash
# Build the Ghidra 12.1.4 native decompiler for linux/arm64.
# Usage: ./scripts/build.sh [source-dir-or-tarball]   (default: ./ghidra-src)
set -euo pipefail

TAG=Ghidra_12.1.4_build
SRC="${1:-./ghidra-src}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/dist"
CXX_BIN="${CXX_BIN:-clang++-18}"

command -v "$CXX_BIN" >/dev/null || { echo "need $CXX_BIN (clang 18+ recommended)"; exit 1; }
for t in make bison flex; do command -v "$t" >/dev/null || { echo "need $t"; exit 1; }; done

# 1. fetch sources if given a nonexistent path
if [ ! -d "$SRC" ]; then
  mkdir -p "$SRC"
  echo "downloading $TAG sources..."
  curl -L --retry 5 -C - -o "$SRC.tgz" \
    "https://github.com/NationalSecurityAgency/ghidra/archive/refs/tags/${TAG}.tar.gz"
  tar xzf "$SRC.tgz" -C "$SRC" --strip-components=1
fi

CPP="$SRC/Ghidra/Features/Decompiler/src/decompile/cpp"
[ -d "$CPP" ] || { echo "not a Ghidra source tree: $SRC"; exit 1; }
cd "$CPP"

# 2. deep template recursion needs more than the default 8 MB stack
ulimit -s unlimited 2>/dev/null || ulimit -s 65536

# 3. the Makefile has no aarch64 branch; skip its one-shot depend rule
mkdir -p com_opt com_dbg ghi_opt
: > com_opt/depend
: > com_dbg/depend

# 4. compile one file at a time (a single -MM over all .cc files ICEs)
for f in $(make -s ARCH=aarch64 ARCH_TYPE= OSDIR=linux_arm_64 \
                --eval='p:;@echo $(GHIDRA_NAMES)' p); do
  [ -s "ghi_opt/$f.o" ] && continue
  "$CXX_BIN" -std=c++11 -c -O2 -Wno-sign-compare "$f.cc" -o "ghi_opt/$f.o" \
    || { echo "retry $f"; "$CXX_BIN" -std=c++11 -c -O2 -Wno-sign-compare "$f.cc" -o "ghi_opt/$f.o"; }
done

# 5. link
make ARCH=aarch64 ARCH_TYPE= OSDIR=linux_arm_64 CXX="$CXX_BIN -std=c++11" ghidra_opt

mkdir -p "$OUT"
cp ghidra_opt "$OUT/decompile"
chmod +x "$OUT/decompile"
echo "built: $OUT/decompile"
file "$OUT/decompile"
