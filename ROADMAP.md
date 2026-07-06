# Roadmap

This is a living document, not a promise with dates attached — this
project has no dedicated team or funding behind it, so progress depends on
whoever shows up to work on a given piece. Where something depends on a
specific blocker (money, a person with a Mac, a decision), that's called
out explicitly rather than glossed over.

For the day-to-day "here's exactly what to work on" list, see
[CONTRIBUTING.md](CONTRIBUTING.md)'s "Where help is genuinely needed right
now" section — this document is the higher-level "why these phases, in
this order" view. The two are kept in sync; if they ever drift, trust
CONTRIBUTING.md for the concrete task list.

## Where things stand today

Honest status, not aspirational:

- **Build pipeline**: functional. `buildscripts/` cross-compiles libmpv and
  its full dependency chain (mbedtls, dav1d, libxml2, ffmpeg, freetype,
  fribidi, harfbuzz, unibreak, libass, lua, libplacebo) for iOS device +
  simulator, and `mpv-ios.sh` assembles the result into a working
  `Libmpv.xcframework`. This has been debugged against real CI failures
  (bash 3.2 incompatibilities, missing execute permissions, a libxml2
  upstream break from a removed meson option) rather than only reasoned
  about in the abstract.
- **MPVKit (Swift wrapper)**: functional core — `MPVCore` (lifecycle,
  commands, event loop), `MPVProperty` (typed get/set/observe),
  `MPVPlayer` (play/pause/seek/volume/tracks), `MPVGLView` (OpenGL ES/EAGL
  rendering via mpv's render API, with VideoToolbox hardware decode).
- **App (mpv-ios-player)**: basic but real — file/URL loading, playback
  controls, seek bar, track selection, SwiftUI throughout.
- **CI**: build verification on every push, automated weekly dependency
  version-bump PRs, a free no-Mac-required Simulator preview path via
  Appetize.io.
- **Not yet done**: signed release builds, TestFlight, App Store
  submission, real-device testing (everything so far has been built and
  reasoned through without access to a physical iPhone or a Mac during
  development), a native high-resolution app icon, and a number of player
  features mpv-android already has (see below).

## Phase 1 — Solidify the foundation (current focus)

Goal: make what already exists reliable before adding more surface area.

- [ ] Get the build pipeline green on a real, from-scratch run (fresh
      clone, no cached prefix) and keep it that way — the dependency-check
      workflow will keep surfacing version-bump breaks; the goal here is
      turning those around quickly rather than letting them accumulate.
- [ ] Real-device validation of the core playback path: does a file
      actually decode, render, and play correctly on a physical iPhone,
      not just build successfully. This is the single biggest unknown
      right now (see CONTRIBUTING.md's "Real-device testing" section) —
      everything upstream of this point has been validated by reasoning
      and CI, not by watching a video actually play.
- [ ] Native 1024×1024 app icon (current one is a 2x upscale from
      mpv-android's 512×512 source — functional, not final).
- [ ] Fill in gaps in MPVKit's API surface as real usage surfaces them —
      this is normal for a young wrapper library, not a sign anything is
      wrong with the current design.

## Phase 2 — Player feature parity with mpv-android

Goal: close the gap between "plays video" and "a player people would
actually choose to use day-to-day." Roughly in priority order, though not
strictly sequential — these are largely independent and can be picked up
in any order:

- [ ] Gesture controls: swipe to seek/adjust volume/adjust brightness
      (mpv-android has this; `MPVPlayerView` currently only has tap and
      button controls).
- [ ] Subtitle customization: style, size, delay/sync adjustment, and
      picking among embedded subtitle formats mpv supports.
- [ ] Chapter navigation.
- [ ] A-B repeat and playback speed presets.
- [ ] Picture-in-Picture support.
- [ ] Now Playing / Control Center / lock-screen remote control
      integration (`MPRemoteCommandCenter` /
      `MPNowPlayingInfoCenter`) — currently absent; background audio
      works (see `Info.plist`'s `UIBackgroundModes`) but isn't
      controllable from the lock screen.
- [ ] Playlist / queue support for multi-file playback.
- [ ] Local network / file-sharing sources beyond the current file-picker
      and manual-URL entry (e.g. SMB, WebDAV — mpv-android supports
      several).

## Phase 3 — Distribution

Goal: get this into people's hands without requiring them to build it
themselves.

- [ ] **Signed release builds.** Currently blocked on having an Apple
      Developer Program account ($99/year) behind the project — see
      CONTRIBUTING.md's "Signed release builds / TestFlight" section for
      what's needed and how to help (a sponsor, a co-maintainer with an
      existing account, or funding to acquire one).
- [ ] TestFlight beta distribution, once signing is sorted out.
- [ ] Decide on and document a stance on App Store submission — mpv's
      GPL/LGPL licensing (see the main README's "License note") needs a
      clear compliance plan before this is pursued, the way VLC and other
      GPL-licensed apps on the App Store have had to work through.
- [ ] If App Store submission isn't viable or desired, document
      alternative distribution clearly (e.g. build-it-yourself
      instructions are already the default state; an AltStore/sideloading
      guide could be a lighter-weight middle ground worth exploring).

## Phase 4 — Ecosystem and polish

Longer-horizon, lower-urgency items:

- [ ] macOS (Catalyst or native) support — the render path
      (`MPVGLView`'s OpenGL ES/EAGL approach) is iOS-specific by design;
      a macOS target would likely want to reconsider whether to share
      that code or use a separate AppKit-native render path, given macOS
      has more rendering backend options available to it than iOS does.
      Worth a design discussion before starting, not a quick port.
- [ ] iPad-specific layout refinement (`mpv-ios-player` currently targets
      both device families via `TARGETED_DEVICE_FAMILY: "1,2"` in
      `project.yml`, but the UI hasn't been specifically tuned for
      larger screens / multitasking / Stage Manager).
- [ ] Localization — currently English-only.
- [ ] Accessibility audit (VoiceOver labels, Dynamic Type support in the
      player controls) — not yet done.
- [ ] Performance profiling on lower-end/older supported devices (current
      deployment target is iOS 15.0, per `project.yml`).
- [ ] **Vulkan via MoltenVK, as a second render backend alongside OpenGL
      ES.** Investigated in depth (see the corresponding closed
      discussion/issue for the full research trail) but not started —
      documenting the findings here so whoever picks this up next isn't
      starting from zero.

      **What's confirmed possible:** libmpv has no Metal render-API
      backend (see "Explicitly not planned" below), but mpv *does*
      support Vulkan as a `gpu-next`/libplacebo backend, and MoltenVK
      layers Vulkan on top of Metal on Apple platforms — including iOS,
      officially, App-Store-distributable, using only public Apple APIs
      (no private API usage). The specific integration point is
      `VK_EXT_metal_surface` (`vkCreateMetalSurfaceEXT`), which creates a
      `VkSurfaceKHR` directly from a `CAMetalLayer` — critically, this
      does **not** require `NSApplication`/AppKit the way mpv's existing
      macOS Vulkan context (`video/out/vulkan/context_mac.m`) does, so
      the reason that file doesn't work on iOS doesn't apply to a
      from-scratch iOS context using this extension.

      **What this would actually take** (verified against mpv's real
      source, not guessed):
      1. A new `video/out/vulkan/context_ios.m` — modeled on
         `video/out/vulkan/context_android.c` (104 lines, no desktop
         windowing dependency, creates its `VkSurfaceKHR` directly from a
         native window handle via `vkCreateAndroidSurfaceKHR` — the iOS
         equivalent would use `vkCreateMetalSurfaceEXT` with a
         `CAMetalLayer` the same way). This is a new file, not a patch to
         anything existing.
      2. A small registration patch to `video/out/gpu/context.c` (an
         `extern` declaration plus one array entry, following the exact
         pattern already used for `ra_ctx_vulkan_android`).
      3. A `meson.build`/`meson.options` change: a new feature option
         (e.g. `ios-vulkan`), conditionally compiling the new context file,
         and defining `VK_USE_PLATFORM_METAL_EXT` for the iOS target.
      4. `buildscripts/`: re-enable `-Dvulkan=enabled` in `mpv.sh` (currently
         force-disabled — see that script's comments), and a **new**
         `buildscripts/scripts/moltenvk.sh` to cross-compile MoltenVK
         itself for iOS. Note: Homebrew's `molten-vk` formula was checked
         and does **not** help here — it only builds MoltenVK's macOS
         slice, not iOS, so it can't be used as a shortcut the way some
         other dependencies might be. MoltenVK's own build is Xcode-project-
         based (`MoltenVKPackaging.xcodeproj`, via its `fetchDependencies`
         script pulling in SPIRV-Cross/glslang/Vulkan-Headers/cereal), not
         meson/autotools like this project's other dependencies, so
         `moltenvk.sh` would need a genuinely different shape than the
         existing dependency scripts.
      5. `libplacebo`'s build flags would need `-Dvulkan` re-enabled
         (currently disabled — see `libplacebo.sh`'s comments) once
         MoltenVK is available to link against.

      **Why this hasn't been started:** the honest blocker is that none
      of the above can be test-compiled without a Mac (the same
      constraint noted throughout this project), and this particular
      change touches five different files/scripts across two build
      systems (meson and Xcode-project-based) with no working reference
      commit in this project to iteratively debug against the way, e.g.,
      the `avfoundation` audio patches could be — those were fixed by
      reading real CI compiler errors one at a time. A change this size
      attempted "blind" risks many rounds of guess-and-check once a Mac
      *is* available, rather than a clean first attempt. Good next step
      for someone with sustained Mac access and comfort debugging Xcode
      project builds, not a quick PR.

      **Uncertain / not yet investigated:** how much this would actually
      improve on the current OpenGL ES path in practice on real iOS
      hardware — libplacebo's more advanced shader features are the
      theoretical upside, but no benchmarking exists yet to confirm the
      real-world difference is worth this integration cost. Worth
      measuring on the existing OpenGL ES path's actual limitations
      before assuming Vulkan is the right next step, not just because
      it's more capable on paper.

## Explicitly not planned (for now)

Worth stating directly, since "why doesn't this do X" is a natural
question:

- **A Metal render backend, specifically inside libmpv's public render
  API.** This was tried and abandoned early in the project — libmpv's
  render API (`mpv_render_context_create()` and friends) doesn't have a
  Metal backend (only OpenGL and software rendering exist; see the main
  README's "Architecture notes" section for the full explanation). This
  isn't fixable with a small patch the way the `avfoundation` audio
  output was — short of a much larger upstream contribution to libmpv
  itself, there's no Metal `MPV_RENDER_API_TYPE_*` to target. **Note:**
  this doesn't rule out Vulkan-via-MoltenVK as an indirect path to
  Metal-backed rendering — see the Vulkan/MoltenVK item in Phase 4 above,
  which is a different (and much larger) undertaking than what was ruled
  out here.
- **Android support in this repo.** This project exists because
  mpv-android already covers Android well — there's no plan to unify the
  two codebases; they're deliberately separate, platform-native
  implementations sharing only the underlying libmpv/mpv approach.

## How this roadmap gets updated

Anyone is welcome to propose changes to this roadmap — open an issue with
the **Feature Request** template (see [CONTRIBUTING.md](CONTRIBUTING.md))
if you think a phase is missing something, mis-prioritized, or if you want
to claim an item and want it noted here as in-progress. This isn't a
top-down plan handed down by a fixed team — it reflects what's realistic
given who's actually contributing at any given time.
