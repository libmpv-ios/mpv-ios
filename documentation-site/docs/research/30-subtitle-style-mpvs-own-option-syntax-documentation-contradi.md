---
id: 30-subtitle-style-mpvs-own-option-syntax-documentation-contradi
title: "Subtitle style: mpv's own option syntax documentation contradicts itself, and mpv's hex color byte order is backwards from the common iOS convention"
sidebar_label: "30. Subtitle style: mpv's own option syntax documentation contradicts itself, and mpv's hex color byte order is backwards from the common iOS convention"
sidebar_position: 31
---

## 30. Subtitle style: mpv's own option syntax documentation contradicts itself, and mpv's hex color byte order is backwards from the common iOS convention

**What was added:** `MPVCore.subtitleDelay`/`subtitleScale`/
`subtitlePosition`/`subtitleColorHex`/`subtitleBackgroundColorHex` in
`MPVPlayer.swift`, and a new `SubtitleStyleSheet` UI (delay/size/
position sliders, two `ColorPicker`s) reachable from
`TrackSelectionSheet` once a subtitle track is selected.

**`--sub-scale`'s own syntax line is internally inconsistent, and the
inconsistency was only caught by cross-checking two other parts of the
same manual page against each other.** `options.rst` writes this
option's syntax as `--sub-scale=<0-100>`, which reads as "pass a value
from 0 to 100." But the very next line of the same entry states the
default is `1` — a genuine 0-100 range's default would sit somewhere
near the middle of that range, not at its extreme low end. Checking
mpv's own shipped `etc/input.conf` settled it: the default keybindings
step this option by `add sub-scale 0.1` / `add sub-scale -0.1` per
keypress. Against a real 0-100 range, a step of 0.1 would be an
imperceptible 0.1% nudge; against a ~1.0-centered multiplier, 0.1 is
exactly the "adjust font size by roughly 10%" behavior mpv's own manual
describes elsewhere for that keybinding. `subtitleScale`'s doc comment
records this reasoning explicitly and recommends a ~0.1...3.0 UI range
instead of trusting the `<0-100>` placeholder. (`--sub-pos`'s `<0-150>`
syntax was checked the same way and found to be internally consistent —
its stated default of 100 sits inside that range normally — so it
didn't need the same correction; recorded here mainly so a future
reader doesn't assume every mpv option's syntax placeholder needs this
level of suspicion, only that checking costs little and this specific
one failed the check.)

**mpv's hex color format puts the alpha byte first
(`#AARRGGBB`), confirmed directly against `options.rst`'s own worked
example** (`--sub-color='#C0808080'` for 50% gray at 75% alpha — `C0`
leads). Several general-purpose iOS "hex string to UIColor" snippets
(surfaced while researching the conversion side of this feature) assume
the opposite, more common `#RRGGBBAA` (alpha-last) convention. Getting
this backwards wouldn't have caused a crash or a compile error — it
would have silently swapped the red channel and the alpha channel for
any color with partial transparency, which is exactly the kind of bug
that looks fine in a quick opaque-color test and only shows up once
someone tries a semi-transparent subtitle background. Both
`MPVCore.subtitleColorHex`'s doc comment and `SubtitleStyleSheet`'s
`Color`-hex helpers call out the byte order explicitly so a future hex
color helper isn't copy-pasted in from a generic snippet without
adjusting it.

**`Color.cgColor` is nil for dynamic/system colors, confirmed before
relying on it** — a constant color built from literal RGB components
(`Color(.sRGB, red:...)`) has a working `cgColor`, but `Color.blue` and
anything returned by the system's own `ColorPicker` UI can be a dynamic
color, for which `cgColor` reliably returns `nil`. `SubtitleStyleSheet`
bridges through `UIColor(self)` and `getRed(green:blue:alpha:)` instead,
which works unconditionally for both cases — chosen specifically
because `ColorPicker`'s selection can hand back either kind of color,
not just the constant kind a quick hex-conversion snippet would have
been tested against.

**Non-`@Published` properties need a manual `objectWillChange.send()`
to drive SwiftUI updates.** `PlayerViewModel`'s subtitle-style
properties are computed vars forwarding straight to `MPVCore` (there's
no mpv property-change event observed for any of them, unlike
time-pos/duration/etc.), so plain `get { core.x } set { core.x = $0 }`
would compile fine but never cause a bound `Slider`/`ColorPicker` to
redraw after a write — `@Published`'s automatic notification only fires
for its own wrapped property being reassigned, and nothing here
reassigns one. Each setter calls `objectWillChange.send()` explicitly
before writing through, which is Combine's documented pattern for
exactly this situation (true storage living outside any `@Published`
wrapper the object itself owns).

**Lesson:** the same manual page can be internally contradictory
(syntax placeholder vs. stated default vs. shipped keybindings all
disagreeing about `sub-scale`'s real range) — when something is
suspicious, checking a second and third statement from the *same*
source that bears on the same fact is often enough to resolve it
without needing an external source at all. Separately, "the two most
similar-looking pieces of prior art disagree with each other" (mpv's
alpha-first hex vs. the alpha-last convention several iOS snippets use)
is exactly the situation where trusting either one without checking the
authoritative source for the actual property being written to is
riskiest — the code compiles and looks reasonable either way, and only
mpv's own manual says which one is actually correct for this specific
option.
