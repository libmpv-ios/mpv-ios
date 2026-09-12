---
id: 29-decoder-selection-a-scary-looking-mpv-crash-report-turned-ou
title: "Decoder selection: a scary-looking mpv crash report turned out not to apply here, but only after actually reading which backend it named"
sidebar_label: "29. Decoder selection: a scary-looking mpv crash report turned out not to apply here, but only after actually reading which backend it named"
sidebar_position: 30
---

## 29. Decoder selection: a scary-looking mpv crash report turned out not to apply here, but only after actually reading which backend it named

**What was added:** runtime hardware/software decoder switching
(`MPVCore.DecoderOption`, `setDecoder(_:)`, `currentDecoder()`), a
decoder picker section added to the existing `TrackSelectionSheet`, and
`hwdec-current` property observation feeding
`PlayerViewModel.currentDecoder`.

**The first search result for "change hwdec at runtime" was a mpv
crash report — worth recording exactly why it didn't block this
implementation, rather than either ignoring it or over-reacting to it.**
mpv issue #3788 documents a real, reproducible crash from cycling
`hwdec` between `no` and `auto-copy` at runtime. Two details in that
report matter more than its headline: it's from 2016 (mpv predates
much of its current property-notification infrastructure — see entry
28's note on `playlist-count`'s own since-fixed 2016-era bug for the
same general vintage of issue), and it's specific to the **vdpau**
backend (`Assertion '!ctx->hwdec_priv' failed` inside vdpau's own probe
path) — a Linux/NVIDIA-only decode API this project's iOS build doesn't
compile in at all (`buildscripts/scripts/mpv.sh` only enables `ios-gl`).
Neither detail rules out some other VideoToolbox-specific instability by
itself, but they do mean this specific report isn't evidence against
this specific implementation.

**What did settle it: checking whether an already-shipping player does
this the simple way.** mpv-android's `pickDecoder()`
(`MPVActivity.kt`) calls `MPVLib.setPropertyString("hwdec", ...)`
directly, with no reload/restart/pause-and-resume dance beyond pausing
its own picker dialog UI — and has done so in production for years for
mediacodec, VideoToolbox's closest Android equivalent in terms of "GPU
hardware decoder wired into an OpenGL-family render path." `setDecoder`
here mirrors that directly: `setPropertyString`, not a `loadfile` reissue
at the current position — with the reissue approach (mirroring mpv's
own `reload.lua` companion script's "preserve position, reissue
loadfile" pattern for a *different* problem, stalled network streams)
noted in a comment as the fallback if real-device testing ever turns up
a VideoToolbox-specific problem with the direct-set approach.

**Property vs. option, caught before it shipped.** An early version of
`setDecoder` called `setOptionString("hwdec", ...)` — the method this
codebase already uses for `MPVConfiguration`'s pre-`initialize()` setup
— rather than `setPropertyString`. These aren't interchangeable here:
`setOptionString` maps to `mpv_set_option_string`, intended for
before-initialize configuration; a *runtime* change to an
already-initialized player (exactly mpv-android's `pickDecoder()`
codepath) is a property set. mpv's own C API docs note that
`mpv_set_property` can, since API version 1.23, also set some options —
but that doesn't make the reverse true, and mirroring mpv-android's own
call (`setPropertyString`) rather than reasoning about which API
"should" work was the more reliable check here.

**`hwdec-current` (not `hwdec`) is what's observed for UI state**,
matching mpv-android's `hwdecActive` reading `hwdec-current` rather than
echoing back whatever was last requested — `input.rst` documents that
hardware decoding can silently fail over to software for an unsupported
codec, so the requested value and the actually-active one can genuinely
differ. `TrackSelectionSheet`'s decoder section checkmark deliberately
compares against the last-*requested* option (a local `@State`, not
`viewModel.currentDecoder`) for exactly this reason: showing a silent
hardware-to-software fallback as if the user had tapped "Software"
themselves would misrepresent what they actually chose. The actually-
active decoder is surfaced separately, in the section's footer text,
so the fallback is still visible without corrupting which button shows
as selected.

**Lesson:** a scary top search result is a reason to read closely, not
a reason to either dismiss the whole approach or avoid it entirely —
the actually relevant question was never "does changing hwdec at
runtime ever crash mpv," it was "does changing *this* hwdec value, on
*this* backend, in *this* codebase's calling pattern, crash mpv," and
that narrower question had a much more directly useful answer sitting
in a codebase (mpv-android) already doing the narrower thing in
production.
