# Android ARM64 TCG optimization plan

## Target and non-goals

Target host: Android 16 on an ARM64 phone (Poco M6 class device).
Target guest: x86-64 Windows using QEMU system emulation.
Initial accelerator: TCG. Ordinary ARM64 KVM does not execute an x86-64 guest natively; do not assume `-accel kvm` is available for this host/guest pairing.

This work is focused on the QEMU source tree itself. It does not modify or integrate the PocketVM Android app.

## Rules for performance work

1. Keep an untouched upstream baseline and record its exact commit.
2. Measure before changing hot paths. Do not assume a compiler flag or speculative optimization is faster.
3. Change one performance factor at a time and preserve a reversible commit.
4. Run correctness tests before comparing performance. A faster result that changes guest behavior is a regression.
5. Report build status, test status, workload, device, thermal state, and repeated-run results. Do not describe unmeasured changes as speedups.

## Initial bottleneck map

For x86-64 system emulation on an ARM64 TCG host, likely areas to investigate—not presumed bottlenecks—are:

- x86 guest instruction translation and generated TCG operation quality;
- ARM64 TCG code generation and translation-block chaining/cache behavior;
- guest RAM access, TLB misses, and SoftMMU paths;
- emulated device and interrupt overhead;
- host Android/Bionic compatibility and build configuration;
- memory pressure, thermal throttling, and scheduler behavior on the phone.

Any code change must be tied to a profile or a reproducible benchmark.

## Baseline checklist

Record these before performance patches:

- QEMU commit SHA and local build configuration;
- Android version, SoC/CPU details, RAM, and available storage;
- compiler/NDK versions and build flags;
- whether the binary launches and which machine/device models work;
- guest configuration (vCPU count, RAM, disk image, display, and devices);
- cold-start time, boot-to-login time, idle CPU use, guest workload throughput, and memory use;
- at least five repeated runs where practical, with warm-up and thermal notes.

Use the same guest image, settings, and workload for every comparison. Keep a baseline result even if the first build is not yet runnable on Android.

## Build profile and experiments

The initial script `scripts/build-android-arm64-tcg.sh` builds only `x86_64-softmmu`, uses a Release build, and enables LTO. It is an experimental profile and has not been verified on the target phone yet.

- Default build: `bash scripts/build-android-arm64-tcg.sh`
- Separate lean-device experiment: `LEAN_DEVICES=1 bash scripts/build-android-arm64-tcg.sh`

The lean-device option maps to Meson's `-Ddefault_devices=false`. This can remove devices that a guest setup needs, so it is a separate experiment, not a default recommendation. A smaller binary does not automatically mean a faster guest.

Do not add `--enable-kvm` for x86-64-on-ARM64 expecting native execution. Do not assume configure flags from older QEMU releases still exist; verify the current `configure --help` and Meson options first.

### PGO

PGO is a later experiment, after a working baseline build and a repeatable workload exist. First verify that the selected Clang/LLVM version and this QEMU revision support the intended profile-generation mode. Clang instrumentation-based PGO commonly uses `-fprofile-instr-generate`, `LLVM_PROFILE_FILE`, and `llvm-profdata merge`, followed by a separate profile-use build. Do not mix GCC's `-fprofile-generate/-fprofile-use` workflow into a Clang build without checking compiler support.

The training run must exercise the same kind of guest workload that matters for the user. A profile from a trivial boot or an unrelated host workload may optimize the wrong paths. Keep generation and use builds in separate build directories and preserve the baseline.

### Compiler and code-size experiments

Treat `-O3`, LTO, target-specific CPU flags, and device pruning as separate experiments. `-march=native` is only appropriate if the compiler accurately identifies the actual host CPU and the produced binary will run on that same compatible device class. Do not guess a Cortex core name from the phone model alone.

BOLT is optional and only worth attempting after a working executable, representative profiles, and compatible LLVM tools are available.

## Staged implementation

### Stage 0 — Source and build reconnaissance
Confirm the upstream commit, available host/target combinations, Android NDK/Bionic constraints, and a minimal x86_64-softmmu build configuration. Do not alter emulator semantics.

### Stage 1 — Reproducible build and smoke tests
Establish a repeatable ARM64 Android-host build path. Confirm the resulting executable's host architecture, run QEMU help/version output, and run the smallest feasible headless guest smoke test.

### Stage 2 — Profiling
Use `simpleperf` or another profiler that is actually supported on the device to identify time spent in TCG execution, memory translation, and device emulation. Root-only tools and host Linux perf workflows may not be available on ordinary Android. If profiling on-device is unavailable, state that limitation and avoid drawing performance conclusions from desktop-only profiles.

Use detailed QEMU tracing or `-d op,out_asm` only for short diagnostic runs; logging can heavily distort timing. Do not benchmark with verbose tracing enabled.

### Stage 3 — Focused optimizations
Implement small, isolated changes only where the measurements justify them. Potential areas include TCG-generated code quality, ARM64 backend instruction selection, translation-block lookup/chaining, and SoftMMU/TLB hot paths. Do not enlarge TLBs or translation caches, change atomic implementations, or modify optimizer passes without a measured hypothesis and regression tests.

### Stage 4 — Regression and performance validation
Run relevant QEMU tests and guest smoke tests, then repeat the identical benchmarks. Reject changes that regress correctness or produce no repeatable benefit.

## Current status

- [x] Fork confirmed to be based on the official `qemu/qemu` GitHub mirror.
- [x] Created the `android-arm64-tcg-optimization` working branch.
- [x] Recorded the target and measurement-first process.
- [x] Added a configurable Release/LTO build script and optional lean-device experiment.
- [x] Documented the PGO and profiling workflow.
- [ ] Establish and verify an Android ARM64 host build.
- [ ] Capture baseline results on the target phone.
- [ ] Run PGO using a representative guest workload.
- [ ] Profile and land measured source-level optimizations.
