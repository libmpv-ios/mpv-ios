---
id: 35-loadfile-declared-twice-in-the-same-file-invalid-redeclarati
title: "`loadFile` declared twice in the same file: \"invalid redeclaration\" compile error"
sidebar_label: "35. `loadFile` declared twice in the same file: \"invalid redeclaration\" compile error"
sidebar_position: 36
---

## 35. `loadFile` declared twice in the same file: "invalid redeclaration" compile error

**What happened:** CI failed while compiling `MPVKit` for the iOS
Simulator with:
```
MPVPlayer.swift:621:10: error: invalid redeclaration of 'loadFile(_:mode:)'
```
Two identical-signature declarations of `func loadFile(_ path: String,
mode: MPVLoadMode = .replace)` existed in the same `public extension
MPVCore` — one under a "Loading" section near the top of the file
(the original, from the initial player-controls port), and a second,
byte-identical-in-body copy under a later "Playlist" section (added
when playlist support was ported from mpv-android's `PlaylistDialog`,
since `loadfile` with an `append`/`append+play` mode flag is also how
playlist entries get added). Swift does not allow two methods with the
same name and parameter types on the same extended type, even with
identical bodies - this is a hard compile error, not a warning, and
it's the same failure mode regardless of whether the two copies happen
to agree on implementation.

**Actual fix:** removed the earlier, shorter-commented declaration
under "Loading" and kept the one under "Playlist," since its doc
comment is the more complete of the two (it explains why
`append`/`append+play` are used over the deprecated single-token
`append-play`, sourced from `input.rst`'s own deprecation note) - the
"Loading" section now just points to where `loadFile` actually lives
instead of repeating a second definition.

**Verification:** confirmed via the actual CI failure log rather than
inspection alone which two declarations were colliding (`grep -n "func
loadFile"` initially, then diffed the two full declarations including
their doc comments to decide which one to keep), then re-scanned the
rest of `MPVKit`'s source files for any other same-name/same-signature
duplicates before considering the fix complete - none found; the two
matches for `seek` are legitimate overloads (`seek(to:)` vs.
`seek(by:)`, different argument labels), and other repeated-name
matches were distinct local variables or properties in different
scopes, not top-level redeclarations.

**Lesson:** copy-pasting a helper method into a new feature section (to
keep that section's example self-contained, or because the new section
needs to call it too) is an easy way to introduce an exact duplicate
when the method already exists elsewhere in the same file - especially
across separate work sessions/contexts adding different features (here:
playlist support being added without the person/process doing so
re-checking whether `loadFile` was already declared). A grep for the
function name across the file before adding it again would have caught
this at write time rather than at the next CI run.
