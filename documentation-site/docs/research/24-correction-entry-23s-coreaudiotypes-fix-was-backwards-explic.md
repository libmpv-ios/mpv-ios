---
id: 24-correction-entry-23s-coreaudiotypes-fix-was-backwards-explic
title: "Correction: entry 23's `CoreAudioTypes` fix was backwards — explicitly linking it turns a harmless warning into a fatal error"
sidebar_label: "24. Correction: entry 23's `CoreAudioTypes` fix was backwards — explicitly linking it turns a harmless warning into a fatal error"
sidebar_position: 25
---

## 24. Correction: entry 23's `CoreAudioTypes` fix was backwards — explicitly linking it turns a harmless warning into a fatal error

**What happened:** entry 23 treated `ld: warning: Could not find or use
auto-linked framework 'CoreAudioTypes': framework 'CoreAudioTypes' not
found` as something to fix, and added `.linkedFramework("CoreAudioTypes")`
to `MPVKit/Package.swift` alongside the other real framework fixes in that
entry. The next CI run got further — past `MPVKit` compiling, past `CMPV`
linking, all the way to the actual app binary link step
(`Ld .../MPVIOSPlayer.debug.dylib`) — and failed there with:
```
ld: framework 'CoreAudioTypes' not found
clang: error: linker command failed with exit code 1 (use -v to see invocation)
```
No longer a warning — a hard, fatal link error, and a new failure point
(the app-level `Ld` step) that hadn't been reached before.

**Investigation:** a web search for the exact original warning text
turned up several unrelated reports of the same message (a
realm-swift GitHub issue, multiple Apple Developer Forums threads about
SwiftUI Previews, a Google Mobile Ads SDK support thread, a CocoaPods
issue) and they converge on the opposite conclusion from what entry 23
assumed. Directly relevant: a Realm engineer's own diagnosis reads
"CoreAudioTypes is default Framework for iOS" - i.e. implicitly present
already - and a related report states plainly: "Because CoreAudioTypes
is default Framework for iOS, so you don't need import it into your
project. Remove CoreAudioTypes from frameworks, libraries, and embedded
Content." One Apple Developer Forums participant summarized it as: "My
app does not use 'CoreAudioTypes'. From what I see, this error message
obscures the actual issue in a build" - matching entry 23's own original
read of it as a red herring riding alongside a real, separate
undefined-symbol error. `CoreAudioTypes` on iOS is a header-only
umbrella living inside `CoreAudio`, not a separately-shipped linkable
framework binary - so `.linkedFramework("CoreAudioTypes")` asks the
linker for a `CoreAudioTypes.framework` that plainly doesn't exist as a
standalone file, which is a hard requirement failure, whereas Xcode's
own auto-linker only *warns* when its inference reaches the same
nonexistent target and then continues past it.

**Actual fix:** removed `.linkedFramework("CoreAudioTypes")` from
`MPVKit/Package.swift`'s `linkerSettings` entirely, leaving
`AVFoundation`, `AudioToolbox`, `CoreAudio`, `VideoToolbox`, and
`CoreMedia` (all genuinely real, separately-linkable frameworks that
mpv/ffmpeg's enabled build options actually need) in place.

**Lesson:** a linker *warning* about a missing framework and a linker
*error* about a missing framework are not the same problem with
different severities - sometimes the warning is Xcode's auto-linker
reaching for something that was never meant to be linked directly in the
first place, and forcing the explicit link doesn't satisfy the warning,
it manufactures a new failure mode that didn't exist before. The
"symptom vs. cause" distinction entry 23 already drew for `SwiftUICore`
(a restricted framework that legitimately cannot be linked directly, and
needed no fix) should have been applied identically to `CoreAudioTypes`
appearing in the very same warning line - both were auto-link inference
artifacts, not real missing dependencies, and only one of the two got
treated that way the first time around. When a fix for one part of a
multi-symptom error log is applied, re-running to confirm progress
(rather than assuming every line in the original log needed its own
fix) is what surfaced this - the build got measurably further, which is
useful signal, but the exact new failure text needs the same scrutiny as
the original rather than assuming the round of fixes was complete.
