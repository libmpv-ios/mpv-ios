---
id: 37-undefined-neon-symbols-linking-libmpv-combined-a-on-device-l
title: "Undefined NEON symbols linking `libmpv-combined.a` on device: libass's autotools build silently drops its own aarch64 asm sources"
sidebar_label: "37. Undefined NEON symbols linking `libmpv-combined.a` on device: libass's autotools build silently drops its own aarch64 asm sources"
sidebar_position: 38
---

## 37. Undefined NEON symbols linking `libmpv-combined.a` on device: libass's autotools build silently drops its own aarch64 asm sources

**What happened:** the iOS **device** build (`--platform ios-arm64`,
arm64, real hardware — not the simulator) failed at the final
`MPVIOSPlayer` link step with over two dozen undefined symbols, all from
one object file:
```
Undefined symbols for architecture arm64:
  "_ass_add_bitmaps_neon", referenced from:
      _ass_bitmap_engine_init in libmpv-combined.a[2186](ass_bitmap_engine.o)
  "_ass_be_blur_neon", referenced from: ...
  "_ass_blur4_horz16_neon", referenced from: ...
  ... (24 total, all libass's *_neon symbols)
ld: symbol(s) not found for architecture arm64
clang: error: linker command failed with exit code 1
```
Every missing symbol was a NEON-optimized function from libass, all
referenced from a single dispatcher, `ass_bitmap_engine_init`. The build
had gotten past every compile step (CMPV, MPVKit, MPVIOSPlayer all
compiled and linked their own object files fine) — this was purely a
missing-symbol failure at the very last, whole-program link.

**Root cause:** `ass_bitmap_engine_init()` (`libass/ass_bitmap_engine.c`)
picks its function-pointer table at runtime based on two **compile-time**
macros: `#if CONFIG_ASM` and `#elif ARCH_AARCH64`, both set by libass's
own build system, not detected at runtime. `buildscripts/scripts/libass.sh`
built libass with the legacy autotools path (`./configure` /
`Makefile.am`), and `configure.ac` does still define `CONFIG_ASM=1` and
`ARCH_AARCH64=1` for an aarch64 host (`AM_COND_IF([AARCH64], [AC_DEFINE(
ARCH_AARCH64, 1)])` etc.) — so `ass_bitmap_engine_init` compiled the branch
that calls `ass_add_bitmaps_neon`, `ass_be_blur_neon`, and the rest. But
`Makefile.am` has **zero references** to `libass/aarch64/*.S` — the five
files that actually implement those functions
(`asm.S`, `be_blur.S`, `blend_bitmaps.S`, `blur.S`, `rasterizer.S`) are
never listed in any `_SOURCES` variable, so autotools never compiles or
archives them. libass's *Meson* build (`libass/meson.build`) does list
them explicitly (`src_aarch64 = files('aarch64/asm.S', ...)`, wired in
under `elif generic_cpu_family == 'aarch64'`) — Meson is libass's current,
actively-maintained build system, and the autotools one is a legacy path
that was evidently never updated when ARM NEON asm support was added.
Compounding this: our `libass.sh` never exported an `AS` (assembler) to
`configure` at all (unlike `CC`/`CXX`/`AR`/`RANLIB`, which it did pass),
so even a Makefile.am that did list `.S` files would likely have used the
wrong toolchain for them.

This is why the earlier simulator build (entry #36's fix) never surfaced
this: `ass_bitmap_engine_init` only takes the `ARCH_AARCH64`/NEON branch
under `#elif`, guarded by `#if ARCH_X86` above it for x86 — the simulator
slice built here is arm64 too in this repo's matrix, but per mpv-ios's
own platform table x86_64-simulator exists as a separate slice; whichever
simulator slice actually got exercised previously took the `ARCH_X86`/
`_c` scalar fallback path instead, which references no `*_neon` symbols
and links fine regardless of whether the aarch64 `.S` files were compiled.

**Actual fix:** rewrote `buildscripts/scripts/libass.sh` to build with
Meson + Ninja instead of autotools, mirroring the existing pattern used by
every other Meson-based dependency in this repo (`fribidi.sh`,
`harfbuzz.sh`, `freetype2.sh`, etc.): `meson setup $build --cross-file
"$prefix_dir"/crossfile.txt`, disabling `fontconfig` (iOS has no
fontconfig; libass falls back to its CoreText backend, auto-detected by
Meson on Darwin the same way autotools' `configure` auto-detected it) and
enabling `libunibreak`, then `ninja install`. This routes through
`libass/meson.build`'s `src_aarch64` list, so the `.S` files actually get
assembled and archived this time. No changes were made to
`Package.swift`, `CMPV`, or anything under `mpv-ios-player/` — this was
purely a static-library-composition problem one dependency down.

**Verification:** confirmed by reading libass's own `Makefile.am` and
`meson.build` side by side (cloned upstream `master`, the same ref this
repo's `v_ci_libass` pin tracks) — `grep -rn aarch64 Makefile.am` returns
nothing, `grep -n aarch64 libass/meson.build` returns the explicit
`src_aarch64` file list. Also confirmed `configure.ac` genuinely does set
`CONFIG_ASM`/`ARCH_AARCH64` for aarch64 unconditionally (no nasm/gas
version check the way x86 has — ARM's `can_asm=true` unconditionally in
the `AS_CASE([$host], [aarch64], ...)` branch), which is what let the
dispatcher compile a call it could never satisfy.

**Lesson:** a static C library that ships two parallel build systems can
silently diverge on *which source files are even part of the build*, not
just on flags or generated output — and the failure mode isn't a build
error in that library itself (libass builds and archives cleanly either
way; `make`/`ninja` both exit 0), it's a *linker* error two steps removed,
in whatever finally links against the resulting `.a`. `configure.ac` and
`meson.build` looking equivalent on the options they expose
(`--enable-libunibreak` / `-Dlibunibreak=enabled`,
`--disable-fontconfig` / `-Dfontconfig=disabled`) says nothing about
whether their compiled source lists actually match — that has to be
checked directly, per architecture, against each build file's own source
lists, especially for a dependency whose upstream repo keeps a legacy
build system around at all (its presence implies it's not the primary
one anymore, which is exactly when it's most likely to have quietly
stopped tracking new source files).

