# Android/ARM64-host TCG baseline for a lightweight Linux guest

This is a measurement plan, not a claim that QEMU has already been built or optimized.

## Goal

Run an x86_64 Linux guest on an ARM64 Android host using QEMU TCG, then measure the baseline before changing TCG internals. Ordinary Android ARM64 KVM does not provide native acceleration for an x86_64 guest.

## Stage 1: build the current baseline

In Termux, install the initial build dependencies:

\`\`\`sh
pkg update
pkg install git clang meson ninja pkg-config python glib pixman
\`\`\`

Clone only the current branch to reduce unnecessary Git history downloads:

\`\`\`sh
git clone --depth 1 -b android-arm64-tcg-optimization https://github.com/moein09810981/QUME-Optimized-Optiz.git
cd QUME-Optimized-Optiz
bash scripts/build-android-arm64-tcg.sh
\`\`\`

The first build may reveal missing Termux dependencies or incompatibilities with the current QEMU revision. If it fails, preserve the complete first error and fix that before attempting performance tuning. A successful build is not proof of guest compatibility.

## Stage 2: select a small guest image

Use a small x86_64 Linux image for the first boot test; do not download a Windows image for this stage. Verify the image's architecture and published checksum from the distribution's official site. Keep the image and QEMU build in separate directories.

Start with a console-only guest and a conservative memory allocation suitable for the phone. The exact boot command depends on the chosen image format and its console support, so do not assume one generic command will boot every ISO.

## Stage 3: record a baseline

Record at least:
- QEMU version and exact configure/build options.
- Guest image and checksum.
- Guest boot success, time to reach a usable shell, and any boot errors.
- A repeatable CPU workload's elapsed time, repeated at least three times.
- Guest RAM allocation, QEMU process memory if available, phone temperature/throttling, and whether the phone was charging.

Use the median of repeated runs. Keep the same guest image, RAM, CPU count, and workload for later comparisons. Do not compare results if thermal throttling or guest configuration changed substantially.

## Stage 4: optimize one variable at a time

1. Baseline build with the normal device set.
2. Test LTO/optimization flags while keeping the workload unchanged.
3. Test a representative Clang instrumentation-PGO profile collected from the same workload.
4. Only then profile hotspots and consider source changes in TCG/SoftMMU.

Treat `LEAN_DEVICES=1` as a compatibility experiment, not an automatic speed optimization; removing default devices can prevent a guest from booting. Keep each result and build configuration so changes can be reverted.

## Current status

The build and PGO scripts are experimental and have not been verified on the target phone in this workflow. No speedup is claimed until the guest boots and a repeatable baseline has been measured.
