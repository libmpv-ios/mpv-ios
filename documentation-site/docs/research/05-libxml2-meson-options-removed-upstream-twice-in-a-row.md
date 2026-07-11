---
id: 05-libxml2-meson-options-removed-upstream-twice-in-a-row
title: "libxml2: meson options removed upstream, twice in a row"
sidebar_label: "5. libxml2: meson options removed upstream, twice in a row"
sidebar_position: 5
---

## 5. libxml2: meson options removed upstream, twice in a row

**What happened, round 1:**
```
meson.build:1:0: ERROR: Unknown option: "ftp".
```

**What happened, round 2** (after fixing round 1):
```
meson.build:1:0: ERROR: Unknown option: "lzma".
```

**Root cause:** libxml2's meson options list isn't static across
versions. FTP and LZMA compression support were both removed from
libxml2's codebase around the 2.14/2.15 release series (confirmed by
reading libxml2's own NEWS file and current `meson_options.txt` directly,
rather than assuming from the error message alone) — not merely disabled
by default, but deleted, so passing `-Dftp=disabled` or `-Dlzma=disabled`
fails with "unknown option" since there's nothing left to configure.

**What actually fixed this properly:** rather than removing flags one at
a time as each CI run surfaced the next missing one, we compared this
project's `libxml2.sh` directly against **mpv-android's own** `libxml2.sh`
— which only ever passed
`-Dminimum=true -D{push,reader,sax1,iso8859x,pattern}=enabled` and nothing
else. Simplifying to match that exactly (removing `-Dhttp`, `-Dlzma`,
`-Dzlib` entirely, letting every optional feature default to whatever
upstream's own "auto" resolves to) fixed it in one pass and is far more
resistant to future libxml2 version bumps, since it depends on fewer
options that could individually disappear.

**Lesson:** when a version-drift error appears, don't just delete the one
flag the compiler complained about and move on — check whether a
reference implementation (mpv-android, in this case) already solved the
same problem more robustly, and whether other flags in the same command
are equally fragile before the *next* CI run surfaces them one at a time.
