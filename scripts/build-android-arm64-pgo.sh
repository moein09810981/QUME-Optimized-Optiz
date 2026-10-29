#!/usr/bin/env bash
# Experimental Clang instrumentation-PGO helper for Android/ARM64-host QEMU.
# This script builds an instrumented or profile-use binary; it does not run a
# guest workload or claim a performance improvement.
#
# Generate build:
#   PGO_MODE=generate bash scripts/build-android-arm64-pgo.sh
# Then run the generated QEMU binary with a representative guest workload:
#   LLVM_PROFILE_FILE="$PWD/pgo-data/qemu-%p.profraw" ./qemu-system-x86_64 ...
# Merge profiles:
#   llvm-profdata merge -output=pgo-data/qemu.profdata pgo-data/*.profraw
# Profile-use build:
#   PGO_MODE=use PGO_PROFILE="$PWD/pgo-data/qemu.profdata" \
#     bash scripts/build-android-arm64-pgo.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PGO_MODE="${PGO_MODE:-generate}"
PGO_PROFILE="${PGO_PROFILE:-$ROOT/pgo-data/qemu.profdata}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-android-arm64-pgo-$PGO_MODE}"
JOBS="${JOBS:-2}"
EXTRA_CFLAGS="${EXTRA_CFLAGS:--O3}"

for tool in clang meson ninja pkg-config python; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Missing required tool: %s\n' "$tool" >&2
        exit 2
    }
done

if ! pkg-config --exists glib-2.0 pixman-1; then
    printf 'Missing development dependencies: glib-2.0 and/or pixman-1.\n' >&2
    exit 2
fi

case "$PGO_MODE" in
    generate)
        PGO_CFLAGS="-fprofile-instr-generate"
        PGO_LDFLAGS="-fprofile-instr-generate"
        ;;
    use)
        command -v llvm-profdata >/dev/null 2>&1 || {
            printf 'Missing llvm-profdata; install a matching LLVM/Clang toolchain.\n' >&2
            exit 2
        }
        [[ -s "$PGO_PROFILE" ]] || {
            printf 'Profile not found or empty: %s\n' "$PGO_PROFILE" >&2
            printf 'Run the generate build, collect a representative workload, then merge .profraw files.\n' >&2
            exit 2
        }
        PGO_CFLAGS="-fprofile-instr-use=$PGO_PROFILE"
        PGO_LDFLAGS="-fprofile-instr-use=$PGO_PROFILE"
        ;;
    *)
        printf 'PGO_MODE must be generate or use.\n' >&2
        exit 2
        ;;
esac

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

"$ROOT/configure" \
    --target-list=x86_64-softmmu \
    --enable-tcg \
    -Dbuildtype=release \
    -Db_lto=true \
    --disable-docs \
    --disable-werror \
    --extra-cflags="$EXTRA_CFLAGS $PGO_CFLAGS" \
    --extra-ldflags="$PGO_LDFLAGS"

ninja -j "$JOBS"

printf '\nPGO %s build completed. This is not a performance result.\n' "$PGO_MODE"
./qemu-system-x86_64 --version
