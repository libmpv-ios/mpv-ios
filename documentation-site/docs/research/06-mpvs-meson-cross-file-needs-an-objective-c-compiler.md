---
id: 06-mpvs-meson-cross-file-needs-an-objective-c-compiler
title: "mpv's meson cross file needs an Objective-C compiler"
sidebar_label: "6. mpv's meson cross file needs an Objective-C compiler"
sidebar_position: 6
---

## 6. mpv's meson cross file needs an Objective-C compiler

**What happened:**
```
meson.build:1582:4: ERROR: 'objc' compiler binary not defined in cross file [binaries] section
```

**Root cause:** mpv's iOS VideoToolbox/GLES hardware-decode interop
(`video/out/hwdec/hwdec_ios_gl.m`) is Objective-C, and we'd enabled the
`ios-gl` meson feature that compiles it. meson's cross file only declared
`c` and `cpp` binaries under `[binaries]`, with no `objc`/`objcpp` entries.

**Fix:** since Apple's `clang` itself handles C, C++, and Objective-C
depending on file extension, we pointed `objc`/`objcpp` at the same
`clang`/`clang++` binaries already used for `c`/`cpp`, plus matching
`objc_args`/`objcpp_args` with the same `-arch`/`-isysroot`/version-min
flags as the other language entries. See `buildall.sh`'s `setup_prefix()`.

**A related gotcha we had to account for:** the generated `crossfile.txt`
lives inside the cached `prefix/<platform>/` directory, which is cached
across CI runs by dependency version. This particular fix didn't change
any dependency version, so the existing cache key wouldn't have picked up
the corrected crossfile automatically. We added a `CROSSFILE_REV` marker
to `ci.sh`'s cache key specifically for this kind of change (anything
that alters how `crossfile.txt` itself is generated, independent of
dependency versions), and bumped it.

**Lesson:** a fix to *how the build is configured* (not just *what
version of a dependency is used*) can still be silently masked by a
cache keyed only on dependency versions — worth checking whether a fix
actually needs a cache-invalidation companion change.
