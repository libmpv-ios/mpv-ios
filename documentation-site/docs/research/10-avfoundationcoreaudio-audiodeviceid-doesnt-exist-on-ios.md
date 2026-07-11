---
id: 10-avfoundationcoreaudio-audiodeviceid-doesnt-exist-on-ios
title: "avfoundation/coreaudio: `AudioDeviceID` doesn't exist on iOS"
sidebar_label: "10. avfoundation/coreaudio: AudioDeviceID doesn't exist on iOS"
sidebar_position: 10
---

## 10. avfoundation/coreaudio: `AudioDeviceID` doesn't exist on iOS

**What happened:** enabling mpv's `avfoundation` audio output (which
meson had auto-enabled once it detected the relevant Apple frameworks
were present) failed with several undeclared-type errors centered on
`AudioDeviceID`/`AudioStreamID`.

**Investigation, done by reading mpv's actual current source (uploaded
directly for this purpose, not relying on search snippets or the error
message alone):**

- `audio/out/ao_avfoundation.m` **already has three separate
  `#if TARGET_OS_IPHONE` blocks** setting up an `AVAudioSession` — clear,
  deliberate upstream iOS support. But one call was left unguarded:
  `[p->renderer setAudioOutputDeviceUniqueID:...]`, which Apple's own
  headers mark `API_UNAVAILABLE(ios, ...)`. This looked like a genuine
  oversight in upstream mpv (a missing guard, not an intentional
  exclusion), since the surrounding code clearly already handles iOS.
- The compile errors, though, actually originated in **shared utility
  files** (`ao_coreaudio_utils.c/.h`, `ao_coreaudio_chmap.c/.h`) under a
  combined `#if HAVE_COREAUDIO || HAVE_AVFOUNDATION` guard. We verified,
  function by function, which of the guarded declarations actually take
  an `AudioDeviceID`/`AudioStreamID` (real CoreAudio HAL types with no iOS
  equivalent) versus which are device-independent
  (`AudioChannelLayout`-based channel-map helpers that `ao_avfoundation.m`
  genuinely calls). The guard had simply never been split to distinguish
  these — everything sharing one condition meant enabling `avfoundation`
  dragged in HAL-only code it never uses.

**Fix:** a 6-patch series (`buildscripts/patches/mpv/0001` through
`0006`), applied automatically by
`buildscripts/include/apply-mpv-patches.sh` (called from `download.sh`
right after mpv is cloned):
1. Guard the one unguarded `setAudioOutputDeviceUniqueID:` call behind
   `#if !TARGET_OS_IPHONE`.
2–5. Narrow the shared-utility guards so only the genuinely
   `AudioDeviceID`-dependent declarations/definitions require
   `HAVE_COREAUDIO`, leaving the device-independent ones (`ca_get_acl`,
   `ca_find_standard_layout`, `ca_log_layout`) available under the
   original `HAVE_COREAUDIO || HAVE_AVFOUNDATION` condition.
6. A follow-up fix (see next entry) for a guard we initially missed.

Each patch was **test-applied against a completely fresh mpv checkout**
(not assumed to apply cleanly) and checked with a small Python script
that verifies `#if`/`#endif` balance across every file touched, since an
unbalanced patch can look fine in a diff while silently breaking
compilation in a confusing way.

**Result:** `mpv.sh` now enables `-Davfoundation=enabled` (previously
force-disabled entirely as the first, simpler fix), giving iOS builds
mpv's more modern `AVSampleBufferAudioRenderer`-based audio output
alongside `audiounit`, including capabilities like spatial audio support
that `audiounit` alone doesn't provide. `coreaudio` itself remains
disabled — its full HAL device enumeration/selection genuinely has no iOS
equivalent, unlike avfoundation's narrower, already-mostly-iOS-compatible
surface.

**Lesson:** a compile error pointing at "undeclared type" doesn't always
mean the surrounding *feature* is impossible on the target platform — it
can mean a *guard condition* was written too broadly, bundling
device-independent and device-dependent code together. Worth checking
which code a failing feature *actually calls* before concluding the whole
feature is unsupportable.
