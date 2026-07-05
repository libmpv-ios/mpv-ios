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

## Explicitly not planned (for now)

Worth stating directly, since "why doesn't this do X" is a natural
question:

- **A Metal render backend.** This was tried and abandoned early in the
  project — libmpv's public render API doesn't have a Metal backend (only
  OpenGL and software rendering exist; see the main README's "Architecture
  notes" section for the full explanation). This isn't a "not yet," it's
  a "the library doesn't support this," short of a much larger upstream
  contribution to libmpv itself.
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
