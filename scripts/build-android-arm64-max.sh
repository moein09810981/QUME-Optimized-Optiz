#!/usr/bin/env bash
# Maximum-optimization native QEMU build for ARM64 Android (Termux).
# Run from the QEMU source root:  bash scripts/build-android-arm64-max.sh <mode>
#
# Modes (typical order for the full pipeline):
#   deps      install Termux build dependencies
#   cpu       show detected CPU cores and the flags that will be used
#   plain     ThinLTO + -O3 + CPU tuning, no PGO (baseline for benchmarks)
#   generate  build an instrumented binary for PGO training
#   merge     merge the raw profiles produced by training into one profile
#   use       final build using the merged profile (PGO + ThinLTO)
#
# PGO workflow:
#   1) generate   2) boot your REAL guest with out/generate/qemu-system-aarch64
#   (boot, use it, run something heavy, then shut the guest down CLEANLY so QEMU
#   exits normally - profiles are written at exit)   3) merge   4) use
#
# Environment variables:
#   TARGET_LIST   default "aarch64-softmmu"  (add x86_64-softmmu if needed)
#   JOBS          default 2 (phones throttle; raise only with cooling)
#   HOST_CPU_FLAGS  override auto-detected flags, e.g. "-march=armv8.2-a -mtune=cortex-a76"
#   LEAN_DEVICES  1 = -Ddefault_devices=false (Linux virtio guests only)
#   PGO_DIR       default <root>/pgo-data
set -Eeuo pipefail

MODE="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_LIST="${TARGET_LIST:-aarch64-softmmu}"
JOBS="${JOBS:-2}"
LEAN_DEVICES="${LEAN_DEVICES:-0}"
PGO_DIR="${PGO_DIR:-$ROOT/pgo-data}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# CPU detection: pick -march from the weakest core, -mtune from the big cores
# (the rarest core type in a big.LITTLE SoC). Everything is overridable.
# ---------------------------------------------------------------------------
detect_cpu_flags() {
    if [[ -n "${HOST_CPU_FLAGS:-}" ]]; then
        printf '%s' "$HOST_CPU_FLAGS"; return
    fi
    [[ -r /proc/cpuinfo ]] || { printf '%s' "-march=armv8-a"; return; }

    local parts
    parts="$(grep -i '^CPU part' /proc/cpuinfo | awk '{print tolower($NF)}' | sort | uniq -c | sort -n)"
    [[ -n "$parts" ]] || { printf '%s' "-march=armv8-a"; return; }

    local big_part
    big_part="$(printf '%s\n' "$parts" | head -n1 | awk '{print $2}')"

    declare -A NAME=(
        [0xd03]=cortex-a53 [0xd05]=cortex-a55 [0xd07]=cortex-a57
        [0xd08]=cortex-a72 [0xd09]=cortex-a73 [0xd0a]=cortex-a75
        [0xd0b]=cortex-a76 [0xd0c]=neoverse-n1 [0xd0d]=cortex-a77
        [0xd41]=cortex-a78 [0xd44]=cortex-x1 [0xd46]=cortex-a510
        [0xd47]=cortex-a710 [0xd48]=cortex-x2 [0xd4d]=cortex-a715
        [0xd4e]=cortex-x3
    )
    # Cores that implement at least Armv8.2-A.
    local V82=" 0xd05 0xd0a 0xd0b 0xd0c 0xd0d 0xd41 0xd44 0xd46 0xd47 0xd48 0xd4d 0xd4e "

    local arch="armv8.2-a" p
    for p in $(printf '%s\n' "$parts" | awk '{print $2}'); do
        [[ "$V82" == *" $p "* ]] || arch="armv8-a"
    done

    local tune="${NAME[$big_part]:-}"
    if [[ -n "$tune" ]]; then
        printf -- '-march=%s -mtune=%s' "$arch" "$tune"
    else
        printf -- '-march=%s' "$arch"
    fi
}

# ---------------------------------------------------------------------------
case "$MODE" in
deps)
    pkg update -y
    pkg install -y clang lld llvm make ninja python pkg-config git \
        glib pixman libslirp zlib libpng libjpeg-turbo flex bison
    pip install --upgrade meson tomli 2>/dev/null || true
    echo "Dependencies installed."
    exit 0
    ;;
cpu)
    echo "Detected flags: $(detect_cpu_flags)"
    grep -i '^CPU part' /proc/cpuinfo 2>/dev/null | sort | uniq -c || true
    exit 0
    ;;
plain|generate|use|merge) ;;
*) die "usage: $0 {deps|cpu|plain|generate|merge|use}" ;;
esac

