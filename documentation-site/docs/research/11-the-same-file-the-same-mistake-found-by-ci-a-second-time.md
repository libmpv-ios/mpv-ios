---
id: 11-the-same-file-the-same-mistake-found-by-ci-a-second-time
title: "The same file, the same mistake, found by CI a second time"
sidebar_label: "11. The same file, the same mistake, found by CI a second time"
sidebar_position: 11
---

## 11. The same file, the same mistake, found by CI a second time

**What happened:** after patches 0001–0005 shipped and were believed
complete, the next CI run failed with:
```
error: call to undeclared function 'AudioConvertHostTimeToNanos'
error: call to undeclared function 'AudioGetCurrentHostTime'
```

**Root cause:** `ao_coreaudio_utils.c`'s `ca_get_latency()` function had
its *own*, separate `#if HAVE_COREAUDIO || HAVE_AVFOUNDATION` guard,
calling two functions declared in `<CoreAudio/HostTime.h>` — a header
that patch 0002 had already narrowed this file's own `#include` of to
`HAVE_COREAUDIO` only. We had fixed the include but missed that this
function's own guard condition needed the identical narrowing, since it
called functions from that now-conditionally-included header.

**Fix:** patch 0006 narrows `ca_get_latency`'s guard to `HAVE_COREAUDIO`
only, so an avfoundation-only build correctly falls into the function's
existing `#else` branch (a `mach_absolute_time`-based equivalent that's
already there, already correct, and needs no CoreAudio API at all — it
just wasn't being selected due to the too-broad guard).

**What we did afterward to reduce the chance of a third repeat:**
re-scanned every remaining `HAVE_COREAUDIO || HAVE_AVFOUNDATION` guard
across all four touched files for any other hidden
`AudioDeviceID`/`AudioStreamID`/HostTime-API reference, rather than
stopping at the one instance the compiler happened to report first.

**Lesson, stated directly in `patches/mpv/README.md` now:** when a file
has multiple guarded sections sharing the same macro condition, fixing
the one instance a compiler error points at doesn't mean the others are
safe — the same file had two separate instances of essentially the same
mistake (a guard covering more than its body actually needs), and only a
full-file scan catches the second one before CI does.
