---
id: 12-a-third-related-file-needed-the-same-treatment-aocoreaudiopr
title: "A third, related file needed the same treatment: `ao_coreaudio_properties.c`"
sidebar_label: "12. A third, related file needed the same treatment: ao_coreaudio_properties.c"
sidebar_position: 12
---

## 12. A third, related file needed the same treatment: `ao_coreaudio_properties.c`

**What happened:** with patches 0001–0006 applied, CI still failed
compiling `ao_coreaudio_properties.c` for an avfoundation-only iOS build
— this time on raw CoreAudio HAL types (`AudioObjectID`,
`AudioObjectPropertyScope`, `AudioObjectPropertySelector`,
`AudioObjectPropertyAddress`) that aren't merely guarded-but-unavailable
like the earlier entries, but not declared *anywhere* in the iOS SDK at
all — `<AudioToolbox/AudioToolbox.h>` doesn't transitively pull in the
macOS-only `<CoreAudio/AudioHardware.h>` HAL header on iOS the way it
does on macOS.

**Root cause:** upstream mpv's `meson.build` compiles
`ao_coreaudio_properties.c` whenever *either* `coreaudio` or
`avfoundation` is enabled. Verified directly against current upstream
source: none of the functions this file defines
(`ca_get`/`ca_set`/`ca_get_ary`/`ca_get_str`/`ca_settable`) are called
from anywhere reachable by an avfoundation-only build —
`ao_coreaudio.c`/`ao_coreaudio_exclusive.c` (macOS-only, not built for
iOS) call them directly, and `ao_coreaudio_utils.c` only calls them from
inside the blocks patch 0002 had already narrowed to `HAVE_COREAUDIO`
only. With patches 0001–0006 applied, nothing in an avfoundation-only
iOS build actually needs this file anymore — `meson.build`'s own
`if features['avfoundation']` block was the only remaining reason it got
compiled at all.

**Fix:** patch 0007 removes `ao_coreaudio_properties.c` from the
`avfoundation` branch of `meson.build`'s file list, leaving it compiled
only under `coreaudio` (correctly still macOS-only, unchanged from
before). Unlike patches 0001–0006, this one is a `meson.build` change
rather than a source-file change, and it has a real dependency
ordering constraint: it only makes sense once patch 0002 has already
narrowed `ao_coreaudio_utils.c`'s own use of this file's macros — which
is why it's numbered 0007, applied last, rather than earlier in the
series.

**Lesson:** the same "guard covers more than it needs to" pattern from
entries 10 and 11 can show up one level higher, in the build-system file
list itself, not just inside `#if` guards within a single file — worth
checking meson.build's own feature-to-file mapping, not just in-file
guards, when a whole file (not just a function) turns out to be
unreachable-but-still-compiled for a given configuration.
