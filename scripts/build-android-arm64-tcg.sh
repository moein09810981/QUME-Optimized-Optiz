#!/usr/bin/env bash
# Experimental native Android/ARM64 TCG build profile for Termux.
# Run from the QEMU source root: bash scripts/build-android-arm64-tcg.sh
# Override JOBS and EXTRA_CFLAGS to fit the device and compiler.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-android-arm64-tcg}"
JOBS="${JOBS:-2}"
EXTRA_CFLAGS="${EXTRA_CFLAGS:--O3}"

for tool in clang meson ninja pkg-config python; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Missing required tool: %s\n' "$tool" >&2
        printf 'In Termux, install the QEMU build toolchain and dependencies first.\n' >&2
        exit 2
    }
done

if ! pkg-config --exists glib-2.0 pixman-1; then
    printf 'Missing development dependencies: glib-2.0 and/or pixman-1.\n' >&2
    printf 'Install their Termux development packages, then rerun this script.\n' >&2
    exit 2
fi

printf 'Source: %s\nBuild:  %s\nJobs:   %s\nCFLAGS: %s\n' \
    "$ROOT" "$BUILD_DIR" "$JOBS" "$EXTRA_CFLAGS"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# TCG is the relevant accelerator: the Android ARM64 host cannot run an
# x86-64 guest with native ARM KVM acceleration.
"$ROOT/configure" \
    --target-list=x86_64-softmmu \
    --enable-tcg \
    -Dbuildtype=release \
    -Db_lto=true \
    --disable-docs \
    --disable-werror \
    --extra-cflags="$EXTRA_CFLAGS"

ninja -j "$JOBS"

printf '\nBuild completed. Verify the host binary before attempting a guest boot:\n'
./qemu-system-x86_64 --version
./qemu-system-x86_64 -accel help
