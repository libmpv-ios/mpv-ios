---
id: index
title: Introduction
sidebar_position: 1
---

# mpv-ios

A production-oriented libmpv-based media player for iOS, structured as
the iOS counterpart to [mpv-android](https://github.com/mpv-android/mpv-android):
same libmpv core, same dependency stack, ported to Apple's toolchain and
Swift/SwiftUI instead of the NDK/JNI/Kotlin stack.

:::info What this site covers
This is the full documentation for mpv-ios — build instructions,
architecture decisions, the contribution process, and (in **Engineering
Notes**) a detailed, honest log of every bug found and fixed while
porting mpv to iOS. If you only read one section before contributing,
make it [Engineering Notes → Research Log](./research/index.md) — it
will save you from re-diagnosing a problem someone already solved.
:::

## Project layout

```
mpv-ios/
├── project.yml             # XcodeGen spec — generates the .xcodeproj for CI
├── .github/workflows/      # CI: builds Libmpv.xcframework, releases, Appetize previews
├── buildscripts/           # Cross-compiles libmpv + deps → Libmpv.xcframework
│   ├── download.sh
│   ├── buildall.sh
│   ├── patches/mpv/        # iOS-compatibility patches applied to mpv source
│   └── scripts/mpv-ios.sh  # Final XCFramework assembly
├── MPVKit/                 # Swift Package: Swift wrapper around libmpv
│   └── Sources/
│       ├── CMPV/           # C shim (callback trampolines, GLES proc-address)
│       └── MPVKit/         # MPVCore, MPVProperty, MPVPlayer, MPVGLView, ...
└── mpv-ios-player/          # Example SwiftUI app consuming MPVKit
```

## What's real here vs. what you still need to do

Every file in this project is real, intended-to-compile production
code — not stubs or pseudocode. What it does **not** include:

- **A pre-built `Libmpv.xcframework`.** You must run the buildscripts on
  a Mac to produce it (see [Building](./building.md)) — this cannot be
  cross-compiled from Linux or Windows, since Apple's toolchain,
  codesigning, and SDKs are macOS-only.
- **Xcode project files** (`.xcodeproj`/`.xcworkspace`) checked into the
  repo. `MPVKit` is a standalone Swift Package; `project.yml` (via
  XcodeGen) generates the app target's project on demand.
- **App icons, launch screen, signing/provisioning.** Standard Xcode
  project setup, unrelated to mpv specifically.

## Why this project exists

Most iOS video players fall into one of two camps: they use `AVPlayer`
(Apple's built-in player, with real gaps — no MKV support, limited
subtitle format support, no advanced audio/video filter chain), or
they're closed-source apps with ads, subscriptions, or analytics a
privacy-conscious user might not want.

libmpv is the same playback engine that VLC, IINA (macOS), and
mpv-android are built on — it plays nearly anything AVPlayer refuses to
open. This project exists to bring that same capability natively to
iPhone/iPad, with the source fully open and documented.

See [Contributing](./contributing.md) for the fuller version of this
argument, including what you personally gain from contributing.

## Quick links

- 🛠️ **[Building the project](./building.md)** — full build steps, from
  a fresh clone to a working `Libmpv.xcframework`.
- 📱 **[Testing without a Mac or iPhone](./testing-without-a-mac.md)** —
  yes, this is actually possible, via a free Appetize.io preview.
- 🧭 **[Roadmap](./roadmap.md)** — where the project stands today and
  what's planned.
- 🤝 **[Contributing](./contributing.md)** — concrete areas where help is
  genuinely useful right now.
- 📖 **[Research Log](./research/index.md)** — the complete, chronological
  story of every build/compatibility bug found and fixed during
  development.
