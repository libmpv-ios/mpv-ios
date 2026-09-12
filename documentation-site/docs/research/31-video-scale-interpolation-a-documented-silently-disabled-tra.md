---
id: 31-video-scale-interpolation-a-documented-silently-disabled-tra
title: "Video scale/interpolation: a documented \"silently disabled\" trap that mpv-android's own preference UI was clearly built to work around"
sidebar_label: "31. Video scale/interpolation: a documented \"silently disabled\" trap that mpv-android's own preference UI was clearly built to work around"
sidebar_position: 32
---

## 31. Video scale/interpolation: a documented "silently disabled" trap that mpv-android's own preference UI was clearly built to work around

**What was added:** full-parity video scale/interpolation controls per
this session's own scope decision — `MPVCore.videoScale`/`chromaScale`/
`downscale`/`temporalScale`/`scaleParam1`/`scaleParam2`,
`setInterpolationEnabled(_:)`, `setAspectMode(_:)`, `videoZoom`,
`videoRotation`, `panscan`, `videoUnscaled` — plus a new
`VideoSettingsSheet` UI.

**`--interpolation`'s own manual entry contains an explicit warning that
was the entire reason this feature needed cross-checking against
mpv-android's implementation, not just its option list.** `options.rst`
states: enabling `--interpolation` while `--video-sync` is not one of
the `display-*` modes results in interpolation being "silently
disabled." No error, no refused property write — the toggle would
simply appear to do nothing. Reading mpv-android's
`InterpolationDialogPreference.kt` showed this isn't a theoretical
concern this project would be the first to hit: that class has explicit
`ensureSyncMode()`/`ensureInterpolationToggled()` methods whose entire
purpose is keeping the interpolation switch and the video-sync mode
consistent with each other in both directions — turning interpolation
on forces video-sync to a `display-*` mode if it isn't already one, and
moving video-sync away from `display-*` turns interpolation back off.
`MPVCore.setInterpolationEnabled(_:)` mirrors this pairing directly
rather than only exposing the raw `interpolation` property, specifically
because exposing it raw would reproduce the exact "toggle does nothing,
no error" trap the option's own documentation warns about.

**One part of this couldn't be verified without a real device, and the
code says so rather than asserting it works.** The `display-*` modes
also require, per the same manual page, "a vsync blocked presentation
mode" (`--opengl-swapinterval=1` for the GL backend this project uses).
This project's actual render loop (`MPVGLView`'s render-update-callback-
driven `drawIfNeeded()`) has no explicit swap-interval call and no
`CADisplayLink` — `EAGLContext.presentRenderbuffer` is vsync-locked by
iOS regardless of app-level swap-interval configuration, which *should*
satisfy the requirement, but this hasn't been confirmed by watching
actual interpolation behavior on a device, since this environment can't
build or run the project. `setInterpolationEnabled`'s doc comment says
this plainly instead of implying the feature is fully verified.

**`--video-zoom` is a log2 factor, not a linear multiplier or
percentage** — `options.rst` states this directly (0 = unscaled, 1 =
double size, -2 = one fourth size). `VideoSettingsSheet`'s zoom slider
operates on the raw log2 value directly (a symmetric range around 0 is
the natural UI shape for a log-scale control) while its label applies
`pow(2, value)` to show a human-readable "2.0x"-style readout — binding
a slider directly to this property and labeling the raw value would
have shown a confusing "-2...2"-range number with no obvious
relationship to visible zoom level.

**`--tscale` is a separate, smaller filter namespace from `--scale`/
`--cscale`/`--dscale`, confirmed by options.rst stating outright that
only "separable convolution filters" are valid `--tscale` choices.**
`VideoSettingsSheet` keeps two explicitly separate filter-name arrays
(`spatialScaleFilters` vs. `temporalScaleFilters`) rather than one
shared list threaded through both scale-family and tscale pickers —
merging them would have let the UI offer filter names for `--tscale`
that mpv would reject or ignore.

**What wasn't fully resolved:** neither `--scale=help` nor
`--tscale=help` could be run against a real mpv binary from this
environment, so both filter-name arrays are the subset `options.rst`
names explicitly in prose, not a verified-complete list. Flagged in
both the doc comments and in-code as a known gap, rather than presenting
a plausible-looking but unverified "complete" list as authoritative.

**Lesson:** an option's own manual entry stating a specific, named
failure mode ("silently disabled" under condition X) is a strong signal
to check how a mature, already-shipping implementation of the same
feature handles that exact condition, rather than implementing the
option in isolation and discovering the failure mode via user reports
later. Separately: verifying via documentation and cross-referencing an
existing implementation reaches a real ceiling at some point (the
GL-swap-interval question here) — the honest response is recording
exactly what wasn't verified and why, not extrapolating confidence from
how well-verified the rest of the feature is.
