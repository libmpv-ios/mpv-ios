---
id: 15-swift-package-manager-doesnt-propagate-a-binarytargets-heade
title: "Swift Package Manager doesn't propagate a binaryTarget's headers automatically"
sidebar_label: "15. Swift Package Manager doesn't propagate a binaryTarget's headers automatically"
sidebar_position: 15
---

## 15. Swift Package Manager doesn't propagate a binaryTarget's headers automatically

**What happened:** once the `Libmpv.xcframework` build itself was finally
green (see entry 13), the very next CI stage — building `MPVKit` as a
Swift package against that framework — failed immediately:
```
In file included from .../MPVKit/Sources/CMPV/cmpv_shim.c:1:
.../MPVKit/Sources/CMPV/include/cmpv_shim.h:4:10: fatal error: 'mpv/client.h' file not found
    4 | #include <mpv/client.h>
```

**Root cause:** `Package.swift` declares `CMPV` (a C target) with
`dependencies: ["Libmpv"]`, where `Libmpv` is the `.binaryTarget` wrapping
`Libmpv.xcframework`. This looks like it should be enough — and it is,
for *Swift* files that `import Libmpv` (see `MPVCore.swift` and others,
which work fine) — but it is **not** enough for a C target that reaches
for the framework's headers via a plain `#include`. This is a
well-documented Swift Package Manager limitation, not a mistake specific
to this project: multiple independent bug reports
(`swiftlang/swift-package-manager#7626`, a Swift Forums thread titled
exactly "Binary Target infer header search path", and several others)
describe the identical symptom against completely unrelated packages —
SPM does not automatically add a binary target's `Headers/` directory to
a dependent C/C++/Objective-C target's header search path, only to
Swift's module-based `import` resolution.

**Fix:** added explicit `cSettings: [.headerSearchPath(...)]` entries to
`CMPV`'s target definition in `Package.swift`, pointing directly at the
XCFramework's own internal per-platform `Headers/` folders. This
project's XCFramework (built by `buildscripts/scripts/mpv-ios.sh`)
produces exactly two platform-slice folders — a device slice
(`ios-arm64`) and a lipo-merged simulator fat-binary slice
(`ios-arm64_x86_64-simulator`), matching the plain-static-library
XCFramework layout documented in several third-party writeups on the
format. Both paths are listed unconditionally; whichever one doesn't
apply to the current build target is simply not found and ignored by the
compiler, so this doesn't need to vary per-platform in the manifest
itself.

**Lesson:** a working `import Libmpv` elsewhere in the same package
doesn't guarantee every target can see the underlying headers — Swift's
module-based import and a C target's raw `#include` resolve through
different mechanisms in SPM, and only one of them benefits automatically
from a binary target dependency. Worth checking specifically whether a
failing target is a C/Objective-C target reaching for headers directly,
versus a Swift target doing a module `import`, since the fix differs
completely between the two.
