---
id: 34-orientation-lock-swiftui-has-no-hook-for-this-at-all-and-the
title: "Orientation lock: SwiftUI has no hook for this at all, and the API that does exist is documented-broken on the exact iOS version this project targets"
sidebar_label: "34. Orientation lock: SwiftUI has no hook for this at all, and the API that does exist is documented-broken on the exact iOS version this project targets"
sidebar_position: 35
---

## 34. Orientation lock: SwiftUI has no hook for this at all, and the API that does exist is documented-broken on the exact iOS version this project targets

**What was added:** `OrientationLockController` (auto/landscape/
portrait/unlocked modes, matching mpv-android's `cycleOrientation()`/
`updateOrientation()`), a new minimal `AppDelegate` wired in via
`@UIApplicationDelegateAdaptor`, and a tap-cycles/long-press-picks
orientation control in `MPVPlayerView`'s top bar.

**This is the one feature in this whole project that required adding
new app-lifecycle infrastructure (an `AppDelegate`) specifically
because SwiftUI's own `App` protocol has no equivalent hook at all** —
confirmed across every source consulted on this topic, not just one:
`application(_:supportedInterfaceOrientationsFor:)` is only ever called
on a `UIApplicationDelegate`, full stop. A separate source
(a Medium writeup specifically about SwiftUI orientation locking)
documented having tried the obvious SwiftUI-native-feeling workarounds
first — `windowScene?.effectiveGeometry.setValue(true, forKey:
"isInterfaceOrientationLocked")` and equivalent KVC calls on
`rootViewController` — and reported both **crash** with "this class is
not key value coding-compliant for the key ...". That's a materially
different situation from most of this project's other iOS-API
research, where the question was "which of several working approaches
is correct" — here, most of the approaches that don't involve adding an
`AppDelegate` don't work at all.

**The API that does exist is separately reported broken on iOS 16
specifically, in an Apple Developer Forums thread from an Apple
context** (not a random blog): `application:supportedInterfaceOrientationsForWindow:`
"does not lock the orientation" on iOS 16, changing orientation before
asking the delegate rather than after, backwards from its own
documented sequencing — with multiple independent forum replies
confirming the same symptom, not one isolated report. The **working**
combination synthesized from several forum threads describing the same
migration is: `UIWindowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))`
(the iOS 16+ replacement for directly setting device orientation) paired
with `UIViewController.setNeedsUpdateOfSupportedInterfaceOrientations()`
on the current root view controller, so the delegate's
`supportedInterfaceOrientationsFor:` gets explicitly re-queried rather
than relying on whatever the (reportedly broken) automatic re-check
does. `OrientationLockController.applyChange()` calls both, in that
order, specifically because no single source described only one of
them as sufficient.

**Design choices carried over from mpv-android, and one deliberately
not:** the auto-mode aspect-ratio threshold (treating near-square video
as "let the system rotate freely" rather than force-locking) mirrors
mpv-android's own `ASPECT_RATIO_MIN`-gated behavior in
`updateOrientation()`, though the specific numeric threshold (1.2) is
this project's own choice, not a value read out of mpv-android's
source — recorded as such rather than implied to be a ported constant.
`cycleOrientation()` mirrors mpv-android's exactly (a two-state
landscape/portrait toggle, not a cycle through all four `Mode` cases) —
mpv-android's own cycle button never reaches its `auto`/unspecified
state, that's only reachable from its separate settings screen, and
this project's tap-cycles/long-press-for-full-picker control preserves
that same split (tap = the two-state toggle, long-press = all four
modes) rather than inventing a different interaction model.

**Lesson:** when *every* source consulted on a topic converges on "the
direct/obvious way doesn't exist for this UI framework" and "the
documented replacement API is itself reported broken on the exact OS
version in question," that's a meaningfully different research
situation from the usual "which approach is correct" question this
project has faced for most other features — it calls for synthesizing
a specific combination from multiple problem-reports and their
replies (not just one canonical doc page), and for being explicit in
the resulting code and commit history about which parts of that
combination came from which specific report, since no single source
described the whole working solution end to end.
