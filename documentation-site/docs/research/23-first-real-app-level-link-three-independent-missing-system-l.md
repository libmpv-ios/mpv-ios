---
id: 23-first-real-app-level-link-three-independent-missing-system-l
title: "First real app-level link: three independent missing-system-library/naming bugs, surfacing together"
sidebar_label: "23. First real app-level link: three independent missing-system-library/naming bugs, surfacing together"
sidebar_position: 24
---

## 23. First real app-level link: three independent missing-system-library/naming bugs, surfacing together

**What happened:** with entries 21 and 22 fixed, CI reached the actual
link step of the `MPVIOSPlayer` app target for the first time — the
first point in this whole project where anything produces a final
Mach-O binary out of `libmpv-combined.a`, rather than just compiling
`MPVKit`'s own Swift/C sources against it. The link failed with a wall
of output covering what turned out to be three unrelated bugs, plus one
red herring:

1. `ld: warning: no platform load command found in
   '...libmpv-combined.a[x86_64][...]cdef16_sse.obj'` (repeated for many
   object files) — a `libtool -static` warning, not a hard error;
   harmless as long as `ld`'s own "assuming: iOS-simulator" guess is
   correct, which it was here. Not investigated further.
2. `ld: warning: Could not find or use auto-linked framework
   'CoreAudioTypes'` and `Could not parse or use implicit file
   '.../SwiftUICore.framework/SwiftUICore.tbd': cannot link directly
   with 'SwiftUICore' because product being built is not an allowed
   client of it` — looked alarming, but a web search turned up several
   unrelated projects (a CocoaPods/Cloudinary issue, HaishinKit,
   Kotlin Multiplatform builds, an Expo/Xcode-16.1 report) hitting the
   *exact same two warnings*, always alongside a real, unrelated
   undefined-symbol error in the same build. `SwiftUICore` is a
   restricted-linkage Apple framework that ordinary targets aren't
   allowed to link directly — Xcode's own auto-linking appears to
   mis-infer a direct dependency on it (and, separately, on
   `CoreAudioTypes`) whenever *something else* in the same link job has
   already failed with undefined symbols. Across every case found, no
   one needed to "fix" `SwiftUICore` itself — only the framework's
   *auto-link inference failing loudly* is new in Xcode 16; the
   underlying trigger was consistently a real, separate linker error.
   `CoreAudioTypes` specifically, unlike `SwiftUICore`, is a normal
   (if newer) linkable framework — adding it to `linkerSettings`
   resolves that half; `SwiftUICore` needed no fix at all once the
   actual undefined symbols below were resolved.
3. `Undefined symbols`: three genuinely independent problems, all
   producing undefined-symbol errors that happened to appear in the same
   link log:
   - Every `_lua_*`/`_luaL_*` symbol (dozens) — traced to
     `buildscripts/scripts/mpv-ios.sh`'s `LIBNAMES` array listing the
     entry as `lua54`. Lua 5.2.4's own `Makefile install` target always
     produces `liblua.a`, never a version-suffixed name (confirmed by
     `lua.sh`'s own generated `lua.pc`: `Libs: -L${libdir} -llua`). The
     combine script's candidate loop tried `liblua54.a` then
     `liblua5454.a` — neither ever existed, so Lua's static lib was
     silently dropped from `libmpv-combined.a` on every single build
     since this project began, and nothing surfaced it until an actual
     app tried to link against the combined library.
   - `_BZ2_bz*`, `_deflate*`/`_inflate*`, `_iconv*` — genuine system
     libraries (`libbz2`, `libz`, `libiconv`) that ffmpeg's demuxers
     (Matroska block decompression), libass, and mpv's own PNG encoder
     call into, but which were never declared anywhere as a linked
     library for any target in `MPVKit/Package.swift`. A static library
     never pulls in its own system-library dependencies the way a
     dynamic framework does — this was simply never needed before
     because nothing had linked a real app binary against
     `libmpv-combined.a` until this point.
   - `_avdevice_register_all`, `_avdevice_version` — referenced
     unconditionally by mpv's own `common_av_log.c` (version-check and
     registration bookkeeping at startup, unrelated to any actual
     device-input feature), but `ffmpeg.sh` passed `--disable-devices`,
     which fully disables building `libavdevice.a` at all — not just the
     individual OS-specific device backends. On iOS there are genuinely
     no usable device backends, but the library itself (with just its
     registration table and these two entry points) still needs to
     exist.

**Fixes:**
- `mpv-ios.sh`: `LIBNAMES` entry changed from `lua54` to `lua`; added
  `avdevice` to the list; the platform-combine loop now hard-fails
  (rather than silently skipping) if any expected static lib isn't found
  for a platform, printing exactly which name(s) went unmatched — so a
  future naming mismatch like this one surfaces immediately at combine
  time instead of resurfacing three build stages later as a wall of
  undefined symbols with no obvious connection back to the cause.
- `ffmpeg.sh`: `--disable-devices` replaced with `--disable-indevs
  --disable-outdevs`, which still disables every actual OS-specific
  device driver (none of which exist on iOS anyway) while leaving
  `libavdevice.a` itself buildable, satisfying mpv's unconditional
  reference to its two entry points.
- `MPVKit/Package.swift`: added `linkerSettings` to the `MPVKit` target —
  `.linkedLibrary` for `z`, `bz2`, `iconv`; `.linkedFramework` for
  `AVFoundation`, `AudioToolbox`, `CoreAudio`, `CoreAudioTypes`,
  `VideoToolbox`, `CoreMedia` (matching what mpv/ffmpeg's own enabled
  build options actually use).

**Lesson:** a static library combine step that silently drops a
component it couldn't find (rather than failing loudly) can ship broken
for an arbitrarily long time — this project's Lua bundling was wrong
from very early on and nothing caught it until the very first attempt to
link a real app against the combined library, at which point the
resulting error (dozens of undefined `_lua_*` symbols) gave no direct
hint that the actual bug was a filename typo three build stages earlier.
Separately: warnings that look the most alarming in a build log
(`SwiftUICore` — a "not an allowed client" framework-linkage rejection)
aren't necessarily the actual bug; matching the exact warning text
against other projects' reports is often faster than reasoning about the
warning from first principles, and revealed this one to be a downstream
symptom of the real undefined-symbol errors rather than an independent
problem needing its own fix.
