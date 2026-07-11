---
id: 08--bsymbolic-a-fix-for-something-that-wasnt-actually-broken
title: "`-Bsymbolic`: a fix for something that wasn't actually broken"
sidebar_label: "8. -Bsymbolic: a fix for something that wasn't actually broken"
sidebar_position: 8
---

## 8. `-Bsymbolic`: a fix for something that wasn't actually broken

**What happened:** CI logs showed lines like this during mpv's meson
configuration step:
```
Compiler for C supports link arguments -Wl,-Bsymbolic: NO
ld: unknown options: -Bsymbolic
```
This looked alarming enough that an earlier version of this project
"fixed" it by injecting `b_symbolic = false` into the generated
`crossfile.txt`'s `[properties]` section.

**First correction (still incomplete):** that fix didn't actually work —
the exact same "supports link arguments... NO" line kept appearing in
later CI runs. Investigating why led to checking meson's own complete,
official built-in options documentation directly (Universal options, Base
options, and Compiler options — every category) rather than assuming
`b_symbolic` was a real option that just needed to be in a different
cross-file section. **It isn't.** No option by that name exists anywhere
in meson's built-in option set. The original fix was invalid from the
start; putting it in `[built-in options]` instead of `[properties]`
wouldn't have helped either, since meson has no such option to set in the
first place.

**What the log lines actually are, once traced to mpv's own source:**
mpv's `meson.build` itself calls
`cc.get_supported_link_arguments(['-Wl,-Bsymbolic'])` when defining the
`libmpv` library target. This is meson's own standard
capability-detection function — it's *designed* to test whether a link
argument is supported and gracefully return an empty list if not, rather
than fail the build. The "NO" and the underlying "unknown options"
sub-process failure are that detection mechanism working exactly as
intended: it tries the flag, sees the linker reject it, concludes "not
supported," and simply doesn't pass `-Wl,-Bsymbolic` when actually linking
`libmpv`. Apple's linker not supporting `-Bsymbolic` was never a build
failure at all — it was a normal, harmless "feature not available, don't
use it" result that happens to print a scary-looking `ld: unknown
options` line as part of how the probe works.

**Actual fix:** remove the invalid `b_symbolic = false` line entirely.
It did nothing (meson silently ignores unrecognized cross-file
properties rather than erroring on them), and there was never anything
here that needed fixing in the first place.

**Lesson:** not every alarming-looking line in a build log is an actual
failure — meson's own capability-probing conventions can produce
sub-process errors (a linker genuinely refusing a flag) as an
*intentional, expected part of successfully detecting what's supported*.
Before writing a fix, it's worth tracing where a suspicious log line
actually originates (in this case, mpv's own `meson.build`, not some
opaque part of the toolchain) and confirming a real problem exists at
all — this entry's first version didn't do that rigorously enough, and
shipped a "fix" for a non-existent option that consequently fixed
nothing, while also creating a false sense that the (non-)issue had been
resolved.
