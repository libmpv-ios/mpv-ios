# mpv iOS compatibility patches

This folder contains patches applied automatically to mpv's source before
building it for iOS (see `buildscripts/include/apply-mpv-patches.sh`,
called from `download.sh` right after mpv is cloned).

## Why these exist

A small number of mpv source files call macOS-only APIs from code paths
that are otherwise buildable and useful on iOS. Rather than disabling the
whole feature (which is simpler but throws away working functionality),
these patches narrow the actual problem down to the specific unavailable
call or type, letting the rest of the feature build and work normally.

Every patch here was written by reading mpv's **actual current source**
directly — not guessed from a compiler error message alone — specifically
checking which functions are genuinely called from which files before
deciding what's safe to patch versus what's a real, unavoidable
macOS-only limitation.

## Current patches

### 0001 — `ao_avfoundation.m`: guard device selection for iOS

mpv's AVFoundation audio output already has clear, intentional iOS support
built in by upstream (three separate `#if TARGET_OS_IPHONE` blocks set up
an `AVAudioSession` on iOS). One call was left unguarded:
`setAudioOutputDeviceUniqueID:`, which Apple's own headers mark
`API_UNAVAILABLE(ios, ...)` — it's for picking among multiple macOS audio
*devices*, a concept iOS doesn't have (iOS manages one active audio route
via `AVAudioSession` instead). This looks like a straightforward oversight
in upstream mpv, not an intentional "don't support this on iOS" choice —
the fix simply skips that one call on iOS, where it has nothing meaningful
to do.

### 0002 / 0003 — `ao_coreaudio_utils.{c,h}`: narrow HAL-only guards

Several functions in this shared utility file are declared under
`#if HAVE_COREAUDIO || HAVE_AVFOUNDATION`, but actually take an
`AudioDeviceID`/`AudioStreamID` (real CoreAudio HAL types that don't exist
on iOS) and are never called from `ao_avfoundation.m` — only from
`ao_coreaudio.c`/`ao_coreaudio_exclusive.c` (both macOS-only, not built for
iOS). These patches narrow those specific declarations/definitions to
`HAVE_COREAUDIO` only, so `avfoundation` doesn't drag in code it never
uses that can't compile on iOS.

### 0004 / 0005 — `ao_coreaudio_chmap.{c,h}`: split device-independent functions

Same situation as above in a different file: `ca_get_acl` (and its
dependencies `ca_find_standard_layout`, `ca_log_layout`) take no device
parameter and are genuinely used by `ao_avfoundation.m`. `ca_init_chmap`/
`ca_get_active_chmap` take an `AudioDeviceID` and are only used by the
macOS-only coreaudio files. These patches split what was one combined
guard block into two, keeping the device-independent half available to
avfoundation.

## What this unlocks

With these patches applied, `buildscripts/scripts/mpv.sh` re-enables
`-Davfoundation=enabled` (previously force-disabled entirely). iOS builds
now get mpv's more modern `AVSampleBufferAudioRenderer`-based audio output
in addition to `audiounit`, including capabilities like spatial audio
support that `audiounit` alone doesn't provide.

`coreaudio` itself (`ao_coreaudio.c`, `ao_coreaudio_exclusive.c`) remains
disabled and unpatched — those files are genuinely, fundamentally
macOS-only (full CoreAudio HAL device enumeration/selection has no iOS
equivalent at all), so there's no oversight to fix there, unlike
avfoundation's narrower, already-mostly-iOS-compatible API surface.

## Adding a new patch

1. **Read mpv's actual current source** for the file in question — don't
   guess from an error message alone. Confirm exactly which functions call
   which other functions before deciding what's safe to narrow/guard.
2. Make the patch as small and targeted as possible.
3. Generate it as a standard `-p1` unified diff (`a/path` and `b/path`
   prefixes matching mpv's own repo layout — see the existing patches for
   the exact format).
4. Test-apply it against a fresh mpv checkout before committing:
   `cd buildscripts/deps/mpv && patch -p1 --dry-run < ../../patches/mpv/000N-your-patch.patch`
5. Run a preprocessor `#if`/`#endif` balance check on any file you
   touched after applying for real — an unbalanced patch can produce a
   file that looks fine in a diff but fails to compile in a confusing
   way. A simple Python script walking the file and pushing/popping a
   stack on `#if`/`#endif` lines catches this quickly.
6. Add a README entry (like the ones above) explaining what upstream
   limitation the patch works around and why the fix is correct for iOS
   specifically — not just "makes it compile."
7. Number new patches sequentially (`0006-...`, etc.) —
   `apply-mpv-patches.sh` applies them in filename order, so if one patch
   depends on another already being applied, the numbering must reflect
   that dependency order.

## When a patch stops applying

`apply-mpv-patches.sh` fails loudly (not silently) if a patch no longer
applies cleanly — this usually means an mpv version bump changed the code
the patch targets. When that happens:

1. Check mpv's current source for the file in question to see what changed.
2. Determine whether the original iOS limitation the patch worked around
   still exists in the new code.
3. If yes: update the patch to match the new surrounding code.
4. If no (upstream fixed it themselves, or removed the feature): delete
   the patch and update this README.

Never just delete a failing patch without checking why it stopped
applying first — the failure might mean the iOS-incompatible code moved
elsewhere in the same file rather than disappearing.
