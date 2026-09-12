---
id: 25-two-more-ao-avfoundation-m-call-sites-needed-guarding-found
title: "Two more `ao_avfoundation.m` call sites needed guarding, found only after entry 23/24's fixes let the build reach them"
sidebar_label: "25. Two more `ao_avfoundation.m` call sites needed guarding, found only after entry 23/24's fixes let the build reach them"
sidebar_position: 26
---

## 25. Two more `ao_avfoundation.m` call sites needed guarding, found only after entry 23/24's fixes let the build reach them

**What happened:** with entries 23 and 24's fixes applied (Lua, avdevice,
system libraries, and the `CoreAudioTypes` correction), CI progressed
further than ever before — past `CoreAudioTypes`/`SwiftUICore` (both
correctly resolved to non-issues, confirming entry 24's diagnosis) — and
failed with exactly two remaining undefined symbols:
```
Undefined symbols for architecture arm64
  "_ca_get_device_list", referenced from:
      _audio_out_avfoundation in libmpv-combined.a[arm64][205](audio_out_ao_avfoundation.m.o)
  "_cfstr_get_cstr", referenced from:
      -[AVObserver handleRestartNotification:] in libmpv-combined.a[arm64][205](audio_out_ao_avfoundation.m.o)
```
Both from the same object file, `ao_avfoundation.m` — the same file
patch 0001 (see `buildscripts/patches/mpv/README.md`) had already
patched once, for a different, unguarded call.

**Investigation:** rather than reasoning from memory about mpv's source,
the user uploaded a fresh copy of mpv's actual current master and
mpv-android's source directly, and both symbols were traced by grepping
across the whole `audio/out/` tree for their definitions and every call
site:
- `ca_get_device_list` (defined in `ao_coreaudio_utils.c`) genuinely
  needs full CoreAudio HAL device enumeration
  (`kAudioObjectSystemObject`, `kAudioHardwarePropertyDevices`,
  `AudioDeviceID`) — real HAL APIs with no iOS equivalent. Tracing the
  `#if`/`#endif` structure directly (not assumed from the diff alone)
  confirmed it sits in the *same* `#if HAVE_COREAUDIO` block patch 0002
  already narrowed away from avfoundation, alongside
  `ca_is_output_device` — so it's correctly absent from an
  avfoundation-only iOS build's object files. The bug wasn't in the
  definition's guard at all: `ao_avfoundation.m`'s own
  `audio_out_avfoundation` driver struct still unconditionally assigned
  `.list_devs = ca_get_device_list` regardless of platform. Confirmed
  safe to simply omit under `HAVE_COREAUDIO`-only builds by checking
  `ao.c`, which already null-checks `driver->list_devs` before calling
  it.
- `cfstr_get_cstr` turned out to be a different kind of bug entirely: a
  trivial, genuinely device-independent `CFString`-to-C-string helper
  with zero HAL dependency — but its only definition lives in
  `osdep/utils-mac.c`, compiled under `features['cocoa']`, a *separate*
  meson feature from `coreaudio`/`avfoundation` that happens to also be
  disabled on iOS but for an unrelated reason (no AppKit/Cocoa, not "no
  HAL"). Verified this distinction directly in `meson.build` rather than
  assuming `HAVE_COREAUDIO` was the right guard just because it produced
  a working build — using the wrong macro would have been coincidentally
  correct for this specific build configuration while remaining
  semantically wrong.

**Actual fix:** a new patch, `0008-ao_avfoundation-guard-remaining-undefined-symbols.patch`,
guarding the `.list_devs` assignment with `#if HAVE_COREAUDIO` (mirroring
an existing `#if HAVE_COREAUDIO` block already present elsewhere in the
same file, for style consistency with upstream) and the three
`name`/`cfstr_get_cstr`-dependent lines in the restart-notification
handler with `#if HAVE_COCOA` — leaving the surrounding `MP_WARN`/
`stop`/`start` calls, which don't depend on `name`, unconditional. Both
changes verified with a proper `#if`/`#endif` nesting-depth check (not
naive substring counting — see the correction below) against the file
with the *entire* 0001-0007 patch chain already applied, by actually
running the project's real `apply-mpv-patches.sh` end to end against a
fresh mpv checkout rather than hand-simulating it.

**Self-correction made during this same investigation:** an initial
`#if`/`#endif` balance check used naive string counting
(`content.count('#if ')` vs `content.count('#endif')`), which
undercounted `#ifdef`/`#ifndef` variants and didn't account for `#else`
branches not needing their own `#endif` — it reported a false imbalance
on `ao_coreaudio_utils.c` (a file this patch doesn't even touch).
Switched to actually tracking nesting depth line-by-line
(incrementing on any `#if`/`#ifdef`/`#ifndef`, decrementing on
`#endif`, checking the final depth is zero) — this matches what
`buildscripts/patches/mpv/README.md` itself already recommends
("a simple Python script walking the file and pushing/popping a stack"),
which the first attempt didn't actually follow closely enough.

**Lesson:** a source file already patched once for one iOS-incompatible
call can still have other, independent iOS-incompatible calls elsewhere
in the same file — patch 0001's existence didn't mean `ao_avfoundation.m`
was "done," it meant *one specific call* in it was fixed. Both new bugs
here also reinforce a pattern from entry 10's own patches (0002-0006):
undefined-symbol errors at final link, for symbols that compile
successfully at the call site, usually mean a *guard* is missing or
wrong somewhere in the chain from definition to use — not that the
called function doesn't exist at all. And: verify a "balance check"
script actually implements the check it claims to, rather than trusting
a superficially-plausible one-liner — a wrong verification method that
happens to usually pass is worse than no verification, because it
produces false confidence.
