---
id: 33-stats-overlay-an-initial-this-property-doesnt-exist-conclusi
title: "Stats overlay: an initial \"this property doesn't exist\" conclusion was wrong, caught by reading mpv's C source instead of stopping at input.rst"
sidebar_label: "33. Stats overlay: an initial \"this property doesn't exist\" conclusion was wrong, caught by reading mpv's C source instead of stopping at input.rst"
sidebar_position: 34
---

## 33. Stats overlay: an initial "this property doesn't exist" conclusion was wrong, caught by reading mpv's C source instead of stopping at input.rst

**What was added:** `MPVCore.PlaybackStats`/`currentStats()` (codec,
resolution, fps, hwdec, bitrate, A/V sync, dropped frames, cache state)
and a `StatsOverlay` SwiftUI view polling it once per second while
visible — equivalent in spirit to mpv-android's `updateStats()`, though
mpv-android's own version only ever surfaces FPS; this implementation's
scope is closer to mpv's own `stats.lua` OSD script.

**A wrong conclusion, caught before it shipped by going one layer
deeper than the usual source.** An initial `grep` across `input.rst`
for "video-codec"/"audio-codec" turned up nothing, leading to a first
draft that assumed these properties simply don't exist and worked
around it by manually cross-referencing `track-list`'s entries against
the currently-selected `vid`/`aid` track ids instead. That conclusion
was wrong. Checking mpv's own C source (`player/command.c`) — a step
this project doesn't normally need, since `input.rst` is usually
authoritative and sufficient — turned up
`M_PROPERTY_ALIAS("video-codec", "current-tracks/video/codec-desc")`
and its `audio-codec` counterpart: both properties are real, just
implemented as property *aliases* rather than being independently
documented as top-level properties in the section of `input.rst` the
first search covered. The simpler, correct implementation
(`getPropertyString("video-codec")` directly) replaced the manual
track-list cross-referencing entirely once this was found.

**A second, more consequential mistake from the same round of
guessing: assuming `video-bitrate` was a DOUBLE property.** Nothing
about the property's docstring states its type either way, and "a
bitrate" reads intuitively as a fractional value. mpv's own source
settled it unambiguously: `mp_property_packet_bitrate` computes an
internal `double` but returns it via `m_property_int64_ro`, i.e. the
value is rounded and exposed as INT64 at the client-API boundary. This
would not have been a cosmetic bug — mpv's client API refuses a
property read requested in the wrong format rather than silently
converting, so calling `getPropertyDouble` (this codebase's existing,
correctly-typed helper for genuinely double-typed properties) against
an INT64 property returns `nil` unconditionally. Every bitrate reading
in the stats overlay would have silently shown as absent, with nothing
in the UI or logs pointing at why. Checked and fixed to
`getPropertyInt`, with the bits-per-second-to-kilobits conversion moved
to happen in `Double` *after* the correctly-typed read rather than
during it.

**One property's type could not be fully settled and is flagged as
such rather than guessed with false confidence.** `container-fps` is
implemented internally as a C `float` (`CONF_TYPE_FLOAT`), a third
distinct type from both `int64` and `double` at the C level — but mpv's
client API only defines `MPV_FORMAT_INT64`/`MPV_FORMAT_DOUBLE` for
numeric properties (no float format exists at that boundary), so
`float`s are necessarily promoted to `double` when read from client
code. `getPropertyDouble` is used on that reasoning, documented
in-code as reasoning rather than a confirmed on-device result — this
environment has no way to compile and run the project to check
directly, and a wrong guess here fails safe (a `nil` reading, not a
crash or bad value), which is why this one specific property was
flagged rather than silently assumed correct alongside the others that
were fully verified.

**Lesson:** "grep the manual and get zero results" is evidence the
manual doesn't document something *at that exact name, in that exact
section* — it is not equivalent to "this doesn't exist," and property
aliases are exactly the gap between those two claims. When a
conclusion drawn from documentation search leads to visibly more
complex code than expected (here: manually cross-referencing
`track-list` against selected track ids, instead of reading one
property), that complexity gap is itself worth treating as a signal to
check a level deeper — in this case, the actual property-registration
table in mpv's own source — before accepting the conclusion.