for tool in clang meson ninja pkg-config python; do
    command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool (run: $0 deps)"
done
pkg-config --exists glib-2.0 pixman-1 || die "missing glib-2.0 / pixman-1 dev packages (run: $0 deps)"
[[ "$LEAN_DEVICES" == "0" || "$LEAN_DEVICES" == "1" ]] || die "LEAN_DEVICES must be 0 or 1"

# ---- merge profiles -------------------------------------------------------
if [[ "$MODE" == "merge" ]]; then
    command -v llvm-profdata >/dev/null 2>&1 || die "llvm-profdata not found (pkg install llvm)"
    shopt -s nullglob
    raw=("$PGO_DIR"/*.profraw)
    ((${#raw[@]})) || die "no .profraw files in $PGO_DIR - did QEMU exit cleanly after training?"
    llvm-profdata merge -output="$PGO_DIR/qemu.profdata" "${raw[@]}"
    echo "Merged ${#raw[@]} raw profiles -> $PGO_DIR/qemu.profdata"
    exit 0
fi

# ---- build modes ----------------------------------------------------------
CPU_FLAGS="$(detect_cpu_flags)"

# -O3 and ARM-friendly codegen. -fno-plt / -fno-semantic-interposition cut
# indirect-call overhead; function/data sections + --gc-sections shrink the
# binary (better icache/iTLB behaviour on small phone caches).
COMMON_CFLAGS="-O3 -fno-plt -fno-semantic-interposition -fomit-frame-pointer \
-ffunction-sections -fdata-sections -fno-math-errno -fno-trapping-math $CPU_FLAGS"
LDFLAGS_EXTRA="-Wl,--gc-sections -Wl,-O2"

if command -v ld.lld >/dev/null 2>&1; then
    LDFLAGS_EXTRA="$LDFLAGS_EXTRA -fuse-ld=lld"
fi

PGO_CFLAGS=""
PGO_LDFLAGS=""
case "$MODE" in
generate)
    mkdir -p "$PGO_DIR"
    PGO_CFLAGS="-fprofile-instr-generate=$PGO_DIR/qemu-%p-%m.profraw"
    PGO_LDFLAGS="-fprofile-instr-generate"
    ;;
use)
    [[ -f "$PGO_DIR/qemu.profdata" ]] || die "missing $PGO_DIR/qemu.profdata (run generate, train, merge first)"
    PGO_CFLAGS="-fprofile-instr-use=$PGO_DIR/qemu.profdata -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date -Wno-backend-plugin"
    PGO_LDFLAGS="-fprofile-instr-use=$PGO_DIR/qemu.profdata"
    ;;
esac

BUILD_DIR="${BUILD_DIR:-$ROOT/build-android-max-$MODE}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

printf 'Mode:    %s\nTargets: %s\nJobs:    %s\nCPU:     %s\nBuild:   %s\n' \
    "$MODE" "$TARGET_LIST" "$JOBS" "$CPU_FLAGS" "$BUILD_DIR"

ARGS=(
    --cc=clang
    --target-list="$TARGET_LIST"
    --enable-tcg
    --enable-slirp
    -Dbuildtype=release
    -Db_lto=true
    -Db_lto_mode=thin
    --disable-docs
    --disable-werror
    --disable-user
    --disable-plugins
    --disable-debug-info
    --disable-qom-cast-debug
    --disable-guest-agent
    --disable-tools
    --extra-cflags="$COMMON_CFLAGS $PGO_CFLAGS"
    --extra-ldflags="$LDFLAGS_EXTRA $PGO_LDFLAGS"
)
[[ "$LEAN_DEVICES" == "1" ]] && ARGS+=(-Ddefault_devices=false)

"$ROOT/configure" "${ARGS[@]}"
ninja -j "$JOBS"

# Collect binaries.
mkdir -p "$OUT_DIR/$MODE"
for t in ${TARGET_LIST//,/ }; do
    bin="qemu-system-${t%-softmmu}"
    if [[ -x "./$bin" ]]; then
        cp -f "./$bin" "$OUT_DIR/$MODE/$bin"
        strip --strip-unneeded "$OUT_DIR/$MODE/$bin" 2>/dev/null || true
        "$OUT_DIR/$MODE/$bin" --version | head -n1
    fi
done
echo "Binaries in: $OUT_DIR/$MODE"
[[ "$MODE" == "generate" ]] && echo "Next: boot your guest with the instrumented binary, shut it down cleanly, then run: $0 merge && $0 use"
exit 0
