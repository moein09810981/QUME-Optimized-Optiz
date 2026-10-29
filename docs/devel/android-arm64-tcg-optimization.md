# Android ARM64 TCG optimization plan

## Target and non-goals

Target host: Android 16 on an ARM64 phone (Poco M6 class device).
Target guest: x86-64 Windows using QEMU system emulation.
Initial accelerator: TCG. An ARM64 Android host cannot use ordinary ARM KVM to execute an x86-64 guest natively; CPU instructions must be translated.

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

## Staged implementation

### Stage 0 — Source and build reconnaissance
Confirm the upstream commit, available host/target combinations, Android NDK/Bionic constraints, and a minimal x86_64-softmmu build configuration. Do not alter emulator semantics.

### Stage 1 — Reproducible build and smoke tests
Establish a repeatable ARM64 Android-host build path. Confirm the resulting executable's host architecture, run QEMU help/version output, and run the smallest feasible headless guest smoke test.

### Stage 2 — Profiling
Use available host profiling and QEMU tracing facilities to identify time spent in TCG execution, memory translation, and device emulation. If profiling on-device is unavailable, state that limitation and avoid drawing performance conclusions from desktop-only profiles.

### Stage 3 — Focused optimizations
Implement small, isolated changes only where the measurements justify them. Keep each change on its own commit and compare against the baseline.

### Stage 4 — Regression and performance validation
Run relevant QEMU tests and guest smoke tests, then repeat the identical benchmarks. Reject changes that regress correctness or produce no repeatable benefit.

## Current status

- [x] Fork confirmed to be based on the official `qemu/qemu` GitHub mirror.
- [x] Created the `android-arm64-tcg-optimization` working branch.
- [x] Recorded the target and measurement-first process.
- [ ] Establish and verify an Android ARM64 host build.
- [ ] Capture baseline results on the target phone.
- [ ] Profile and land measured source-level optimizations.
