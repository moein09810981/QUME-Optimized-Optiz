#!/usr/bin/env bash
# Optimized build of qemu-system-aarch64 (TCG-focused), meant for Termux/Android
# or any aarch64 Linux host. Run from the repository root.
#
#   scripts/build-optimized.sh generate   # 1) build instrumented binary
#   ...boot your real guest, use it for a few minutes, shut it down cleanly...
#   scripts/build-optimized.sh use        # 2) rebuild using the profile (PGO)
#   scripts/build-optimized.sh plain      # LTO + -O3 only, no PGO
#
# Notes:
#  - Build natively on the phone so -mcpu=native matches the real CPU.
#  - Keep the profile data directory between the two steps.
set -euo pipefail

MODE="${1:-plain}"
JOBS="${JOBS:-$(nproc)}"
PGO_DIR="${PGO_DIR:-$PWD/pgo-data}"
BUILD_DIR="build-opt-$MODE"

CFLAGS_COMMON="-O3 -fno-plt -fomit-frame-pointer -mcpu=native"

case "$MODE" in
  generate) EXTRA="$CFLAGS_COMMON -fprofile-generate -fprofile-dir=$PGO_DIR"
            LDEXTRA="-fprofile-generate" ;;
  use)      EXTRA="$CFLAGS_COMMON -fprofile-use -fprofile-dir=$PGO_DIR -fprofile-correction -Wno-missing-profile"
            LDEXTRA="-fprofile-use" ;;
  plain)    EXTRA="$CFLAGS_COMMON"; LDEXTRA="" ;;
  *) echo "usage: $0 {generate|use|plain}" >&2; exit 1 ;;
esac

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

../configure \
  --target-list=aarch64-softmmu \
  --enable-lto \
  --disable-docs \
  --disable-werror \
  --disable-user \
  --disable-plugins \
  --disable-debug-info \
  --enable-vnc \
  --extra-cflags="$EXTRA" \
  --extra-ldflags="$LDEXTRA"

make -j"$JOBS"
echo "Built: $PWD/qemu-system-aarch64"
