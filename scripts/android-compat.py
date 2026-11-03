#!/usr/bin/env python3
"""Idempotent source patches so QEMU builds natively on Android (bionic/Termux).

Run automatically by scripts/build-android-arm64-max.sh before configure.
Safe to run repeatedly: every patch carries a marker and is skipped once applied.

Why:
  * Meson reports the host OS as 'android', so QEMU's CONFIG_LINUX (and every
    `host_os == 'linux'` check) is false and the Linux code paths are dropped.
    Android is Linux, so we map 'android' -> 'linux'.
  * bionic has no POSIX shm_open()/shm_unlink(); emulate them with memfd.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARK = "android-compat"


def patch(rel, old, new):
    p = ROOT / rel
    if not p.exists():
        print(f"[WARN]    {rel}: file not found, skipped", file=sys.stderr)
        return
    s = p.read_text()
    if MARK in s:
        print(f"[ok]      {rel}: already patched")
        return
    if old not in s:
        print(f"[WARN]    {rel}: anchor not found, skipped", file=sys.stderr)
        return
    p.write_text(s.replace(old, new, 1))
    print(f"[patched] {rel}")


patch(
    "meson.build",
    "host_os = host_machine.system()\n",
    "host_os = host_machine.system()\n"
    "# android-compat: Android is Linux; keep QEMU's Linux code paths enabled\n"
    "if host_os == 'android'\n"
    "  host_os = 'linux'\n"
    "endif\n",
)

patch(
    "util/oslib-posix.c",
    "#ifdef CONFIG_LINUX\n#include <sys/syscall.h>\n#endif\n",
    "#if defined(CONFIG_LINUX) || defined(__ANDROID__)\n"
    "#include <sys/syscall.h>\n"
    "#endif\n"
    "\n"
    "#ifdef __ANDROID__ /* android-compat */\n"
    "/* bionic has no POSIX shm_open/shm_unlink: use an anonymous memfd. */\n"
    "#define shm_open(name, oflag, mode) \\\n"
    "    ((int)syscall(__NR_memfd_create, \"qemu-shm\", 1U /* MFD_CLOEXEC */))\n"
    "#define shm_unlink(name) (0)\n"
    "#endif\n",
)
