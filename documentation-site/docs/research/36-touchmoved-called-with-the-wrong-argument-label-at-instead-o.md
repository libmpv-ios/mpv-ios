---
id: 36-touchmoved-called-with-the-wrong-argument-label-at-instead-o
title: "`touchMoved` called with the wrong argument label: `at:` instead of `to:`"
sidebar_label: "36. `touchMoved` called with the wrong argument label: `at:` instead of `to:`"
sidebar_position: 37
---

## 36. `touchMoved` called with the wrong argument label: `at:` instead of `to:`

**What happened:** CI failed while building `MPVIOSPlayer` for the iOS
Simulator with:
```
error: incorrect argument label in call (have 'at:', expected 'to:')
    if viewModel.touchGestures.touchMoved(at: value.location) {
```
`MPVTouchGestures` (added in entry #26) declares three touch-forwarding
methods: `touchDown(at:)`, `touchMoved(to:)`, and `touchUp(at:)` — two of
the three use `at:`, but `touchMoved` uses `to:`. `MPVPlayerView`'s
`DragGesture` handler calls all three from the same `onChanged`/`onEnded`
closures, and the `touchMoved` call site was written with the same `at:`
label as its neighbors rather than the label the method actually
declares.

**Actual fix:** changed the call site in `MPVPlayerView.swift` from
`touchGestures.touchMoved(at: value.location)` to
`touchGestures.touchMoved(to: value.location)`, matching
`MPVTouchGestures.swift`'s existing declaration. The method's own
signature was left as-is: `touchDown`/`touchUp` model a point the touch
*is at*, while `touchMoved` models a point the touch *moved to* — the
inconsistency is a pre-existing naming choice in the gesture API, not a
bug, so the fix corrects the caller rather than renaming the API and
risking other callers or future ports (e.g. mpv-android parity) expecting
`to:`.

**Verification:** confirmed via the actual CI failure log rather than
inspection alone, then grepped `mpv-ios-player/` and `MPVKit/` for every
call site of `touchDown`, `touchMoved`, and `touchUp` to check no other
call used the wrong label — `MPVPlayerView.swift`'s single `touchMoved`
call was the only mismatch; `touchDown(at:)` and `touchUp(at:)` were
already correct.

**Lesson:** a set of sibling methods that are mostly-but-not-entirely
consistent in argument-label naming is an easy trap when writing a call
site by pattern-matching neighboring lines rather than checking each
method's actual signature — the compiler catches it immediately here
(Swift argument labels are part of the function's type), but the same
copy-neighboring-line habit could silently pick the wrong *value* instead
of just the wrong *label* in a language without that guarantee. Worth a
quick grep for a method's declaration before calling it in a block that
already calls two or three of its close siblings.
