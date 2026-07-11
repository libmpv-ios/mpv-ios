---
id: architecture
title: Architecture Notes
sidebar_position: 1
---

# Architecture Notes

Design decisions worth understanding before touching the render or audio
pipeline.

## No Metal render backend

libmpv's public render API (`include/mpv/render.h`) only defines two
backends: `MPV_RENDER_API_TYPE_OPENGL` and a software renderer — there is
**no Metal render-API type**, verified directly against libmpv's own
headers rather than assumed.

mpv's own Metal usage on macOS goes through Vulkan+MoltenVK inside an
AppKit-only window path (`video/out/vulkan/context_mac.m`), which
requires `NSApplication` and doesn't run on iOS.

This project instead uses **OpenGL ES via EAGL** — the path mpv upstream
itself ships for iOS (`video/out/hwdec/hwdec_ios_gl.m`, gated by meson's
`ios-gl` feature), with VideoToolbox hardware frames imported zero-copy
via `CVOpenGLESTextureCache`. See `MPVGLView.swift` in `MPVKit` for the
implementation — `CAEAGLLayer` + `EAGLContext` + libmpv's OpenGL render
API, with a dedicated render queue and a C callback trampoline bridging
mpv's "new frame ready" notification into Swift.

:::tip See also
A Vulkan-via-MoltenVK path has been investigated as a possible second
render backend, confirmed technically feasible via `VK_EXT_metal_surface`
but not yet attempted — see the [Roadmap](./roadmap.md) and
[Research Log entry 14](./research/index.md) for the full breakdown.
:::

## No fontconfig

iOS provides CoreText; libass and harfbuzz are built with their CoreText
backends instead of fontconfig + libxml2-based font matching, matching
how mpv itself is typically built for Apple platforms.

## Static linking throughout

Everything is merged into one static `libmpv-combined.a` per platform via
`libtool -static`, then wrapped in an XCFramework — App Store apps can't
casually ship a collection of loose `.dylib`s the way Android apps ship
`.so` files per-ABI.

## mpv source is patched for iOS before building

A small number of mpv's audio-output files (`ao_avfoundation.m` and the
CoreAudio utility files it shares code with) call macOS-only APIs from
otherwise iOS-compatible code paths. Rather than disabling those features
entirely, `buildscripts/patches/mpv/` contains small, targeted patches
that narrow the actual problem down to the specific unavailable
call/type, applied automatically by `download.sh`.

This is what lets the build re-enable `avfoundation` (mpv's more modern
audio output, with spatial audio support) instead of falling back to only
the more limited `audiounit`. See `buildscripts/patches/mpv/README.md`
and [Research Log entries 10–12](./research/index.md) for the complete
story of what's patched and why.

## Dependency versioning strategy

- **Tarball-pinned dependencies** (`lua`, `freetype`, `harfbuzz`,
  `fribidi`, `mbedtls`, `libxml2`, `unibreak`) have exact versions pinned
  in `buildscripts/include/depinfo.sh`, checked weekly by an automated
  `dependency-check.yml` workflow that opens a PR per available update
  (Dependabot doesn't cover this — there's no ecosystem for versions
  embedded in a shell script).
- **Git-cloned dependencies** (`mpv`, `ffmpeg`, `dav1d`, `libass`,
  `libplacebo`) are pinned in CI to a tag/commit set via `v_ci_*`
  variables in the same file, following the same pattern
  [mpv-android](https://github.com/mpv-android/mpv-android) itself uses
  for `ffmpeg` (`v_ci_ffmpeg`) — local/manual builds still clone latest
  HEAD for convenience, but CI needs a reproducible, intentionally chosen
  version so an unrelated upstream commit landing between two pushes
  can't silently break CI on code nobody here touched.

## CI cache invalidation

The dependency-prefix cache (see `buildscripts/include/ci.sh`) is keyed
partly on a `BUILD_LOGIC_REV` marker, not just on dependency versions —
this exists because the cached `prefix/<platform>/` directory contains
the *compiled output* of this project's own build scripts, not just
"whatever version of each dependency was requested." A change to any
build script's logic (not just a version bump) needs this marker bumped,
or a stale cache can mask the fix. See Research Log entries 6 and 13 for
two real incidents this caused.
