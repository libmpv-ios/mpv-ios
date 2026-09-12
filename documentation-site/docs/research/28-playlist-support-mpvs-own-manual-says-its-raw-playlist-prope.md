---
id: 28-playlist-support-mpvs-own-manual-says-its-raw-playlist-prope
title: "Playlist support: mpv's own manual says its raw playlist property is \"useless,\" and one playlist command still ships with no change notification"
sidebar_label: "28. Playlist support: mpv's own manual says its raw playlist property is \"useless,\" and one playlist command still ships with no change notification"
sidebar_position: 29
---

## 28. Playlist support: mpv's own manual says its raw playlist property is "useless," and one playlist command still ships with no change notification

**What was added:** playlist read/write support in `MPVPlayer.swift`
(`loadFile`/`addToPlaylist`/`playlistNext`/`playlistPrev`/
`playlistPlay`/`playlistRemove`/`playlistMove`/`playlistClear`/
`playlistShuffle`/`playlistItems()`), wired into `PlayerViewModel`,
Control Center next/previous-track commands, and a new `PlaylistSheet`
UI. Two findings here are worth keeping in mind for any future code
that touches mpv's playlist:

**1. The `playlist` property cannot be read the way every other
observed property in this codebase is read.** `input.rst` states this
directly: "currently, the raw property value is useless." It's an
`MPV_FORMAT_NODE`, and this codebase's property-event mapping
(`MPVCore.swift`'s `mapEvent`) only decodes flag/int64/double/string —
anything else falls through to `.none`. The fix used here isn't a new
NODE decoder; it's the same pattern `trackList()` already established
for `track-list` in this file: query the documented per-entry
sub-properties individually (`playlist/N/filename`, `/title`,
`/current`, `/playing`) using getters this codebase already has working.
`playlist/N/playing` was used for the "is this the active entry" flag
rather than `playlist/N/current` — IINA's own scripting API documents
`isCurrent` as deprecated in favor of `isPlaying` for exactly this kind
of check, and mpv's manual separately describes `playlist-current-pos`
as only "vaguely useful," which reads as the same underlying
distinction from the mpv side.

**2. `playlist-move` fires no property-change notification at all**,
confirmed via a still-open mpv issue (#7339) — every other
playlist-mutating command in this codebase's wrapper (`playlist-remove`,
`loadfile ... append`, `playlist-clear`, `playlist-shuffle`) does notify
via `playlist-count`/`playlist-pos`, which is why `PlayerViewModel`
mostly relies on observing those two properties rather than refreshing
after every single call. `playlistMove`'s call site is the one
exception: it refreshes explicitly, immediately after the command,
because trusting the observer there would leave `playlist` silently
stale after every reorder. (A related, older, already-fixed bug is also
worth noting for anyone who finds outdated advice while researching
this: `playlist-count` itself had unreliable change notifications on
append/remove prior to mpv 0.17.0 per mpv issue #3267 — long since fixed
upstream, and this project tracks mpv's master branch, but a search on
this topic surfaces plenty of pre-fix discussion that no longer applies
here.)

**3. `append-play` is deprecated in favor of `append+play`** per
`input.rst`'s own note (deprecated since mpv 0.42) — `loadFile`'s
`MPVLoadMode` enum uses the current combinable-flag form as the
default, keeping the deprecated single-token spelling only as a
documented-but-unused case for reference.

**4. `ContentUnavailableView` (used in an early draft of `PlaylistSheet`
for the empty-playlist state) is iOS 17.0+ only** — caught before it
shipped, same category of deployment-target mismatch as entry 26/27's
`onChange(of:)` issue, just a different API. Replaced with a plain
`VStack`-based empty state, consistent with this project's iOS 16.0
deployment target (`project.yml`).

**Lesson:** "the property doesn't decode the way I expected" and "the
mutating command doesn't notify the way every other one does" are both
the kind of behavior that's easy to miss by testing happy-path append/
remove and assuming reorder works the same way — neither surfaces as a
compile error or an obvious crash, only as UI that silently goes stale
after one specific user action. Worth specifically checking, for any
mpv command being wrapped for the first time, whether its own manual
entry documents anything unusual about its change-notification
behavior, rather than assuming all mutating commands in the same
command family behave identically.
