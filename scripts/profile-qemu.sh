#!/usr/bin/env bash
# Profile a running QEMU process on Android/Linux to find where TCG time goes.
# Do this BEFORE touching helpers or the load/store fast path.
#
#   scripts/profile-qemu.sh <pid-or-name> [seconds]   (default 30s)
#   scripts/profile-qemu.sh qemu-system-aarch64 60
#
# Uses simpleperf (Android) if present, otherwise perf. Output goes to
# ./profile-out/: perf.data and a text report of the hottest symbols.
# Look for: helper_*, tb_lookup / cpu_exec_loop, tlb_fill, do_ld*/do_st*,
# and time spent in generated code (shown as unknown / JIT region).
#
# Note: simpleperf can only attach to processes you are allowed to profile.
# On a non-rooted phone this may only work from `adb shell` or for a
# debuggable build; if it fails, try running QEMU under `simpleperf record`
# directly instead of attaching.
set -Eeuo pipefail

TARGET="${1:-}"
SECS="${2:-30}"
OUT="${OUT:-profile-out}"
[[ -n "$TARGET" ]] || { echo "usage: $0 <pid|process-name> [seconds]" >&2; exit 2; }

if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    PID="$TARGET"
else
    PID="$(pgrep -n -f "$TARGET" || true)"
fi
[[ -n "${PID:-}" ]] || { echo "process not found: $TARGET" >&2; exit 1; }

mkdir -p "$OUT"
echo "Profiling PID $PID for ${SECS}s -> $OUT/"

if command -v simpleperf >/dev/null 2>&1; then
    simpleperf record -p "$PID" -g --duration "$SECS" -o "$OUT/perf.data"
    simpleperf report -i "$OUT/perf.data" --sort comm,dso,symbol \
        > "$OUT/report.txt" 2>&1 || true
    simpleperf stat -p "$PID" --duration 5 \
        -e cpu-cycles,instructions,cache-misses,branch-misses \
        > "$OUT/stat.txt" 2>&1 || true
elif command -v perf >/dev/null 2>&1; then
    perf record -p "$PID" -g -o "$OUT/perf.data" -- sleep "$SECS"
    perf report -i "$OUT/perf.data" --stdio --sort comm,dso,symbol \
        > "$OUT/report.txt" 2>&1 || true
    perf stat -p "$PID" -e cycles,instructions,cache-misses,branch-misses \
        -- sleep 5 > "$OUT/stat.txt" 2>&1 || true
else
    echo "Neither simpleperf nor perf found." >&2
    exit 1
fi

echo "Top of report:"
head -n 40 "$OUT/report.txt" || true
echo "Full report: $OUT/report.txt   counters: $OUT/stat.txt"
