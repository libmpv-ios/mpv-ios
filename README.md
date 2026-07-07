# mpv for IOS

[![Build Status](https://github.com/AeonCoreX-Lab/mpv-ios/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/AeonCoreX-Lab/mpv-ios/actions/workflows/build.yml)

mpv-ios is a video player for IOS based on [libmpv](https://github.com/mpv-player/mpv).

A production-oriented libmpv-based media player for iOS, structured as the
iOS counterpart to [mpv-android](https://github.com/mpv-android/mpv-android):
same libmpv core, same dependency stack, ported to Apple's toolchain and
Swift/SwiftUI instead of the NDK/JNI/Kotlin stack.

## Contributing

Contributions are welcome — see **[CONTRIBUTING.md](CONTRIBUTING.md)** for
concrete areas where help is genuinely useful right now (signed release
builds, real-device testing, a native app icon, player features, and
more), plus code style and testing notes. See **[ROADMAP.md](ROADMAP.md)**
for the bigger picture — where the project stands today and what's planned
across each upcoming phase.

## Documentation

Beyond this README, see **[docs/](docs/)** for reference material: the
proposed URL scheme / Universal Links integration spec, the privacy
policy, the maintainer release checklist, and
**[docs/RESEARCH.md](docs/RESEARCH.md)** — a chronological log of every
build/compatibility bug found and fixed while porting mpv to iOS, worth
checking before troubleshooting a build failure that might already be
documented there.

## Project layout

```
mpv-ios/
├── project.yml            # XcodeGen spec — generates the .xcodeproj for CI
├── .github/workflows/
│   ├── build.yml           # Builds Libmpv.xcframework on every push
│   ├── release.yml         # Publishes it as a GitHub Release on version tags
│   └── appetize-preview.yml # Builds the app + uploads to Appetize.io for
│                            # free, interactive, no-Mac-needed simulator testing
├── buildscripts/          # Cross-compiles libmpv + deps → Libmpv.xcframework
│   ├── download.sh
│   ├── buildall.sh
│   └── scripts/mpv-ios.sh # Final XCFramework assembly
├── MPVKit/                # Swift Package: Swift wrapper around libmpv
│   ├── Package.swift
│   └── Sources/
│       ├── CMPV/          # C shim (callback trampolines, GLES proc-address)
│       └── MPVKit/        # MPVCore, MPVProperty, MPVPlayer, MPVGLView, ...
└── mpv-ios-player/         # Example SwiftUI app consuming MPVKit
    ├── MPVIOSPlayerApp.swift
    ├── MPVRootView.swift
    ├── MPVPlayerView.swift
    ├── PlayerViewModel.swift
    ├── Assets.xcassets/    # App icon + in-app logo (derived from mpv-android's icon)
    └── Info.plist
```

## What's real here vs. what you still need to do

Every file in this repo is real, intended-to-compile production code — not
stubs or pseudocode. What it does **not** include:

- **A pre-built Libmpv.xcframework.** You must run the buildscripts on a Mac
  to produce it (see below). This cannot be cross-compiled from Linux —
  Apple's toolchain, codesigning, and SDKs are macOS-only.
- **Xcode project files (.xcodeproj/.xcworkspace).** MPVKit is a standalone
  Swift Package (add it via Xcode's "Add Package Dependency" -> "Add Local...").
  The `mpv-ios-player/` folder is a set of Swift source files meant to be
  dropped into a new Xcode iOS App project target, not an Xcode project
  itself — generate a new App target in Xcode, add these files to it, and
  link the MPVKit package.
- **App icons, launch screen, signing/provisioning.** Standard Xcode project
  setup, unrelated to mpv specifically.

## App icon & logo

`mpv-ios-player/Assets.xcassets/` includes two image sets derived from
mpv-android's own launcher icon
(`fastlane/metadata/android/en-US/images/icon.png`, the 512×512 master used
for its Play Store listing):

- **`AppIcon.appiconset`** — the actual iOS App Icon (1024×1024, upscaled
  from the 512×512 source, flattened onto an opaque background since App
  Store icons cannot have transparency). Xcode's modern single-size icon
  format generates every required smaller size automatically at build time.
- **`AppLogo.imageset`** — the same artwork at 1x/2x/3x (128/256/384px),
  transparency preserved, for in-app use (currently shown on `MPVRootView`'s
  landing screen via `Image("AppLogo")`).

When you add `mpv-ios-player/`'s files to your Xcode project, make sure
`Assets.xcassets` is included and that your target's "App Icons and Launch
Images Source" build setting points at `AppIcon` (Xcode does this
automatically if you drag in the whole `Assets.xcassets` folder and it's
the only one in the target).

Since the icon was upscaled 2x from a 512×512 source rather than authored
natively at 1024×1024, consider commissioning or vectorizing a native
high-resolution version before shipping to the App Store — the upscale is
clean enough for development/TestFlight but a from-scratch 1024×1024 (or an
SVG re-export, since mpv-android's `mpv_logo.xml` is a vector drawable) will
look sharper on device.

## Testing without a Mac or a physical iPhone

You still need a Mac to *build* this project (Apple's toolchain doesn't run
elsewhere), but you do **not** need a Mac or an iPhone to *interact with*
the built app afterward. See **[TESTING.md](TESTING.md)** for the complete
step-by-step walkthrough (account setup, secrets, first run, what to
expect). Short version: `.github/workflows/appetize-preview.yml` builds
the app for the iOS Simulator (unsigned, no Apple Developer account
needed) and uploads it to [Appetize.io](https://appetize.io), which streams
a real, tappable virtual iPhone into your browser for free.

## Build steps

### 1. Build libmpv for iOS (macOS required)

```bash
cd buildscripts
brew install meson ninja pkg-config gnu-sed nasm autoconf automake libtool
./download.sh
./buildall.sh --all-platforms
cd ..
./buildscripts/scripts/mpv-ios.sh build
```

This produces `Libmpv.xcframework` at the repo root. See
`buildscripts/README.md` for details, troubleshooting, and the full
dependency tree.

### 2. Wire it into MPVKit

```bash
mkdir -p MPVKit/Frameworks
cp -R Libmpv.xcframework MPVKit/Frameworks/
```

Verify the package builds:

```bash
cd MPVKit
swift build -Xswiftc -sdk -Xswiftc "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -Xswiftc -target -Xswiftc arm64-apple-ios17.0-simulator
```

(A plain `swift build` targets your Mac's own OS, which won't work here
since MPVKit's binary target is iOS/tvOS-only — building for a simulator
destination as above, or building via Xcode directly, is the normal path.)

### 3. Create the Xcode app project

1. In Xcode: File -> New -> Project -> iOS -> App. Interface: SwiftUI.
2. Delete the generated `ContentView.swift` and default `App.swift`.
3. Drag in all files from `mpv-ios-player/` (uncheck "Copy items if needed"
   is fine either way; check "Add to target").
4. Replace the generated `Info.plist` with `mpv-ios-player/Info.plist`, or
   merge its keys into your project's existing one.
5. File -> Add Package Dependencies -> Add Local... -> select the `MPVKit`
   folder.
6. Set deployment target to iOS 14.0+ (matches `Package.swift`).
7. Build & run on a physical device or simulator.

## Architecture notes / corrections made during development

- **No Metal render backend.** An earlier draft of this project assumed
  libmpv exposed a Metal render API type. It doesn't — `include/mpv/render.h`
  only defines `MPV_RENDER_API_TYPE_OPENGL` and a software renderer. mpv's
  own Metal usage on Apple platforms goes through Vulkan+MoltenVK inside an
  AppKit-only window path that doesn't run on iOS. This project instead uses
  **OpenGL ES via EAGL** — the path mpv upstream itself ships for iOS
  (`video/out/hwdec/hwdec_ios_gl.m`, meson's `ios-gl` feature), with
  VideoToolbox hardware frames imported zero-copy via
  `CVOpenGLESTextureCache`. See `MPVGLView.swift` and
  `buildscripts/README.md` for the full explanation.
- **No fontconfig.** libass and harfbuzz use their CoreText backends
  instead, matching how mpv itself is typically built for Apple platforms.
- **Static linking throughout**, merged into one XCFramework, since iOS App
  Store apps can't casually ship a collection of loose `.dylib`s the way
  Android apps ship `.so` files per-ABI.

## License note

mpv and its dependency stack are AGPL-3.0 licensed (exact terms depend on
which options are enabled at build time — see `buildscripts/scripts/ffmpeg.sh`,
which enables `--enable-gpl --enable-version3`). Distributing this app on the
App Store means complying with those licenses (e.g. providing corresponding
source, per how other GPL-licensed App Store apps like VLC handle it). This
is a licensing/legal consideration for you to review, not something this
codebase resolves on your behalf.
