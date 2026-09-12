---
id: 22-project-ymls-app-target-was-pinned-to-ios-14-0-while-its-own
title: "`project.yml`'s app target was pinned to iOS 14.0 while its own code required iOS 16.0"
sidebar_label: "22. `project.yml`'s app target was pinned to iOS 14.0 while its own code required iOS 16.0"
sidebar_position: 23
---

## 22. `project.yml`'s app target was pinned to iOS 14.0 while its own code required iOS 16.0

**What happened:** with `project.yml` newly in place (it had been
missing from the repo entirely, despite being referenced by
`.github/workflows/appetize-preview.yml` and documented in the README's
tree diagram — see that fix for the full context) and entry 21's fix
landed, CI progressed much further — through `MPVKit` compiling cleanly —
before failing at `mpv-ios-player`'s own files:
```
'dismiss' is only available in iOS 15.0 or newer
    @Environment(\.dismiss) private var dismiss
                   ^
...
Process completed with exit code 65.
```
The build log's warnings (an `extension URL: Identifiable` Foundation
conformance-collision warning, deprecation notices already understood
from entry 1) were easy to mistake for the actual failure at a glance,
but the real error — an iOS-version-gated API used below the deployment
target — was the `@Environment(\.dismiss)` line.

**Investigation:** `project.yml` set both the project-wide
`options.deploymentTarget.iOS` and the `MPVIOSPlayer` app target's own
`deploymentTarget` to `"14.0"`, matching `MPVKit`'s `Package.swift`
(`.iOS(.v14)`) and the README's documented "iOS 14.0+" for the *library*.
But `deploymentTarget` in `project.yml` was written by inference from
`Package.swift`/README, without first grepping the example app's own
source for which SwiftUI APIs it actually calls. A search of
`mpv-ios-player/*.swift` for version-gated APIs turned up two, both used
unconditionally (no `@available` guard, no `if #available` branch):
`NavigationStack` (`MPVRootView.swift`, `TrackSelectionSheet.swift` — iOS
16+) and `@Environment(\.dismiss)` (`TrackSelectionSheet.swift` — iOS
15+). `NavigationStack` being iOS 16+ makes 16.0 the actual floor this
code already requires, regardless of what the library or the README's
setup instructions state.

**Actual fix:** raised only the `MPVIOSPlayer` app target's
`deploymentTarget` (and its `IPHONEOS_DEPLOYMENT_TARGET` build setting)
to `"16.0"` in `project.yml`, leaving `options.deploymentTarget.iOS` and
`MPVKit`'s own `Package.swift` minimum at `14.0` untouched — the library
itself doesn't use any of the offending APIs and has no reason to have
its stated floor changed. The alternative (rewriting
`TrackSelectionSheet.swift`/`MPVRootView.swift` to use `NavigationView`
and an iOS-14-compatible dismiss pattern instead) would keep the example
app's minimum at parity with the library, but was not the fix applied
here since it touches app logic rather than build configuration for what
is, for now, a genuine version mismatch between two files that were
authored under different assumptions.

**Lesson:** a deployment target set from a library's documented minimum
(`Package.swift`, README setup steps) is not automatically correct for
every target that depends on that library — an app target's real minimum
is set by the newest API its own source actually calls, and needs
checking directly (grep for `@available`, `NavigationStack`,
`.dismiss`/`.presentationDetents`/other version-gated SwiftUI additions,
etc.) rather than inherited by assumption from whatever the library
underneath happens to support. This is easy to miss specifically because
the mismatch only surfaces as a compile error, not a `project.yml`
validation error — `xcodegen generate` succeeds either way, since it has
no way to know what APIs the source files it's pointed at will end up
calling.
