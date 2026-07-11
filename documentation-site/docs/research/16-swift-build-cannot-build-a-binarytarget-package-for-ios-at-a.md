---
id: 16-swift-build-cannot-build-a-binarytarget-package-for-ios-at-a
title: "`swift build` cannot build a binaryTarget package for iOS at all"
sidebar_label: "16. swift build cannot build a binaryTarget package for iOS at all"
sidebar_position: 16
---

## 16. `swift build` cannot build a binaryTarget package for iOS at all

**What happened:** after entry 15's header-search-path fix, CI still
failed with the exact same `'mpv/client.h' file not found` error — but
now preceded by a very different-looking warning that hadn't been
investigated yet:
```
<unknown>:0: warning: using sysroot for 'MacOSX' but targeting 'iPhone'
```
This warning appeared on *every* file compiled, immediately suggesting
the header-search-path fix from entry 15 wasn't the (only) issue — the
compiler itself seemed to be using the wrong SDK entirely, regardless of
what path was configured.

**Root cause:** this build was invoked as
`swift build -Xswiftc -sdk ... -Xswiftc -target arm64-apple-ios17.0-simulator`.
It turns out this specific approach — driving a cross-platform build of a
`.binaryTarget`-dependent package via the plain `swift build` CLI, using
`-Xswiftc`/`-Xcc` flags to redirect the SDK/target — has a real, upstream
limitation, not something fixable by adjusting those flags further:
SwiftPM's own binary-target-resolution code only recognized a `"macos"`
platform string when matching an XCFramework slice to build against (see
`swift-package-manager` issue #6571, which describes the identical
symptom against a completely unrelated XCFramework dependency). There was
no `ios`/`ios-simulator` case in that mapping at all as of that issue —
meaning `swift build` was always going to reach for a macOS slice of
`Libmpv.xcframework` internally, no matter what SDK/target was passed to
the Swift compiler frontend via `-Xswiftc`. The "using sysroot for
'MacOSX'" warning was this happening in practice, and the cascading
header "file not found" errors were a direct consequence (the wrong
sysroot can't see the iOS-slice headers entry 15's fix pointed at,
because the build wasn't actually targeting that slice).

**Fix:** replaced both `swift build -Xswiftc ...` invocations in
`build.yml`'s `swift-package-build` job with `xcodebuild build -scheme
MPVKit -destination "generic/platform=iOS Simulator"` (and the
device-platform equivalent). Modern Xcode can treat a bare
`Package.swift` directory as an implicit project without needing
`swift package generate-xcodeproj` (long deprecated) or any checked-in
`.xcodeproj` — `xcodebuild`, unlike the plain SwiftPM CLI, has always
correctly resolved XCFrameworks per-platform, which is also why this
project's actual app target (`mpv-ios-player`, via `project.yml` +
`appetize-preview.yml`) was never affected by this — it was always built
with `xcodebuild`, never `swift build` directly.

**Lesson:** when two different tools exist for nominally the same job
(here, `swift build` and `xcodebuild`, both able to "build a Swift
package"), and a package depends on something platform-specific like an
XCFramework binary target, it's worth checking whether both tools
actually support that dependency equally — they don't always, and the
failure mode when they don't can look like a header/path configuration
problem (entry 15's territory) rather than what it actually is: an
entire code path in one tool never being wired up for the platform being
targeted at all.
