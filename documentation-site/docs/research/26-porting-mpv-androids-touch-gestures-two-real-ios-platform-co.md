---
id: 26-porting-mpv-androids-touch-gestures-two-real-ios-platform-co
title: "Porting mpv-android's touch gestures: two real iOS platform constraints, not bugs"
sidebar_label: "26. Porting mpv-android's touch gestures: two real iOS platform constraints, not bugs"
sidebar_position: 27
---

## 26. Porting mpv-android's touch gestures: two real iOS platform constraints, not bugs

**What was ported:** mpv-android's `TouchGestures.kt` state machine (swipe
seek/volume/brightness, tap-left/tap-right/tap-center gestures, the
deadzone/throttling/tap-timing constants) and the corresponding handling
in `MPVActivity.kt`'s `onPropertyChange`, as a new headless
`MPVTouchGestures` class in `MPVKit` plus gesture-handling logic in
`PlayerViewModel`. The state machine itself (touch-down/move/up,
Control-state transitions, tap-region math) ports directly with no
behavioral differences - it has no Android-specific dependency to begin
with. Two real platform differences turned up in the *observer* side
(the `onPropertyChange`-equivalent logic), both confirmed by checking
current documentation/API behavior rather than assumed:

**1. iOS apps cannot set system volume programmatically.**
mpv-android's volume gesture calls `AudioManager.setStreamVolume()`
directly on the system audio stream. iOS has no equivalent: an app can
*read* `AVAudioSession.sharedInstance().outputVolume`, but cannot set
it - the only way to change system volume from app code at all is
indirectly, by manipulating the hidden slider inside an `MPVolumeView`,
which still requires that view to exist in the hierarchy and is a
workaround rather than a supported direct-set API. `outputVolume` is
also documented (multiple current Apple Developer Forums threads, iOS
18) as unreliable for *reading* the current value in several
situations - stale after backgrounding, reports 0 immediately after
audio session activation. Given both constraints, the ported gesture
adjusts mpv's own in-app `volume` property (0-100) instead of system
volume. This is a permanent, deliberate platform difference from
mpv-android, not a stand-in for a "real" fix.

**2. `UIScreen.main.brightness` doesn't persist past a lock.**
Still the current, non-deprecated API for reading/setting app-level
screen brightness (confirmed directly, not assumed, given how easy
brightness APIs are to get wrong across iOS versions). Unlike Android's
`WindowManager.LayoutParams.screenBrightness` (which mpv-android's
`updateScreenBrightness()` sets and which persists for the Activity's
lifetime), a brightness set via `UIScreen.main.brightness` reverts to
the user's actual system brightness setting the next time the device
unlocks. Not a bug to work around - just a real behavior difference
worth knowing about so it isn't mistaken for the gesture code failing to
"stick."

**Design choice carried over intentionally:** `MPVTouchGestures` has zero
UIKit/SwiftUI/mpv dependency, matching `TouchGestures.kt`'s own
separation from `MPVActivity` - it only computes state-machine
transitions and reports `MPVPropertyChange` cases through a delegate
protocol (`MPVGestureObserver`), the same division of responsibility as
the Kotlin original's `TouchGesturesObserver` interface. `PlayerViewModel`
plays the role `MPVActivity.kt`'s `onPropertyChange` override plays:
translating an abstract property-change event into concrete seek/volume/
brightness/pause actions.

**Verified before writing, not assumed:**
- `MPVCore`/`MPVPlayer`'s actual public API (`core.seek(to:)`,
  `core.volume`, `core.isPaused`, `core.command(_:)`) was checked
  directly against `MPVPlayer.swift` rather than guessed from the
  gesture code's needs - an earlier draft used a nonexistent
  `core.timePos` setter before this check caught it.
- `MPVCoreDelegate`'s existing `nonisolated func mpv(...)` conformance
  pattern in `PlayerViewModel` was checked and matched exactly for the
  new `MPVGestureObserver` conformance, rather than introducing a
  different (and potentially actor-isolation-incompatible) pattern for
  gesture callbacks specifically.
- The two-parameter `onChange(of:) { oldValue, newValue in }` SwiftUI
  API is iOS 17+ only (confirmed via search) - this project's
  `MPVIOSPlayer` app target deployment target is 16.0 (see entry 22), so
  the single-parameter `onChange(of:perform:)` form was used instead.
  Using the newer form here would have reintroduced exactly the kind of
  deployment-target/API-availability mismatch entry 22 already had to
  fix once.

**Lesson:** porting a state machine that has no platform dependency is
mechanical and low-risk; porting the *handler* that reacts to it is
where the real platform differences live, and claiming a platform
constraint exists (e.g. "iOS has no way to read current volume") without
checking current documentation is itself a risk - the accurate claim
here ("no way to *set* it silently, and *reading* it is documented as
unreliable in specific situations") is more precise and more useful than
a vaguer, unverified version of the same point would have been.
