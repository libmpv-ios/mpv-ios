---
id: 32-a-real-compile-error-shipped-in-earlier-work-objc-selector-o
title: "A real compile error shipped in earlier work: `@objc`/`#selector` on plain Swift classes, found while wiring up persisted playback position"
sidebar_label: "32. A real compile error shipped in earlier work: `@objc`/`#selector` on plain Swift classes, found while wiring up persisted playback position"
sidebar_position: 33
---

## 32. A real compile error shipped in earlier work: `@objc`/`#selector` on plain Swift classes, found while wiring up persisted playback position

**What was added:** playback-position persistence
(`MPVCore.writeWatchLaterConfig()`/`deleteWatchLaterConfig()`, built on
mpv's own built-in watch-later mechanism rather than a custom
save/restore implementation — matching mpv-android's own choice to lean
on mpv's built-in system, and its `savePosition()`'s `eof-reached` check
to avoid resuming a just-finished file at its own ending), wired into
`PlayerViewModel.stop()` and an app-backgrounding observer.

**While adding that backgrounding observer, a genuine compile-breaking
mistake was found in code from an earlier session — not new code, code
already presented as finished.** `MediaSessionManager` (entry 27) uses
`NotificationCenter.default.addObserver(self, selector:
#selector(handleInterruption(_:)), ...)` for its interruption/route-
change handling. `@objc`-exposed methods and `#selector` both require
the containing type to inherit from `NSObject` — `MediaSessionManager`
is declared `public final class MediaSessionManager` with no such
inheritance, matching this codebase's general preference for plain
Swift coordinator types (see `PictureInPictureCoordinator`'s docs on
the same point). This would not have been a subtle runtime bug; it's a
straightforward compile error, sitting in code that had already been
written, reasoned about at length, and presented as complete in a prior
turn.

**The fix surfaced a second, non-obvious issue**: switching to the
block-based `addObserver(forName:object:queue:using:)` API (which needs
no `@objc`/`NSObject`) doesn't fully resolve things on its own, because
both `MediaSessionManager` and `PlayerViewModel` are `@MainActor`-
isolated types. `queue: .main` guarantees the closure runs on the main
thread at runtime, but a plain closure's *static* isolation is still
`nonisolated` to the type system — referencing `self` from inside it
still triggers a Swift concurrency error, confirmed against a matching
Apple Developer Forums report of the exact same "`@MainActor` type +
`addObserver`/`addTarget` closure" combination failing for another
developer. `MainActor.assumeIsolated { }` around the closure body is
the documented resolution for exactly this situation (asserting at
runtime what `queue: .main` already guarantees, without making every
call site `async`) — applied to every affected closure:
`MediaSessionManager`'s two `NotificationCenter` observers, all eight of
its `MPRemoteCommand.addTarget` handlers, and `PlayerViewModel`'s new
backgrounding observer. `PictureInPictureCoordinator`'s
`AVPictureInPictureControllerDelegate`/
`AVPictureInPictureSampleBufferPlaybackDelegate` conformances were
audited for the same risk and left as-is with a comment explaining why
(Apple's own system-framework delegate protocols are expected to be
annotated for exactly this `@MainActor`-conforming-type case) and what
to do if a real build disagrees — this project has no way to verify by
actually compiling, so the honest record is "audited and reasoned
through, not confirmed by a build."

**Lesson, stated plainly:** presenting code as finished in an earlier
turn is not the same as it being correct, and a mistake doesn't become
harder to find just because it shipped a while ago — the same
disciplined checking applied to brand-new code needs to extend to
re-examining prior work when a closely related pattern comes up again
(here, writing a *second* NotificationCenter observer was what
prompted noticing the first one was broken). A `grep` across the whole
project for the broken pattern (`@objc`/`#selector`) after fixing the
two known instances confirmed no third occurrence was hiding elsewhere
— worth doing that sweep rather than assuming the two found instances
were the only ones, once a pattern is known to be wrong.
