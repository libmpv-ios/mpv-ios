---
id: 13-a-four-round-investigation-bitcode-flag-a-misleading-error-a
title: "A four-round investigation: bitcode flag, a misleading error, a real ordering bug, and finally LTO"
sidebar_label: "13. A four-round investigation: bitcode flag, a misleading error, a real ordering bug, and finally LTO"
sidebar_position: 13
---

## 13. A four-round investigation: bitcode flag, a misleading error, a real ordering bug, and finally LTO

This entry covers four CI failures that looked like the same issue (same
error message, same hex value) but turned out to have three different
root causes discovered across four separate rounds of investigation —
worth reading as one continuous story, since each round corrected
something believed settled in the previous one.

**Round 1 — what looked like the whole story:** the XCFramework assembly
step failed with:
```
error: unable to find any architecture information in the binary at
'.../libmpv-combined.a': Unknown header: 0xb17c0de
```
`ffmpeg.sh` was passing `-fembed-bitcode` in `--extra-cflags`. Bitcode is
Apple's abandoned intermediate representation for App Store binaries,
deprecated starting Xcode 14 and non-functional by Xcode 16 (this
project's CI toolchain). `0x0B17C0DE` is genuinely LLVM's real bitcode
wrapper magic number (verified directly against LLVM's own
documentation) — so this diagnosis wasn't wrong, exactly, but it turned
out to be incomplete: removing `-fembed-bitcode` was a legitimate fix
for a real latent problem (that flag becoming actively harmful on modern
Xcode, worth removing regardless), but **it did not fix this particular
CI failure**, because it wasn't actually the cause of it.

**Round 2 — the error persisted after the "fix," with a misleading
detour:** a later CI run, on a commit that no longer passed
`-fembed-bitcode` anywhere, hit the exact same error. Re-investigating
led first to a wrong turn: `ci.sh`'s error handler only dumped
`meson-log.txt` (the `meson setup`/configure-phase log) on failure, which
this run showed ending in a completely successful-looking feature
summary — creating a false impression that the configure step was
somehow silently failing in a way that log couldn't show. This *was* a
real, separate gap worth fixing (`meson-log.txt` alone can't show a
compile-phase failure, since ninja's own output is what actually needs
inspecting for that), and `ci.sh`'s error handler was improved to say so
explicitly. But it turned out this diagnostic gap wasn't the actual
explanation either.

**Round 3 — the real root cause:** carefully re-reading a full, later CI
log line by line (not just grepping for "error") surfaced this:
```
==> Building mpv for ios-arm64
Building mpv-ios for ios-arm64...
Combining 18 static libs for ios-arm64...
```
`"Building mpv-ios for ios-arm64..."` should never appear here — this is
`mpv-ios.sh`'s (the *all-platform* XCFramework assembly script's) own log
line, printed from inside `ci.sh`'s **per-platform loop**, on its very
first (`ios-arm64`) iteration, before `ios-arm64-simulator` or
`ios-x86_64-simulator` had been built at all.

