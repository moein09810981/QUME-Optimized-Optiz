#!/usr/bin/env bash
# Experimental native Android/ARM64-host QEMU TCG build for Termux.
# Run from the QEMU source root: bash scripts/build-android-arm64-tcg.sh
# Optional environment variables:
#   BUILD_DIR=... JOBS=2 LEAN_DEVICES=1 EXTRA_CFLAGS="-O3"
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-android-arm64-tcg}"
JOBS="${JOBS:-2}"
LEAN_DEVICES="${LEAN_DEVICES:-0}"
EXTRA_CFLAGS="${EXTRA_CFLAGS:--O3}"

for tool in clang meson ninja pkg-config python; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Missing required tool: %s\n' "$tool" >&2
        printf 'Install the QEMU build toolchain and dependencies in Termux first.\n' >&2
        exit 2
    }
done

if ! pkg-config --exists glib-2.0 pixman-1; then
    printf 'Missing development dependencies: glib-2.0 and/or pixman-1.\n' >&2
    printf 'Install their Termux development packages, then rerun this script.\n' >&2
    exit 2
fi

if [[ "$LEAN_DEVICES" != "0" && "$LEAN_DEVICES" != "1" ]]; then
    printf 'LEAN_DEVICES must be 0 or 1.\n' >&2
    exit 2
fi

printf 'Source: %s\nBuild:  %s\nJobs:   %s\nLean devices: %s\nCFLAGS: %s\n' \
    "$ROOT" "$BUILD_DIR" "$JOBS" "$LEAN_DEVICES" "$EXTRA_CFLAGS"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

CONFIGURE_ARGS=(
    --target-list=x86_64-softmmu
    --enable-tcg
    -Dbuildtype=release
    -Db_lto=true
    --disable-docs
    --disable-werror
    --extra-cflags="$EXTRA_CFLAGS"
)

# This removes QEMU's default device selection. Use only as a separate
# experiment: a Windows guest may need devices that are no longer included.
if [[ "$LEAN_DEVICES" == "1" ]]; then
    CONFIGURE_ARGS+=(-Ddefault_devices=false)
fi

"$ROOT/configure" "${CONFIGURE_ARGS[@]}"

ninja -j "$JOBS"

printf '\nBuild completed. Verify the host binary before attempting a guest boot:\n'
./qemu-system-x86_64 --version
./qemu-system-x86_64 -accel help
