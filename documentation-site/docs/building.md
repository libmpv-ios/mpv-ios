---
id: building
title: Building the Project
sidebar_position: 1
---

# Building mpv-ios

## Requirements

- **macOS** — Xcode's toolchain (codesigning, SDKs) only runs on macOS.
  GitHub Actions' `macos-14` runner satisfies this if you don't own a Mac
  yourself — see [Testing without a Mac](./testing-without-a-mac.md).
- Xcode + Command Line Tools: `xcode-select --install`
- Homebrew packages:

```bash
brew install meson ninja pkg-config gnu-sed nasm autoconf automake libtool coreutils
```

- `git`, `curl` (both ship with macOS)

## Step 1 — Build libmpv for iOS

```bash
cd buildscripts
./download.sh
./buildall.sh --all-platforms
cd ..
./buildscripts/scripts/mpv-ios.sh build
```

This produces `Libmpv.xcframework` at the repo root. See the
[Engineering Notes](./research/index.md) for the full history of
version-drift and cross-compilation issues this pipeline has been
debugged against — most future build failures will resemble one of
those.

## Step 2 — Wire it into MPVKit

```bash
mkdir -p MPVKit/Frameworks
cp -R Libmpv.xcframework MPVKit/Frameworks/
```

Verify the package builds. **Use `xcodebuild`, not `swift build`** — a
Swift Package Manager limitation prevents `swift build` from resolving
a `.binaryTarget` (XCFramework) dependency for iOS at all (see Research
Log entry 16 for the full story):

```bash
cd MPVKit
xcodebuild build -scheme MPVKit -destination "generic/platform=iOS Simulator"
```

## Step 3 — Create the Xcode app project

1. In Xcode: File → New → Project → iOS → App. Interface: SwiftUI.
2. Delete the generated `ContentView.swift` and default `App.swift`.
3. Drag in all files from `mpv-ios-player/` (check "Add to target").
4. Replace the generated `Info.plist` with `mpv-ios-player/Info.plist`,
   or merge its keys into your project's existing one.
5. File → Add Package Dependencies → Add Local... → select the `MPVKit`
   folder.
6. Set deployment target to iOS 15.0+ (matches `project.yml`).
7. Build & run on a physical device or simulator.

Alternatively, generate the project directly with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) using the checked-in
`project.yml`:

```bash
brew install xcodegen
xcodegen generate --spec project.yml
```

## Architecture notes

A few design decisions are worth understanding before touching the
render or audio pipeline — see [Architecture](./architecture.md) for
the full write-up (no Metal render backend, no fontconfig, static
linking throughout, and the mpv source patches applied before building).

## License note

mpv and its dependency stack are GPL/LGPL-licensed (exact terms depend on
which options are enabled at build time). Distributing this app means
complying with those licenses — this is a licensing/legal consideration
for you to review, not something this codebase resolves on your behalf.