The cause: `ci.sh`'s build loop called
`./buildall.sh --platform "$platform" -n mpv-ios` — passing **`mpv-ios`**
as the target name, not `mpv`. `buildall.sh`'s own `build()` function
treats a target literally named `mpv-ios` as a special case that directly
invokes `scripts/mpv-ios.sh` (see that function's
`if [[ "$1" == "mpv-ios" ]]` branch) instead of building the `mpv`
dependency for the one platform currently being iterated. This meant
every single loop iteration was prematurely re-running the *entire*
XCFramework assembly — libtool-merging whatever partial, inconsistent
set of per-platform `.a` files happened to exist in `prefix/` at that
moment, including platforms whose `mpv` hadn't been built yet in this
run. The resulting `libmpv-combined.a` was never a coherent, complete
archive — hence "unable to find any architecture information." The
`0xb17c0de` bitcode magic number showing up was very likely a genuine
leftover artifact from an old, pre-fix cached `.a` (from before entry 13
round 1's `-fembed-bitcode` removal) being swept into one of these
premature, incomplete merges — a real bitcode-tainted file was involved,
just not as the direct cause of *this* error the way round 1 assumed.

**Actual fix:** changed `-n mpv-ios` to `-n mpv` in `ci.sh`'s per-platform
loop, so each iteration builds only the `mpv` dependency for its own
platform, and `mpv-ios.sh` (the real XCFramework assembly) runs exactly
once, after the loop, as originally intended.

**A cache-invalidation footnote:** this project's `BUILD_LOGIC_REV`
marker (see entry 6's cache-busting mechanism, later broadened in round 1
of this entry) was already in place and correctly bumped for the
`-fembed-bitcode` removal — that part of the process worked as designed.
It just wasn't sufficient on its own, since the actual bug wasn't a
compiled-artifact staleness problem at all, but a live logic error in how
`ci.sh` invoked `buildall.sh` on every run, cache or no cache.

**Lesson:** an error message pointing at a plausible, well-known culprit
(a deprecated bitcode flag, complete with a matching magic-number
coincidence) can be a real, legitimate problem to fix and still not be
*the* problem causing the specific failure in front of you. Two rounds of
"fix the thing that looks right" didn't resolve this — what did was
reading a complete, unfiltered CI log line-by-line for output that
shouldn't be there at all (an XCFramework-assembly log line appearing
inside what should have been a single-platform dependency-build loop),
rather than continuing to pattern-match on the same error signature
across successive rounds. Worth remembering that grepping a log for
"error" finds where something failed, not necessarily *why* — the actual
explanatory line here was a completely unremarkable-looking status
message in the wrong place, not anything that says "error" at all.

**Round 4 — the same error, a third time, after the ordering bug was
genuinely fixed:** with `ci.sh` corrected (round 3) and confirmed via log
to now build each platform exactly once and run XCFramework assembly
exactly once, afterward — the *exact same* `Unknown header: 0xb17c0de`
error still occurred. This time, tracing the log confirmed every
`libtool -static` merge (all three platforms) completed successfully
with no errors, and the failure happened afterward, specifically inside
`xcodebuild -create-xcframework` reading back `ios-arm64`'s freshly,
correctly-merged `libmpv-combined.a`. This ruled out the round-3 ordering
bug as a contributing factor to this specific failure (it was real and
worth fixing regardless, but wasn't a cause of this error either) and
pointed at a genuinely corrupt object file somewhere in the 18 static
libs being merged for that platform.

Checking every `buildscripts/scripts/*.sh` file again for any remaining
bitcode-related flag turned up nothing (the `-fembed-bitcode` removal
from round 1 was confirmed still in place, and no other script ever had
it). This led to research into what *else* can cause a compiler to embed
LLVM bitcode/IR into an object file: LTO (Link-Time Optimization). `clang`
implements LTO by embedding LLVM IR/bitcode into object files as an
inherent part of the mechanism — not only when the separate
`-fembed-bitcode` flag is explicitly passed. `dav1d.sh` had
`-Db_lto=true` in its meson setup, and meson has a long-documented,
known-broken interaction between `b_lto` and static libraries
(`mesonbuild/meson#1646`) — exactly the `--default-library=static`
configuration this project's crossfile forces for every dependency.

**Actual final fix:** removed `-Db_lto=true` from `dav1d.sh`. As with the
earlier `-fembed-bitcode` removal, `libtool -static` merged the
LTO-tainted dav1d objects into `libmpv-combined.a` without any complaint
— the corruption was only ever caught later, by `xcodebuild
-create-xcframework`'s stricter validation, which is part of why this
took multiple rounds to fully localize: the tool that actually creates
the merged archive doesn't validate architecture information the way the
tool that consumes it afterward does.

**Lesson, extending the same theme from round 2:** "no `-fembed-bitcode`
anywhere" turned out not to mean "no bitcode/IR anywhere in any object
file" — LTO is a second, independent path to the same class of problem,
enabled by a completely different-looking meson option with no obvious
naming connection to "bitcode" at all. When a symptom is known to be
caused by a category of thing (embedded LLVM bitcode/IR) rather than one
specific flag, it's worth searching for every mechanism that produces
that category, not just the first one found — `grep`-ing for the literal
string that fixed it last time (`bitcode`) would never have found
`-Db_lto=true`, since that option's name doesn't mention bitcode at all.
