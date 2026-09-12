# Research Log: Porting mpv/libmpv to iOS

This is a chronological record of what was actually discovered, what broke,
and how it was fixed while building this project — not a polished
retrospective, but a working log intended so a future maintainer (or a
past one revisiting this after months away) doesn't have to re-derive any
of this from scratch. Where an earlier assumption turned out to be wrong,
that's recorded too, since knowing *why* something was tried and abandoned
is often as useful as knowing what finally worked.

Each entry follows roughly the same shape: what we assumed or attempted,
what actually happened (an error, or a fact found by reading source
directly), and what we did about it. Entries are in the order they came
up during development, which is also roughly the order a from-scratch
attempt at this project would naturally hit them.

---

## 1. The render backend: Metal was assumed, then found not to exist

**Initial assumption:** libmpv would have a Metal render-API backend,
analogous to its OpenGL backend, since Metal is Apple's modern graphics
API and mpv already runs well on macOS.

**What we actually found:** reading libmpv's own public headers directly
(`include/mpv/render.h`, `include/mpv/render_gl.h`) shows only two render
API types are defined: `MPV_RENDER_API_TYPE_OPENGL` and
`MPV_RENDER_API_TYPE_SW` (software rendering). No Metal type exists in
the public render API at all.

mpv's own Metal usage on macOS (`video/out/vulkan/context_mac.m`) doesn't
go through the render API at all — it uses mpv's internal Vulkan context
system, translated to Metal via MoltenVK, and depends directly on
`NSApplication`/AppKit (`if (!NSApp) { ... "no NSApplication initialized" }`).
This path is fundamentally tied to desktop windowing and doesn't apply to
an embedded-in-an-app-view scenario like iOS.

**What mpv actually ships for iOS:** `video/out/hwdec/hwdec_ios_gl.m`,
gated by meson's `ios-gl` feature — OpenGL ES via EAGL, with VideoToolbox
hardware-decoded frames imported through `CVOpenGLESTextureCache`. This is
the real, upstream-supported iOS path.

**What we did:** built `MPVGLView.swift` around `CAEAGLLayer` +
`EAGLContext` + libmpv's OpenGL render API, matching mpv's own intended
iOS integration rather than inventing a Metal path that doesn't exist.
See the main README's "Architecture notes" section for the full write-up
this became.

**Lesson:** "this modern API surely has a backend for the modern graphics
framework" is a reasonable-sounding assumption that turned out false —
checking the actual public header before writing any dependent code
avoided building an entire render view around an API that doesn't exist.

---

## 2. `buildscripts/download.sh`: a dead variable with broken syntax

**What happened:** an early version of `download.sh` had this line, meant
to optionally allow overriding the download tool:

```bash
[ -z "$WGET" ] && WGET=curl -L -o
```

This is invalid — in bash, `=` with a space after it stops being a plain
variable assignment. `WGET=curl` gets set, and `-L` gets interpreted as a
separate command to run, immediately failing CI with `-L: command not
found`.

**Root cause on inspection:** the `$WGET` variable was never actually
referenced anywhere else in the script — every `fetch_*` function called
`curl` directly. It was dead, unused leftover.

**Fix:** deleted the line entirely.

**Lesson:** dead code that "looks like configuration" is worth deleting
rather than leaving in — it added a bug with zero corresponding benefit.

---

## 3. `buildscripts/buildall.sh`: `declare -g` doesn't work in bash 3.2

**What happened:** CI failed with:
```
./buildall.sh: line 31: declare: -g: invalid option
```

**Root cause:** `markbuilt()` used `declare -g "$varname=0"` to set a
dynamically-named global variable. `declare -g` requires bash 4.2+. macOS
ships bash 3.2 as its system `/bin/bash` (Apple stopped updating bash for
GPLv3 licensing reasons around that version), and GitHub's `macos-14`
runner invokes workflow steps with that same system bash unless a script
explicitly re-execs itself under a newer one.

**Fix:** replaced with `eval "$varname=0"`, which achieves the same
dynamic-variable-assignment effect and works identically on bash 3.2 and
newer.

**Lesson:** any bash feature added to this project's scripts needs to be
checked against bash 3.2 compatibility, not just "does this work on my
own machine" — a developer's personal machine likely has a newer
Homebrew-installed bash that CI does not use by default.

---

## 4. `buildscripts/include/path.sh`: `INSTALL=install` vs `INSTALL=$(which ginstall)`

**What happened:** the `unibreak` dependency failed during `make install`
with:
```
../libtool: line 1883: ../install: No such file or directory
```

**Root cause:** `path.sh` set `export INSTALL=install` — a bare word, not
an absolute path. Several autotools-generated Makefiles (via libtool)
construct their own install invocation in a way that resolves a
non-absolute `$(INSTALL)` value as a literal relative path from deep
inside a per-target build directory, rather than searching `$PATH` the
way a plain shell command would. The result: it looked for a literal
file named `../install` relative to the build directory, which doesn't
exist.

mpv-android's own `path.sh` (checked directly, since this project mirrors
its structure) does this correctly on macOS: `` export INSTALL=`which
ginstall` `` — GNU coreutils' `install` (installed as `ginstall` via
`brew install coreutils`, since macOS's BSD `/usr/bin/install` isn't
fully command-line-compatible with what autotools-generated Makefiles
expect), as a full absolute path.

**Fix:** matched mpv-android's approach — `INSTALL=$(which ginstall)`,
with an explicit error if `ginstall` isn't found (telling the user to
`brew install coreutils`). Added `coreutils` to every `brew install` list
in this repo (both READMEs, `build.yml`, `release.yml`).

**Lesson:** when porting a build-script pattern from another platform's
equivalent project (mpv-android, in this case), copy the *reasoning*, not
just an approximation of the syntax — the original bare-word choice here
looked like a plausible simplification but silently broke a real
constraint the original code was satisfying.

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

---

## 6. mpv's meson cross file needs an Objective-C compiler

**What happened:**
```
meson.build:1582:4: ERROR: 'objc' compiler binary not defined in cross file [binaries] section
```

**Root cause:** mpv's iOS VideoToolbox/GLES hardware-decode interop
(`video/out/hwdec/hwdec_ios_gl.m`) is Objective-C, and we'd enabled the
`ios-gl` meson feature that compiles it. meson's cross file only declared
`c` and `cpp` binaries under `[binaries]`, with no `objc`/`objcpp` entries.

**Fix:** since Apple's `clang` itself handles C, C++, and Objective-C
depending on file extension, we pointed `objc`/`objcpp` at the same
`clang`/`clang++` binaries already used for `c`/`cpp`, plus matching
`objc_args`/`objcpp_args` with the same `-arch`/`-isysroot`/version-min
flags as the other language entries. See `buildall.sh`'s `setup_prefix()`.

**A related gotcha we had to account for:** the generated `crossfile.txt`
lives inside the cached `prefix/<platform>/` directory, which is cached
across CI runs by dependency version. This particular fix didn't change
any dependency version, so the existing cache key wouldn't have picked up
the corrected crossfile automatically. We added a `CROSSFILE_REV` marker
to `ci.sh`'s cache key specifically for this kind of change (anything
that alters how `crossfile.txt` itself is generated, independent of
dependency versions), and bumped it.

**Lesson:** a fix to *how the build is configured* (not just *what
version of a dependency is used*) can still be silently masked by a
cache keyed only on dependency versions — worth checking whether a fix
actually needs a cache-invalidation companion change.

---

## 7. Legacy `config.sub` doesn't recognize modern Apple simulator triples

**What happened:** several autotools-based dependencies (`fribidi`,
`harfbuzz`, `libxml2`) failed their `./configure` step specifically for
the simulator platform slices, rejecting the host triple as unrecognized.

**Root cause:** these dependencies bundle their own copies of GNU
autotools' `config.sub` (the script that validates and canonicalizes
`--host` triples), and older bundled copies predate Apple's simulator
target triples (`aarch64-apple-ios-simulator`,
`x86_64-apple-ios-simulator`) — `config.sub` simply doesn't have a rule
matching them, so `configure` aborts with an "invalid host" style error
before ever reaching the compiler.

**Fix:** rather than patching or regenerating `config.sub` inside every
affected dependency's extracted source (fragile — a per-dependency patch
that would need re-verifying against each project's own bundled
autotools version), `buildall.sh` overrides the `host_triple` value
passed to `configure` for the simulator platforms specifically, to a
generic `aarch64-apple-darwin`/`x86_64-apple-darwin` triple that older
`config.sub` copies **do** recognize. This satisfies `configure`'s
validation step, while the actual compilation target (architecture,
sysroot, and the iOS Simulator deployment constraints) stays correctly
locked in via the explicit `-arch`/`-isysroot`/version-min flags already
present in `CC`/`LDFLAGS` — `config.sub`'s job here is just a string
plausibility check, not the actual source of truth for what gets built.

**Lesson:** an autotools "unrecognized triple" error doesn't necessarily
mean the target is actually unsupported — it can mean the specific bundled
`config.sub` copy predates a legitimate target that the rest of the
toolchain handles fine. Substituting a triple the validation script
already understands, while keeping the real compiler flags accurate, is
a reasonable workaround when patching every dependency's own
autotools files individually would be more fragile.

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

## 9. Lua 5.2.4's `os.execute()` calls `system()`, unavailable on iOS

**What happened:**
```
loslib.c:82:14: error: 'system' is unavailable: not available on iOS
```

**Initial (wrong) assumption:** that `-DLUA_USE_IOS` (which we'd already
set) would guard this, the way it seemed to elsewhere in Lua.

**What we actually found, by checking Lua's published source across
versions directly:** the `LUA_USE_IOS`-aware guard around `system()` (an
`l_system` macro in `loslib.c`) was only added in **Lua 5.4**. This
project pins Lua 5.2.4 (see `depinfo.sh`), and 5.2.4's `loslib.c` calls
`system(cmd)` unconditionally with no iOS-awareness at all.

**Why we can't just upgrade Lua to fix this:** mpv's own FAQ states
explicitly that mpv does not and will not support Lua 5.3 or newer — only
5.1, 5.2, or LuaJIT. So "upgrade to 5.4" isn't an available option here.

**Fix:** rather than patching Lua's own source, `lua.sh` force-includes
(`-include`) a small generated header that `#undef`s and redefines the
`system` macro to a harmless stub (`return cmd ? -1 : 0`, matching
`system(NULL)`'s own "no command processor available" convention) before
`loslib.c`'s reference to it is ever compiled. `os.execute()` calls from
any Lua script become a no-op reporting failure, rather than the build
refusing to compile. No mpv default script actually calls `os.execute()`,
so this has no practical runtime impact for normal playback.

**Lesson:** a macro that "should" guard something based on its name isn't
guaranteed to — verifying against the actual version in use (not the
latest version's behavior) mattered here, since the fix upstream added in
a later release doesn't retroactively apply to the older, still-in-use
version this project depends on.

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

## 14. Vulkan via MoltenVK: investigated, not yet attempted

Documented in full in `ROADMAP.md`'s Phase 4 — summarized here for
completeness of this research log:

- Confirmed `VK_EXT_metal_surface`/`vkCreateMetalSurfaceEXT` can create a
  `VkSurfaceKHR` directly from a `CAMetalLayer`, with **no**
  `NSApplication`/AppKit dependency — unlike mpv's existing macOS Vulkan
  context (`context_mac.m`), which does require it and is why that
  existing file can't simply be reused for iOS.
- Identified `video/out/vulkan/context_android.c` (104 lines, no desktop
  windowing dependency) as the right reference pattern for a hypothetical
  `context_ios.m` — Android has the same "no desktop windowing system"
  constraint iOS does, and mpv already solved it there.
- Checked whether Homebrew's `molten-vk` formula could shortcut building
  MoltenVK from source — it can't; that formula only builds MoltenVK's
  macOS slice, not iOS, since it uses `MoltenVKPackaging.xcodeproj`'s
  macOS-only build scheme.
- Concluded this is a substantially larger undertaking than any single
  fix in this log — five different files/scripts across two build
  systems (meson and MoltenVK's own Xcode-project-based build), none of
  which could be verified without Mac access, unlike the avfoundation
  patches which were debugged against real CI compiler errors one at a
  time. Deliberately not started yet; see `ROADMAP.md` for the full
  breakdown of what it would take.

---

## 15. Swift Package Manager doesn't propagate a binaryTarget's headers automatically

**What happened:** once the `Libmpv.xcframework` build itself was finally
green (see entry 13), the very next CI stage — building `MPVKit` as a
Swift package against that framework — failed immediately:
```
In file included from .../MPVKit/Sources/CMPV/cmpv_shim.c:1:
.../MPVKit/Sources/CMPV/include/cmpv_shim.h:4:10: fatal error: 'mpv/client.h' file not found
    4 | #include <mpv/client.h>
```

**Root cause:** `Package.swift` declares `CMPV` (a C target) with
`dependencies: ["Libmpv"]`, where `Libmpv` is the `.binaryTarget` wrapping
`Libmpv.xcframework`. This looks like it should be enough — and it is,
for *Swift* files that `import Libmpv` (see `MPVCore.swift` and others,
which work fine) — but it is **not** enough for a C target that reaches
for the framework's headers via a plain `#include`. This is a
well-documented Swift Package Manager limitation, not a mistake specific
to this project: multiple independent bug reports
(`swiftlang/swift-package-manager#7626`, a Swift Forums thread titled
exactly "Binary Target infer header search path", and several others)
describe the identical symptom against completely unrelated packages —
SPM does not automatically add a binary target's `Headers/` directory to
a dependent C/C++/Objective-C target's header search path, only to
Swift's module-based `import` resolution.

**Fix:** added explicit `cSettings: [.headerSearchPath(...)]` entries to
`CMPV`'s target definition in `Package.swift`, pointing directly at the
XCFramework's own internal per-platform `Headers/` folders. This
project's XCFramework (built by `buildscripts/scripts/mpv-ios.sh`)
produces exactly two platform-slice folders — a device slice
(`ios-arm64`) and a lipo-merged simulator fat-binary slice
(`ios-arm64_x86_64-simulator`), matching the plain-static-library
XCFramework layout documented in several third-party writeups on the
format. Both paths are listed unconditionally; whichever one doesn't
apply to the current build target is simply not found and ignored by the
compiler, so this doesn't need to vary per-platform in the manifest
itself.

**Lesson:** a working `import Libmpv` elsewhere in the same package
doesn't guarantee every target can see the underlying headers — Swift's
module-based import and a C target's raw `#include` resolve through
different mechanisms in SPM, and only one of them benefits automatically
from a binary target dependency. Worth checking specifically whether a
failing target is a C/Objective-C target reaching for headers directly,
versus a Swift target doing a module `import`, since the fix differs
completely between the two.

---

## 16. `swift build` cannot build a binaryTarget package for iOS at all

**What happened:** after entry 15's header-search-path fix, CI still
failed with the exact same `'mpv/client.h' file not found` error — but
now preceded by a very different-looking warning that hadn't been
investigated yet:
```
<unknown>:0: warning: using sysroot for 'MacOSX' but targeting 'iPhone'
```
This warning appeared on *every* file compiled, immediately suggesting
the header-search-path fix from entry 15 wasn't the (only) issue — the
compiler itself seemed to be using the wrong SDK entirely, regardless of
what path was configured.

**Root cause:** this build was invoked as
`swift build -Xswiftc -sdk ... -Xswiftc -target arm64-apple-ios17.0-simulator`.
It turns out this specific approach — driving a cross-platform build of a
`.binaryTarget`-dependent package via the plain `swift build` CLI, using
`-Xswiftc`/`-Xcc` flags to redirect the SDK/target — has a real, upstream
limitation, not something fixable by adjusting those flags further:
SwiftPM's own binary-target-resolution code only recognized a `"macos"`
platform string when matching an XCFramework slice to build against (see
`swift-package-manager` issue #6571, which describes the identical
symptom against a completely unrelated XCFramework dependency). There was
no `ios`/`ios-simulator` case in that mapping at all as of that issue —
meaning `swift build` was always going to reach for a macOS slice of
`Libmpv.xcframework` internally, no matter what SDK/target was passed to
the Swift compiler frontend via `-Xswiftc`. The "using sysroot for
'MacOSX'" warning was this happening in practice, and the cascading
header "file not found" errors were a direct consequence (the wrong
sysroot can't see the iOS-slice headers entry 15's fix pointed at,
because the build wasn't actually targeting that slice).

**Fix:** replaced both `swift build -Xswiftc ...` invocations in
`build.yml`'s `swift-package-build` job with `xcodebuild build -scheme
MPVKit -destination "generic/platform=iOS Simulator"` (and the
device-platform equivalent). Modern Xcode can treat a bare
`Package.swift` directory as an implicit project without needing
`swift package generate-xcodeproj` (long deprecated) or any checked-in
`.xcodeproj` — `xcodebuild`, unlike the plain SwiftPM CLI, has always
correctly resolved XCFrameworks per-platform, which is also why this
project's actual app target (`mpv-ios-player`, via `project.yml` +
`appetize-preview.yml`) was never affected by this — it was always built
with `xcodebuild`, never `swift build` directly.

**Lesson:** when two different tools exist for nominally the same job
(here, `swift build` and `xcodebuild`, both able to "build a Swift
package"), and a package depends on something platform-specific like an
XCFramework binary target, it's worth checking whether both tools
actually support that dependency equally — they don't always, and the
failure mode when they don't can look like a header/path configuration
problem (entry 15's territory) rather than what it actually is: an
entire code path in one tool never being wired up for the platform being
targeted at all.

---

## 17. `import Libmpv` was never valid — a raw C static library has no Swift module

**What happened:** with entry 16's `xcodebuild` fix in place, CI got
further — `CMPV` compiled successfully (confirming entry 15's header
search paths worked) — but `MPVKit` itself then failed:
```
MPVCore.swift:3:19: error: no such module 'Libmpv'
@_exported import Libmpv
                  ^
```
Inspecting the full `swift-frontend` invocation in the log showed every
`-F` (framework search path) flag pointing at standard SDK/DerivedData
locations — **none of them referenced `Libmpv.xcframework` at all**, even
though `MPVKit`'s target explicitly listed `Libmpv` as a dependency in
`Package.swift`.

**Root cause:** `Libmpv` is a `.binaryTarget` wrapping a plain static
library (`libmpv-combined.a`) plus C headers — it was built by
`buildscripts/scripts/mpv-ios.sh` using `xcodebuild -create-xcframework
-library ... -headers ...`, the form intended for exposing a C/C++
static library, not a Swift framework. Multiple independent reports
(Swift Forums threads, an Apple Developer Forums thread, and a detailed
engineering writeup — all describing the identical "no such module"
symptom against completely unrelated XCFrameworks) confirm the same
underlying fact: a `.binaryTarget`/XCFramework only behaves as an
*importable Swift module* if it actually contains a compiled
`.swiftmodule` inside it. Ours never did and structurally couldn't — it
wraps mpv's C library, which has no Swift code or Swift module to begin
with. `@_exported import Libmpv` (and the plain `import Libmpv` in two
other files) was therefore never a valid statement — it was attempting
to import something that was never a Swift module and never could be one
built this way, and it likely only ever appeared to "work" during
earlier, more limited local testing that didn't exercise this exact
compilation path.

The fix in entry 15 (adding explicit header search paths to `CMPV`) was
real and necessary, but solved a different problem: it let the `CMPV` *C
target* find libmpv's C headers via `#include`. It never addressed (and
couldn't have addressed) `MPVKit`'s Swift files trying to `import Libmpv`
as if it were a Swift module.

**Actual fix:** removed `@_exported import Libmpv` from `MPVCore.swift`
and the plain `import Libmpv` from `MPVGLView.swift` and
`MPVProperty.swift`. This required no functional change beyond deleting
those lines — every mpv C symbol these files use (`mpv_create`,
`mpv_command`, `mpv_render_context_create`, `MPV_FORMAT_STRING`, etc.) is
already declared in `cmpv_shim.h` (which `#include`s `<mpv/client.h>`,
`<mpv/render.h>`, and `<mpv/render_gl.h>`), and is already exposed to
Swift via the existing `import CMPV` each of these files already had.
`Libmpv` remains listed in `MPVKit`'s target `dependencies` in
`Package.swift` — that part was and is correct, since the actual
`.a` binary still needs to be *linked* against, even though it's never
*imported* as a module.

**Lesson:** `@_exported import` (or any `import`) of a binaryTarget only
makes sense if that binary target is itself a Swift framework/module — a
binaryTarget wrapping a plain C static library should only ever be
consumed indirectly, through a C target (like `CMPV` here) that
`#include`s its headers and is itself imported from Swift. Writing
`import Libmpv` "because it's listed as a dependency" conflates two
different relationships SwiftPM's `dependencies:` array can express —
"this target needs to be able to import that module" is not the same
guarantee as "this target needs to link against that binary" — and only
one of those was ever true here.

---

## 18. C enums import as distinct Swift types, not as `Int32`/`UInt32` directly

**What happened:** with entries 15–17 resolved, `MPVKit` finally reached
real type-checking, and failed with a cluster of errors like:
```
MPVProperty.swift:60:44: error: cannot convert value of type 'mpv_error' to specified type 'Int32'
MPVCore.swift:235:55: error: cannot convert value of type 'UInt32' to expected argument type 'Int32'
```

**Root cause:** libmpv's C headers declare several plain enums —
`mpv_error`, `mpv_format`, `mpv_event_id`, `mpv_end_file_reason` — as
`typedef enum mpv_error { ... } mpv_error;`, no fixed underlying type
annotation. When Swift's Clang Importer bridges a plain C enum like this,
it creates a **distinct Swift type** (e.g. `mpv_error`, itself
`RawRepresentable` with some integer `.rawValue`), not a transparent
alias for `Int32`/`UInt32`. This project's code had, in several places,
mixed two things that only *look* interchangeable:
- The real return type of libmpv's C functions themselves (`mpv_command`,
  `mpv_set_property`, etc. are declared to literally return `int`, which
  bridges cleanly to Swift's `Int32`).
- Named error/format/event constants (`MPV_ERROR_UNINITIALIZED`,
  `event.event_id`, `endFile.reason`), which are typed as their *enum*
  (`mpv_error`, `mpv_event_id`, `mpv_end_file_reason` respectively), not
  as bare integers.

A function declared to return plain `Int32` (matching the real C
function signature) can't also directly `return
MPV_ERROR_UNINITIALIZED` (an `mpv_error` value) without an explicit
`.rawValue` — and the reverse direction (passing our own `Int32`-backed
`MPVFormat` enum's `.rawValue` into something expecting the real
`mpv_format` C enum) hit the identical mismatch from the other side.

**Fix, in three parts:**
1. Every `return MPV_ERROR_UNINITIALIZED` (nine occurrences across
   `MPVCore.swift` and `MPVProperty.swift`) became `return
   MPV_ERROR_UNINITIALIZED.rawValue`, matching the `Int32` these
   functions actually return (mirroring the real C functions' `int`
   return type).
2. `event.event_id.rawValue`, `endFile.reason.rawValue`, and
   `prop.format.rawValue` (all `UInt32` as bridged) were wrapped in
   explicit `Int32(...)` where the surrounding Swift code (this
   project's own `MPVEvent`/`MPVFormat` types) expects `Int32`.
3. The reverse direction — constructing a real `mpv_format` C enum value
   from our own `MPVFormat` Swift enum, needed by
   `mpv_observe_property` — was **not** fixed with a raw
   `mpv_format(rawValue: UInt32(format.rawValue))` conversion, because a
   plain C enum's Swift-generated `init(rawValue:)` is failable (Swift
   can't know every raw integer maps to a defined case), which would
   have required an unsafe force-unwrap or an unreachable-but-mandatory
   fallback. Instead, `MPVFormat` gained an explicit `var mpvFormat:
   mpv_format` computed property, mapping each of its five cases to the
   corresponding real `MPV_FORMAT_*` constant by name — compile-time
   exhaustive, no optional involved at all.

**Lesson:** when a C header exposes a plain (non-fixed-underlying-type)
enum, assume it will import into Swift as its own named type, not as a
convenient alias for whatever integer type "feels right." Every point
where a value crosses between "the real C function's declared int return
type" and "one of that C API's own named enum constants" is a place this
kind of mismatch can hide — and it can hide differently in each
direction (missing `.rawValue` one way, a needlessly-failable
`init(rawValue:)` the other way), so each conversion site is worth
checking on its own rather than assuming one fix pattern covers every
occurrence.

---

## 19. `DispatchQueue.sync` ambiguity: an annotation wasn't enough, extraction was

**What happened, round 1:** with entries 15–18 resolved, `MPVKit`
progressed further into real type-checking and hit:
```
MPVGLView.swift:97:21: error: ambiguous use of 'sync(execute:)'
        renderQueue.sync {
                    ^
Dispatch.DispatchQueue:74:17: note: found this candidate in module 'Dispatch'
    public func sync<T>(execute work: () throws -> T) rethrows -> T
Dispatch.DispatchQueue:3:17: note: found this candidate in module 'Dispatch'
    public func sync(execute block: () -> Void)
```

**Initial (incomplete) diagnosis:** `DispatchQueue` declares two
overloads of `sync` — a generic, `rethrows` version, and a plain
`() -> Void` version. The closure passed to `renderQueue.sync { ... }` in
`attachRenderContext()` contained **nested calls to
`withUnsafeMutablePointer(to:_:)`**, itself generic and `rethrows`. The
first fix attempt added an explicit closure signature —
`renderQueue.sync { () -> Void in ... }` — reasoning that telling the
compiler the outer closure's type explicitly would resolve which `sync`
overload was intended.

**Round 2 — the same error, in the same place, after that fix shipped:**
a later CI run showed the identical "ambiguous use of 'sync(execute:)'"
error, at the same line, **with the `() -> Void in` annotation visibly
already present** in the failing line the compiler quoted. This
conclusively demonstrated that the annotation alone was not sufficient —
the ambiguity wasn't coming from Swift being unable to infer the outer
closure's own signature, but from the *nested* generic/rethrows calls
inside it confusing overload resolution in a way an outer annotation
doesn't reach.

**Actual fix:** extracted the entire nested
`withUnsafeMutablePointer(to:_:)` pyramid out of the `sync` closure
entirely, into a new private, non-generic method
(`createRenderContext(core:) -> MPVError?`). The `sync` closure in
`attachRenderContext()` now contains only a single, flat statement —
`creationError = self.createRenderContext(core: core)` — with no nested
generic calls anywhere in its body. This is what actually resolved the
ambiguity: removing the nested generics from the closure passed to
`sync`, not describing that closure's own type more precisely.

**Lesson:** when an "ambiguous use of X" error persists after adding an
explicit type annotation at the call site the error points to, the
annotation may be treating a symptom rather than the cause — worth
checking whether *nested* generic/`rethrows` calls deeper inside that
same closure body are what's actually defeating overload resolution.
Extracting the nested generic structure into its own ordinary
(non-generic-call-containing) function is a more reliable fix than
trying to out-annotate the ambiguity from the outside, and is worth
trying first once an annotation demonstrably didn't work — as confirmed
here by the same error reappearing, unchanged, in the very next CI run
after the annotation was believed to have fixed it.

## 20. Xcode 16.2's stricter C-string macro import made `MPV_RENDER_API_TYPE_OPENGL` ambiguous

**What happened:** after the enum-interop fixes from entry 18 and the
`DispatchQueue.sync` extraction in entry 19, CI progressed further into
`MPVGLView.swift` and then failed at:

```swift
let apiTypeGL = UnsafeMutablePointer(mutating: MPV_RENDER_API_TYPE_OPENGL)
```

with:

```text
error: type of expression is ambiguous without a type annotation
```

The surrounding build log contained many raw Clang module-compilation
messages, but inspection of the final Swift compiler diagnostics showed this
was the first real compilation failure.

**Root cause:** `MPV_RENDER_API_TYPE_OPENGL` is **not** a Swift constant defined
by this project. It comes directly from libmpv's public
`include/mpv/render.h` header as the C macro:

```c
#define MPV_RENDER_API_TYPE_OPENGL "opengl"
```

Under Xcode 16.2 / the iOS 18.2 SDK, Swift's Clang importer became stricter
about C string-literal macros. Instead of unambiguously flowing into
`UnsafeMutablePointer(mutating:)`, the imported macro can now match more than
one valid Swift representation (for example, a C-string pointer versus a
Swift string-like type). As a result, Swift can no longer determine which
`UnsafeMutablePointer(mutating:)` overload should be selected, reporting the
expression itself as ambiguous.

To verify this, the entire package was searched for
`MPV_RENDER_API_TYPE_OPENGL` and the related software-rendering macro.
Neither was used anywhere else, confirming the ambiguity was localized to a
single call site rather than requiring a project-wide migration.

**Fix:** rather than relying on implicit bridging, the imported C macro is
first bound to an explicitly typed C-string pointer, making the conversion
target unambiguous before passing it into
`UnsafeMutablePointer(mutating:)`:

```swift
let apiTypeGLCString: UnsafePointer<CChar> = MPV_RENDER_API_TYPE_OPENGL
let apiTypeGL = UnsafeMutablePointer(mutating: apiTypeGLCString)
```

This preserves the exact runtime behavior while giving Swift's type checker
the information it now requires under the newer SDK.

**Lesson:** when a newer Swift toolchain reports a C macro as "ambiguous,"
the underlying problem may not be the API being called, but how the Clang
Importer now bridges that macro into Swift. Giving imported C values an
explicit intermediate type before passing them into overloaded APIs is often
more robust than depending on implicit inference, especially for legacy
`const char *` macros originating from C libraries. The same C header can
compile unchanged for years while newer Swift/C interop rules require more
explicit typing at the call site.

---

## 20. Correction: `MPV_RENDER_API_TYPE_OPENGL` wasn't ambiguous — it's a plain `String`

**What happened:** the fix described in the entry above (binding
`MPV_RENDER_API_TYPE_OPENGL` to an explicit `UnsafePointer<CChar>`
constant) was believed to resolve the type issue, but the very next CI
run failed at the same line with a different, more specific error:
```
MPVGLView.swift:139:54: error: cannot convert value of type 'String' to
specified type 'UnsafePointer<CChar>' (aka 'UnsafePointer<Int8>')
```

**What this reveals about the previous entry's diagnosis:** the earlier
fix assumed the Clang Importer was offering *two* possible types for this
macro (an "ambiguous" overload situation) and that pinning one down
explicitly would settle it. The actual compiler error shows this wasn't
quite right — under the Xcode 16.2 / iOS 18.2 SDK combination this
project's CI uses, `MPV_RENDER_API_TYPE_OPENGL` (`#define
MPV_RENDER_API_TYPE_OPENGL "opengl"` in libmpv's `render_gl.h`) imports
as a plain Swift `String`, not as anything resembling
`UnsafePointer<CChar>` at all. There was no ambiguity to resolve — the
`let apiTypeGLCString: UnsafePointer<CChar> = MPV_RENDER_API_TYPE_OPENGL`
line was a direct type mismatch, doomed to fail regardless of how
explicitly it was annotated, since a `String` cannot be assigned to an
`UnsafePointer<CChar>`-typed constant no matter how that constant is
declared.

**Actual fix:** bridge the `String` to a C string pointer properly, using
`MPV_RENDER_API_TYPE_OPENGL.withCString { apiTypeGL in ... }`. Since
`withCString`'s pointer is only valid for the duration of its closure,
and `mpv_render_context_create` is a synchronous call that doesn't retain
the pointer past its own return, the entire render-context-creation logic
(previously two levels of nested `withUnsafeMutablePointer` calls) was
moved one level deeper, inside this closure, rather than trying to
extract a longer-lived pointer via `strdup` (which would need matching
manual `free` cleanup for no actual benefit, since nothing needs the
string to outlive this one call).

A missing closing brace was also introduced when the previous fix
attempt added its own nesting level without adjusting the function's
final closing braces to match — worth specifically re-counting brace
nesting depth by hand after adding or removing a closure level in a
deeply-nested function like this one, since a brace-count mismatch can
produce confusing, seemingly unrelated compile errors far from the
actual missing brace.

**Lesson:** "ambiguous" and "cannot convert" are different diagnoses that
call for different fixes, even when they point at the same line and
involve the same values — worth reading the *exact* error text on each
new CI failure rather than assuming a previous, related-looking error
was just incompletely fixed by the same mechanism. Here, the first fix's
own reasoning (macros can import as multiple possible types under newer
interop rules) was a real, generally-true fact about Swift/C interop, but
didn't happen to be what was actually going wrong at this specific call
site — the real answer was simpler (a single, unambiguous `String`
import) than the theorized one (an unresolved overload).

---
## 21. `mpv_render_context_render`: `&fbo`/`&flipY`/`&skip` inside an array literal don't outlive the call

**What happened:** CI failed at `MPVGLView.swift`'s per-frame render call,
not the render-context-setup code entry 17/20 dealt with, with three
instances of the same error:
```
cannot use inout expression here; argument 'data' must be a pointer that
outlives the call to 'init(type:data:)'
    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &fbo),
```
The offending code built the `renderParams` array as a literal, taking
`&fbo`, `&flipY`, and `&skip` directly inline:
```swift
var renderParams: [mpv_render_param] = [
    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &fbo),
    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: &flipY),
    mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: &skip),
    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
]
let result = mpv_render_context_render(ctx, &renderParams)
```

**Why this doesn't work:** Swift's inout-to-pointer (`&x`) conversion
only guarantees the resulting pointer is valid for the duration of the
single call it's passed directly to. Here, `&fbo` is passed to
`mpv_render_param.init(type:data:)`, not to `mpv_render_context_render`
itself — so the pointer's guaranteed lifetime ends right there, before
the `mpv_render_param` value (now holding a use-after-scope pointer) gets
stored into the array and read later by `mpv_render_context_render`. This
is the same category of bug as entry 17 (a value being used somewhere its
guaranteed lifetime doesn't reach), just surfacing through the compiler's
pointer-lifetime diagnostics instead of a module-import error. Notably,
the near-identical-looking code in `createRenderContext` (entry 17/20)
never had this problem, because it never takes `&x` inline in an array
literal — it always goes through `withUnsafeMutablePointer(to:)` first
and only stores the resulting, explicitly-scoped pointer.

**Actual fix:** wrap the three per-frame values in `withUnsafeMutablePointer`,
nested (one call per pointer, matching the existing pattern in
`createRenderContext`), and build `renderParams` plus call
`mpv_render_context_render` *inside* the innermost closure, so all three
pointers are still within their guaranteed-valid scope at the moment
they're actually used:
```swift
let result = withUnsafeMutablePointer(to: &fbo) { fboPtr in
    withUnsafeMutablePointer(to: &flipY) { flipYPtr in
        withUnsafeMutablePointer(to: &skip) { skipPtr in
            var renderParams: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipYPtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(skipPtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            return mpv_render_context_render(ctx, &renderParams)
        }
    }
}
```

**Lesson:** taking `&x` inline as an argument to a *value initializer*
(here, `mpv_render_param.init`) is a different, weaker guarantee than
taking `&x` as an argument to the function that actually dereferences it.
The compiler only tracks the pointer as valid up to the boundary of
whichever call directly receives the `&`-expression — wrapping it in
another initializer first and stashing the result doesn't extend that
lifetime, even though the code visually appears to hand the pointer
straight to the C API a few lines later. Any per-frame/hot-path render
parameter struct built from local mutable state needs the same
`withUnsafeMutablePointer`-and-call-inside-the-closure treatment as the
one-time render-context setup already used, not just the one-time setup
path — a bug class missed here the first time specifically because it
"looked like" the already-correct code nearby, differing only in being a
plain array literal instead of a nested closure.

---

## 22. `project.yml`'s app target was pinned to iOS 14.0 while its own code required iOS 16.0

**What happened:** with `project.yml` newly in place (it had been
missing from the repo entirely, despite being referenced by
`.github/workflows/appetize-preview.yml` and documented in the README's
tree diagram — see that fix for the full context) and entry 21's fix
landed, CI progressed much further — through `MPVKit` compiling cleanly —
before failing at `mpv-ios-player`'s own files:
```
'dismiss' is only available in iOS 15.0 or newer
    @Environment(\.dismiss) private var dismiss
                   ^
...
Process completed with exit code 65.
```
The build log's warnings (an `extension URL: Identifiable` Foundation
conformance-collision warning, deprecation notices already understood
from entry 1) were easy to mistake for the actual failure at a glance,
but the real error — an iOS-version-gated API used below the deployment
target — was the `@Environment(\.dismiss)` line.

**Investigation:** `project.yml` set both the project-wide
`options.deploymentTarget.iOS` and the `MPVIOSPlayer` app target's own
`deploymentTarget` to `"14.0"`, matching `MPVKit`'s `Package.swift`
(`.iOS(.v14)`) and the README's documented "iOS 14.0+" for the *library*.
But `deploymentTarget` in `project.yml` was written by inference from
`Package.swift`/README, without first grepping the example app's own
source for which SwiftUI APIs it actually calls. A search of
`mpv-ios-player/*.swift` for version-gated APIs turned up two, both used
unconditionally (no `@available` guard, no `if #available` branch):
`NavigationStack` (`MPVRootView.swift`, `TrackSelectionSheet.swift` — iOS
16+) and `@Environment(\.dismiss)` (`TrackSelectionSheet.swift` — iOS
15+). `NavigationStack` being iOS 16+ makes 16.0 the actual floor this
code already requires, regardless of what the library or the README's
setup instructions state.

**Actual fix:** raised only the `MPVIOSPlayer` app target's
`deploymentTarget` (and its `IPHONEOS_DEPLOYMENT_TARGET` build setting)
to `"16.0"` in `project.yml`, leaving `options.deploymentTarget.iOS` and
`MPVKit`'s own `Package.swift` minimum at `14.0` untouched — the library
itself doesn't use any of the offending APIs and has no reason to have
its stated floor changed. The alternative (rewriting
`TrackSelectionSheet.swift`/`MPVRootView.swift` to use `NavigationView`
and an iOS-14-compatible dismiss pattern instead) would keep the example
app's minimum at parity with the library, but was not the fix applied
here since it touches app logic rather than build configuration for what
is, for now, a genuine version mismatch between two files that were
authored under different assumptions.

**Lesson:** a deployment target set from a library's documented minimum
(`Package.swift`, README setup steps) is not automatically correct for
every target that depends on that library — an app target's real minimum
is set by the newest API its own source actually calls, and needs
checking directly (grep for `@available`, `NavigationStack`,
`.dismiss`/`.presentationDetents`/other version-gated SwiftUI additions,
etc.) rather than inherited by assumption from whatever the library
underneath happens to support. This is easy to miss specifically because
the mismatch only surfaces as a compile error, not a `project.yml`
validation error — `xcodegen generate` succeeds either way, since it has
no way to know what APIs the source files it's pointed at will end up
calling.

---

## 23. First real app-level link: three independent missing-system-library/naming bugs, surfacing together

**What happened:** with entries 21 and 22 fixed, CI reached the actual
link step of the `MPVIOSPlayer` app target for the first time — the
first point in this whole project where anything produces a final
Mach-O binary out of `libmpv-combined.a`, rather than just compiling
`MPVKit`'s own Swift/C sources against it. The link failed with a wall
of output covering what turned out to be three unrelated bugs, plus one
red herring:

1. `ld: warning: no platform load command found in
   '...libmpv-combined.a[x86_64][...]cdef16_sse.obj'` (repeated for many
   object files) — a `libtool -static` warning, not a hard error;
   harmless as long as `ld`'s own "assuming: iOS-simulator" guess is
   correct, which it was here. Not investigated further.
2. `ld: warning: Could not find or use auto-linked framework
   'CoreAudioTypes'` and `Could not parse or use implicit file
   '.../SwiftUICore.framework/SwiftUICore.tbd': cannot link directly
   with 'SwiftUICore' because product being built is not an allowed
   client of it` — looked alarming, but a web search turned up several
   unrelated projects (a CocoaPods/Cloudinary issue, HaishinKit,
   Kotlin Multiplatform builds, an Expo/Xcode-16.1 report) hitting the
   *exact same two warnings*, always alongside a real, unrelated
   undefined-symbol error in the same build. `SwiftUICore` is a
   restricted-linkage Apple framework that ordinary targets aren't
   allowed to link directly — Xcode's own auto-linking appears to
   mis-infer a direct dependency on it (and, separately, on
   `CoreAudioTypes`) whenever *something else* in the same link job has
   already failed with undefined symbols. Across every case found, no
   one needed to "fix" `SwiftUICore` itself — only the framework's
   *auto-link inference failing loudly* is new in Xcode 16; the
   underlying trigger was consistently a real, separate linker error.
   `CoreAudioTypes` specifically, unlike `SwiftUICore`, is a normal
   (if newer) linkable framework — adding it to `linkerSettings`
   resolves that half; `SwiftUICore` needed no fix at all once the
   actual undefined symbols below were resolved.
3. `Undefined symbols`: three genuinely independent problems, all
   producing undefined-symbol errors that happened to appear in the same
   link log:
   - Every `_lua_*`/`_luaL_*` symbol (dozens) — traced to
     `buildscripts/scripts/mpv-ios.sh`'s `LIBNAMES` array listing the
     entry as `lua54`. Lua 5.2.4's own `Makefile install` target always
     produces `liblua.a`, never a version-suffixed name (confirmed by
     `lua.sh`'s own generated `lua.pc`: `Libs: -L${libdir} -llua`). The
     combine script's candidate loop tried `liblua54.a` then
     `liblua5454.a` — neither ever existed, so Lua's static lib was
     silently dropped from `libmpv-combined.a` on every single build
     since this project began, and nothing surfaced it until an actual
     app tried to link against the combined library.
   - `_BZ2_bz*`, `_deflate*`/`_inflate*`, `_iconv*` — genuine system
     libraries (`libbz2`, `libz`, `libiconv`) that ffmpeg's demuxers
     (Matroska block decompression), libass, and mpv's own PNG encoder
     call into, but which were never declared anywhere as a linked
     library for any target in `MPVKit/Package.swift`. A static library
     never pulls in its own system-library dependencies the way a
     dynamic framework does — this was simply never needed before
     because nothing had linked a real app binary against
     `libmpv-combined.a` until this point.
   - `_avdevice_register_all`, `_avdevice_version` — referenced
     unconditionally by mpv's own `common_av_log.c` (version-check and
     registration bookkeeping at startup, unrelated to any actual
     device-input feature), but `ffmpeg.sh` passed `--disable-devices`,
     which fully disables building `libavdevice.a` at all — not just the
     individual OS-specific device backends. On iOS there are genuinely
     no usable device backends, but the library itself (with just its
     registration table and these two entry points) still needs to
     exist.

**Fixes:**
- `mpv-ios.sh`: `LIBNAMES` entry changed from `lua54` to `lua`; added
  `avdevice` to the list; the platform-combine loop now hard-fails
  (rather than silently skipping) if any expected static lib isn't found
  for a platform, printing exactly which name(s) went unmatched — so a
  future naming mismatch like this one surfaces immediately at combine
  time instead of resurfacing three build stages later as a wall of
  undefined symbols with no obvious connection back to the cause.
- `ffmpeg.sh`: `--disable-devices` replaced with `--disable-indevs
  --disable-outdevs`, which still disables every actual OS-specific
  device driver (none of which exist on iOS anyway) while leaving
  `libavdevice.a` itself buildable, satisfying mpv's unconditional
  reference to its two entry points.
- `MPVKit/Package.swift`: added `linkerSettings` to the `MPVKit` target —
  `.linkedLibrary` for `z`, `bz2`, `iconv`; `.linkedFramework` for
  `AVFoundation`, `AudioToolbox`, `CoreAudio`, `CoreAudioTypes`,
  `VideoToolbox`, `CoreMedia` (matching what mpv/ffmpeg's own enabled
  build options actually use).

**Lesson:** a static library combine step that silently drops a
component it couldn't find (rather than failing loudly) can ship broken
for an arbitrarily long time — this project's Lua bundling was wrong
from very early on and nothing caught it until the very first attempt to
link a real app against the combined library, at which point the
resulting error (dozens of undefined `_lua_*` symbols) gave no direct
hint that the actual bug was a filename typo three build stages earlier.
Separately: warnings that look the most alarming in a build log
(`SwiftUICore` — a "not an allowed client" framework-linkage rejection)
aren't necessarily the actual bug; matching the exact warning text
against other projects' reports is often faster than reasoning about the
warning from first principles, and revealed this one to be a downstream
symptom of the real undefined-symbol errors rather than an independent
problem needing its own fix.

---

## 24. Correction: entry 23's `CoreAudioTypes` fix was backwards — explicitly linking it turns a harmless warning into a fatal error

**What happened:** entry 23 treated `ld: warning: Could not find or use
auto-linked framework 'CoreAudioTypes': framework 'CoreAudioTypes' not
found` as something to fix, and added `.linkedFramework("CoreAudioTypes")`
to `MPVKit/Package.swift` alongside the other real framework fixes in that
entry. The next CI run got further — past `MPVKit` compiling, past `CMPV`
linking, all the way to the actual app binary link step
(`Ld .../MPVIOSPlayer.debug.dylib`) — and failed there with:
```
ld: framework 'CoreAudioTypes' not found
clang: error: linker command failed with exit code 1 (use -v to see invocation)
```
No longer a warning — a hard, fatal link error, and a new failure point
(the app-level `Ld` step) that hadn't been reached before.

**Investigation:** a web search for the exact original warning text
turned up several unrelated reports of the same message (a
realm-swift GitHub issue, multiple Apple Developer Forums threads about
SwiftUI Previews, a Google Mobile Ads SDK support thread, a CocoaPods
issue) and they converge on the opposite conclusion from what entry 23
assumed. Directly relevant: a Realm engineer's own diagnosis reads
"CoreAudioTypes is default Framework for iOS" - i.e. implicitly present
already - and a related report states plainly: "Because CoreAudioTypes
is default Framework for iOS, so you don't need import it into your
project. Remove CoreAudioTypes from frameworks, libraries, and embedded
Content." One Apple Developer Forums participant summarized it as: "My
app does not use 'CoreAudioTypes'. From what I see, this error message
obscures the actual issue in a build" - matching entry 23's own original
read of it as a red herring riding alongside a real, separate
undefined-symbol error. `CoreAudioTypes` on iOS is a header-only
umbrella living inside `CoreAudio`, not a separately-shipped linkable
framework binary - so `.linkedFramework("CoreAudioTypes")` asks the
linker for a `CoreAudioTypes.framework` that plainly doesn't exist as a
standalone file, which is a hard requirement failure, whereas Xcode's
own auto-linker only *warns* when its inference reaches the same
nonexistent target and then continues past it.

**Actual fix:** removed `.linkedFramework("CoreAudioTypes")` from
`MPVKit/Package.swift`'s `linkerSettings` entirely, leaving
`AVFoundation`, `AudioToolbox`, `CoreAudio`, `VideoToolbox`, and
`CoreMedia` (all genuinely real, separately-linkable frameworks that
mpv/ffmpeg's enabled build options actually need) in place.

**Lesson:** a linker *warning* about a missing framework and a linker
*error* about a missing framework are not the same problem with
different severities - sometimes the warning is Xcode's auto-linker
reaching for something that was never meant to be linked directly in the
first place, and forcing the explicit link doesn't satisfy the warning,
it manufactures a new failure mode that didn't exist before. The
"symptom vs. cause" distinction entry 23 already drew for `SwiftUICore`
(a restricted framework that legitimately cannot be linked directly, and
needed no fix) should have been applied identically to `CoreAudioTypes`
appearing in the very same warning line - both were auto-link inference
artifacts, not real missing dependencies, and only one of the two got
treated that way the first time around. When a fix for one part of a
multi-symptom error log is applied, re-running to confirm progress
(rather than assuming every line in the original log needed its own
fix) is what surfaced this - the build got measurably further, which is
useful signal, but the exact new failure text needs the same scrutiny as
the original rather than assuming the round of fixes was complete.

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

## 26. Porting mpv-android's touch gestures: two real iOS platform constraints, not bugs

**What was ported:** mpv-android's `TouchGestures.kt` state machine (swipe
seek/volume/brightness, tap-left/tap-right/tap-center gestures, the
deadzone/throttling/tap-timing constants) and the corresponding handling
in `MPVActivity.kt`'s `onPropertyChange`, as a new headless
`MPVTouchGestures` class in `MPVKit` plus gesture-handling logic in
`PlayerViewModel`. The state machine itself (touch-down/move/up,
Control-state transitions, tap-region math) ports directly with no
behavioral differences - it has no Android-specific dependency to begin
with. Two real platform differences turned up in the *observer* side
(the `onPropertyChange`-equivalent logic), both confirmed by checking
current documentation/API behavior rather than assumed:

**1. iOS apps cannot set system volume programmatically.**
mpv-android's volume gesture calls `AudioManager.setStreamVolume()`
directly on the system audio stream. iOS has no equivalent: an app can
*read* `AVAudioSession.sharedInstance().outputVolume`, but cannot set
it - the only way to change system volume from app code at all is
indirectly, by manipulating the hidden slider inside an `MPVolumeView`,
which still requires that view to exist in the hierarchy and is a
workaround rather than a supported direct-set API. `outputVolume` is
also documented (multiple current Apple Developer Forums threads, iOS
18) as unreliable for *reading* the current value in several
situations - stale after backgrounding, reports 0 immediately after
audio session activation. Given both constraints, the ported gesture
adjusts mpv's own in-app `volume` property (0-100) instead of system
volume. This is a permanent, deliberate platform difference from
mpv-android, not a stand-in for a "real" fix.

**2. `UIScreen.main.brightness` doesn't persist past a lock.**
Still the current, non-deprecated API for reading/setting app-level
screen brightness (confirmed directly, not assumed, given how easy
brightness APIs are to get wrong across iOS versions). Unlike Android's
`WindowManager.LayoutParams.screenBrightness` (which mpv-android's
`updateScreenBrightness()` sets and which persists for the Activity's
lifetime), a brightness set via `UIScreen.main.brightness` reverts to
the user's actual system brightness setting the next time the device
unlocks. Not a bug to work around - just a real behavior difference
worth knowing about so it isn't mistaken for the gesture code failing to
"stick."

**Design choice carried over intentionally:** `MPVTouchGestures` has zero
UIKit/SwiftUI/mpv dependency, matching `TouchGestures.kt`'s own
separation from `MPVActivity` - it only computes state-machine
transitions and reports `MPVPropertyChange` cases through a delegate
protocol (`MPVGestureObserver`), the same division of responsibility as
the Kotlin original's `TouchGesturesObserver` interface. `PlayerViewModel`
plays the role `MPVActivity.kt`'s `onPropertyChange` override plays:
translating an abstract property-change event into concrete seek/volume/
brightness/pause actions.

**Verified before writing, not assumed:**
- `MPVCore`/`MPVPlayer`'s actual public API (`core.seek(to:)`,
  `core.volume`, `core.isPaused`, `core.command(_:)`) was checked
  directly against `MPVPlayer.swift` rather than guessed from the
  gesture code's needs - an earlier draft used a nonexistent
  `core.timePos` setter before this check caught it.
- `MPVCoreDelegate`'s existing `nonisolated func mpv(...)` conformance
  pattern in `PlayerViewModel` was checked and matched exactly for the
  new `MPVGestureObserver` conformance, rather than introducing a
  different (and potentially actor-isolation-incompatible) pattern for
  gesture callbacks specifically.
- The two-parameter `onChange(of:) { oldValue, newValue in }` SwiftUI
  API is iOS 17+ only (confirmed via search) - this project's
  `MPVIOSPlayer` app target deployment target is 16.0 (see entry 22), so
  the single-parameter `onChange(of:perform:)` form was used instead.
  Using the newer form here would have reintroduced exactly the kind of
  deployment-target/API-availability mismatch entry 22 already had to
  fix once.

**Lesson:** porting a state machine that has no platform dependency is
mechanical and low-risk; porting the *handler* that reacts to it is
where the real platform differences live, and claiming a platform
constraint exists (e.g. "iOS has no way to read current volume") without
checking current documentation is itself a risk - the accurate claim
here ("no way to *set* it silently, and *reading* it is documented as
unreliable in specific situations") is more precise and more useful than
a vaguer, unverified version of the same point would have been.

---

## 27. Media Session + Picture in Picture: two features where the "obvious" iOS API is a documented trap

**What was added:** Control Center/lock-screen integration
(`MediaSessionManager`, wrapping `MPNowPlayingInfoCenter` +
`MPRemoteCommandCenter` + `AVAudioSession` interruption/route-change
notifications) and Picture in Picture (`PictureInPictureRenderer` in
MPVKit, `PictureInPictureCoordinator` + `PictureInPictureLayerView` in
the app target). Both features have an "obvious first approach" that
turned out to be wrong or unsafe on inspection, in a way this entry
records so neither gets silently reintroduced later.

**1. `mpv_render_context_render()` cannot safely be called twice per
frame.** The first PiP design considered was: render once for the
screen (existing path, unchanged), then render a second time into a
separate FBO sized for PiP. `render.h`'s own documentation rules this
out — each call "implicitly pulls a video frame from the internal
queue," so two calls per displayed frame risk the screen and PiP paths
showing different frames, or one starving the other. The actual design
renders once (screen path, byte-for-byte unchanged) and reads back that
same already-rendered frame via `glBlitFramebuffer` (OpenGL ES 3.0,
confirmed available given this project's `.openGLES3` context) into an
IOSurface-backed `CVPixelBuffer` — a GPU-side copy, not a second mpv
render and not a `glReadPixels` CPU readback.

**2. `CVOpenGLESTextureCacheCreateTextureFromImage`'s internal-format
parameter is not the same kind of thing as a sized GL storage enum.**
An early draft passed `GL_RGBA8_OES` as `internalFormat` (reasoning by
analogy from unrelated render-target-texture-storage code elsewhere).
Checked against a working reference implementation
(a widely-cited "render to IOSurface-backed CVPixelBuffer via texture
cache" writeup) rather than assumed: the correct triple for a BGRA
`CVPixelBuffer` is `internalFormat=GL_RGBA` (channel count, not a sized
OES enum) with `format=GL_BGRA` / `type=GL_UNSIGNED_BYTE` describing the
buffer's actual memory layout. Worth remembering this API doesn't follow
the same convention as plain `glTexStorage2D`-style calls elsewhere in
GL code, even though the parameter is also named "internalFormat" there.

**3. The "standard" iOS trick for setting system volume is an
Apple-acknowledged unsupported hack, not a sanctioned workaround.**
Already covered from the gesture-porting side in entry 26; recorded
again here because `MediaSessionManager`'s remote-command handling
raised the same question independently (whether PiP/lock-screen volume
controls should drive system volume) and reached the same answer for
the same reason — `AVAudioSession.outputVolume` is read-only, and the
`MPVolumeView`-slider trick reaches into a private view hierarchy Apple
has stated isn't supported and which behaves inconsistently with
AirPlay across iOS versions.

**4. `MPNowPlayingInfoPropertyMediaType` and
`MPMediaItemPropertyMediaType` are two different keys expecting two
different enums, and mixing them up is a real shipped mistake, not a
hypothetical one.** Confirmed via IINA's own GitHub issue tracker
containing exactly this confusion. `MediaSessionManager.updateMetadata`
uses the correct key deliberately, with a comment warning against
"correcting" it to the similarly-named one.

**5. `MPMediaItemArtwork`'s `requestHandler` closure has an
Apple-DTS-acknowledged, still-unresolved crash risk under Swift 6
strict concurrency** when it captures and returns an external `UIImage`
value — exactly the shape `updateMetadata` uses. This project currently
builds under Swift 5.9 (`project.yml`), so it isn't hit today; flagged
in-code so a future move to Swift 6 language mode re-checks Apple's
developer forums rather than assuming this still works unchanged.

**6. `AVSampleBufferDisplayLayer` renders nothing — and cannot support
PiP — while it has a zero-size frame or isn't in any view's layer
hierarchy**, confirmed via an Apple Developer Forums thread reporting
exactly that failure mode. `PictureInPictureLayerView` therefore hosts
the coordinator's `displayLayer` at a real, non-zero size at all times
and hides it with `.opacity(0)` rather than `.hidden` or a zero frame,
specifically to avoid silently breaking PiP the next time it's
requested.

**7. `UIBackgroundModes` needs both `audio` and `picture-in-picture`
for PiP to keep rendering once backgrounded** — this project already
had `audio` (for background audio playback, unrelated to PiP), and it
alone is not sufficient; multiple third-party PiP integration guides
add both keys together via Xcode's combined "Audio, AirPlay, and
Picture in Picture" capability checkbox, which was the signal that these
are treated as a pair, not that `audio` implies the other.

**8. `AVSampleBufferDisplayLayer.enqueue(_:)` is safe to call from a
background queue** — confirmed against the WWDC 2014 reference pattern
for this API (`requestMediaDataWhenReadyOnQueue` explicitly takes a
caller-provided background queue). `PictureInPictureCoordinator` enqueues
directly from `MPVGLView`'s own render queue rather than hopping to the
main actor first, avoiding an extra thread transition on every video
frame that would have bought nothing correctness-wise.

**Design choices carried over intentionally:** both
`MediaSessionManager` and `PictureInPictureCoordinator` are separate
types from `PlayerViewModel`, communicating only through an `Action`
enum + closures rather than holding a reference to `MPVCore` directly —
matching mpv-android's own separation between `PlayerActivity`'s
transport-control logic and its `initMediaSession()`/PiP-params setup,
which only ever *signal* PlayerActivity rather than touching `MPVLib`
themselves.

**Lesson:** both features had a first-instinct implementation (render
twice; set system volume directly; a sized GL enum for internalFormat;
hide the PiP layer when not in PiP) that looked reasonable and matched
a nearby, superficially-similar pattern elsewhere — and every one of
them was wrong for a documented reason findable by checking current
official sources (`render.h`, Apple DTS forum threads, a working
reference implementation) rather than reasoning from the shape of
similar-looking code. Consistent with entry 26's own lesson: the
platform-specific *handler*/integration layer is where unverified
analogy-based reasoning is most likely to silently produce something
that compiles, looks plausible, and is subtly wrong.

---

## 28. Playlist support: mpv's own manual says its raw playlist property is "useless," and one playlist command still ships with no change notification

**What was added:** playlist read/write support in `MPVPlayer.swift`
(`loadFile`/`addToPlaylist`/`playlistNext`/`playlistPrev`/
`playlistPlay`/`playlistRemove`/`playlistMove`/`playlistClear`/
`playlistShuffle`/`playlistItems()`), wired into `PlayerViewModel`,
Control Center next/previous-track commands, and a new `PlaylistSheet`
UI. Two findings here are worth keeping in mind for any future code
that touches mpv's playlist:

**1. The `playlist` property cannot be read the way every other
observed property in this codebase is read.** `input.rst` states this
directly: "currently, the raw property value is useless." It's an
`MPV_FORMAT_NODE`, and this codebase's property-event mapping
(`MPVCore.swift`'s `mapEvent`) only decodes flag/int64/double/string —
anything else falls through to `.none`. The fix used here isn't a new
NODE decoder; it's the same pattern `trackList()` already established
for `track-list` in this file: query the documented per-entry
sub-properties individually (`playlist/N/filename`, `/title`,
`/current`, `/playing`) using getters this codebase already has working.
`playlist/N/playing` was used for the "is this the active entry" flag
rather than `playlist/N/current` — IINA's own scripting API documents
`isCurrent` as deprecated in favor of `isPlaying` for exactly this kind
of check, and mpv's manual separately describes `playlist-current-pos`
as only "vaguely useful," which reads as the same underlying
distinction from the mpv side.

**2. `playlist-move` fires no property-change notification at all**,
confirmed via a still-open mpv issue (#7339) — every other
playlist-mutating command in this codebase's wrapper (`playlist-remove`,
`loadfile ... append`, `playlist-clear`, `playlist-shuffle`) does notify
via `playlist-count`/`playlist-pos`, which is why `PlayerViewModel`
mostly relies on observing those two properties rather than refreshing
after every single call. `playlistMove`'s call site is the one
exception: it refreshes explicitly, immediately after the command,
because trusting the observer there would leave `playlist` silently
stale after every reorder. (A related, older, already-fixed bug is also
worth noting for anyone who finds outdated advice while researching
this: `playlist-count` itself had unreliable change notifications on
append/remove prior to mpv 0.17.0 per mpv issue #3267 — long since fixed
upstream, and this project tracks mpv's master branch, but a search on
this topic surfaces plenty of pre-fix discussion that no longer applies
here.)

**3. `append-play` is deprecated in favor of `append+play`** per
`input.rst`'s own note (deprecated since mpv 0.42) — `loadFile`'s
`MPVLoadMode` enum uses the current combinable-flag form as the
default, keeping the deprecated single-token spelling only as a
documented-but-unused case for reference.

**4. `ContentUnavailableView` (used in an early draft of `PlaylistSheet`
for the empty-playlist state) is iOS 17.0+ only** — caught before it
shipped, same category of deployment-target mismatch as entry 26/27's
`onChange(of:)` issue, just a different API. Replaced with a plain
`VStack`-based empty state, consistent with this project's iOS 16.0
deployment target (`project.yml`).

**Lesson:** "the property doesn't decode the way I expected" and "the
mutating command doesn't notify the way every other one does" are both
the kind of behavior that's easy to miss by testing happy-path append/
remove and assuming reorder works the same way — neither surfaces as a
compile error or an obvious crash, only as UI that silently goes stale
after one specific user action. Worth specifically checking, for any
mpv command being wrapped for the first time, whether its own manual
entry documents anything unusual about its change-notification
behavior, rather than assuming all mutating commands in the same
command family behave identically.

---

## 29. Decoder selection: a scary-looking mpv crash report turned out not to apply here, but only after actually reading which backend it named

**What was added:** runtime hardware/software decoder switching
(`MPVCore.DecoderOption`, `setDecoder(_:)`, `currentDecoder()`), a
decoder picker section added to the existing `TrackSelectionSheet`, and
`hwdec-current` property observation feeding
`PlayerViewModel.currentDecoder`.

**The first search result for "change hwdec at runtime" was a mpv
crash report — worth recording exactly why it didn't block this
implementation, rather than either ignoring it or over-reacting to it.**
mpv issue #3788 documents a real, reproducible crash from cycling
`hwdec` between `no` and `auto-copy` at runtime. Two details in that
report matter more than its headline: it's from 2016 (mpv predates
much of its current property-notification infrastructure — see entry
28's note on `playlist-count`'s own since-fixed 2016-era bug for the
same general vintage of issue), and it's specific to the **vdpau**
backend (`Assertion '!ctx->hwdec_priv' failed` inside vdpau's own probe
path) — a Linux/NVIDIA-only decode API this project's iOS build doesn't
compile in at all (`buildscripts/scripts/mpv.sh` only enables `ios-gl`).
Neither detail rules out some other VideoToolbox-specific instability by
itself, but they do mean this specific report isn't evidence against
this specific implementation.

**What did settle it: checking whether an already-shipping player does
this the simple way.** mpv-android's `pickDecoder()`
(`MPVActivity.kt`) calls `MPVLib.setPropertyString("hwdec", ...)`
directly, with no reload/restart/pause-and-resume dance beyond pausing
its own picker dialog UI — and has done so in production for years for
mediacodec, VideoToolbox's closest Android equivalent in terms of "GPU
hardware decoder wired into an OpenGL-family render path." `setDecoder`
here mirrors that directly: `setPropertyString`, not a `loadfile` reissue
at the current position — with the reissue approach (mirroring mpv's
own `reload.lua` companion script's "preserve position, reissue
loadfile" pattern for a *different* problem, stalled network streams)
noted in a comment as the fallback if real-device testing ever turns up
a VideoToolbox-specific problem with the direct-set approach.

**Property vs. option, caught before it shipped.** An early version of
`setDecoder` called `setOptionString("hwdec", ...)` — the method this
codebase already uses for `MPVConfiguration`'s pre-`initialize()` setup
— rather than `setPropertyString`. These aren't interchangeable here:
`setOptionString` maps to `mpv_set_option_string`, intended for
before-initialize configuration; a *runtime* change to an
already-initialized player (exactly mpv-android's `pickDecoder()`
codepath) is a property set. mpv's own C API docs note that
`mpv_set_property` can, since API version 1.23, also set some options —
but that doesn't make the reverse true, and mirroring mpv-android's own
call (`setPropertyString`) rather than reasoning about which API
"should" work was the more reliable check here.

**`hwdec-current` (not `hwdec`) is what's observed for UI state**,
matching mpv-android's `hwdecActive` reading `hwdec-current` rather than
echoing back whatever was last requested — `input.rst` documents that
hardware decoding can silently fail over to software for an unsupported
codec, so the requested value and the actually-active one can genuinely
differ. `TrackSelectionSheet`'s decoder section checkmark deliberately
compares against the last-*requested* option (a local `@State`, not
`viewModel.currentDecoder`) for exactly this reason: showing a silent
hardware-to-software fallback as if the user had tapped "Software"
themselves would misrepresent what they actually chose. The actually-
active decoder is surfaced separately, in the section's footer text,
so the fallback is still visible without corrupting which button shows
as selected.

**Lesson:** a scary top search result is a reason to read closely, not
a reason to either dismiss the whole approach or avoid it entirely —
the actually relevant question was never "does changing hwdec at
runtime ever crash mpv," it was "does changing *this* hwdec value, on
*this* backend, in *this* codebase's calling pattern, crash mpv," and
that narrower question had a much more directly useful answer sitting
in a codebase (mpv-android) already doing the narrower thing in
production.

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

---

## 31. Video scale/interpolation: a documented "silently disabled" trap that mpv-android's own preference UI was clearly built to work around

**What was added:** full-parity video scale/interpolation controls per
this session's own scope decision — `MPVCore.videoScale`/`chromaScale`/
`downscale`/`temporalScale`/`scaleParam1`/`scaleParam2`,
`setInterpolationEnabled(_:)`, `setAspectMode(_:)`, `videoZoom`,
`videoRotation`, `panscan`, `videoUnscaled` — plus a new
`VideoSettingsSheet` UI.

**`--interpolation`'s own manual entry contains an explicit warning that
was the entire reason this feature needed cross-checking against
mpv-android's implementation, not just its option list.** `options.rst`
states: enabling `--interpolation` while `--video-sync` is not one of
the `display-*` modes results in interpolation being "silently
disabled." No error, no refused property write — the toggle would
simply appear to do nothing. Reading mpv-android's
`InterpolationDialogPreference.kt` showed this isn't a theoretical
concern this project would be the first to hit: that class has explicit
`ensureSyncMode()`/`ensureInterpolationToggled()` methods whose entire
purpose is keeping the interpolation switch and the video-sync mode
consistent with each other in both directions — turning interpolation
on forces video-sync to a `display-*` mode if it isn't already one, and
moving video-sync away from `display-*` turns interpolation back off.
`MPVCore.setInterpolationEnabled(_:)` mirrors this pairing directly
rather than only exposing the raw `interpolation` property, specifically
because exposing it raw would reproduce the exact "toggle does nothing,
no error" trap the option's own documentation warns about.

**One part of this couldn't be verified without a real device, and the
code says so rather than asserting it works.** The `display-*` modes
also require, per the same manual page, "a vsync blocked presentation
mode" (`--opengl-swapinterval=1` for the GL backend this project uses).
This project's actual render loop (`MPVGLView`'s render-update-callback-
driven `drawIfNeeded()`) has no explicit swap-interval call and no
`CADisplayLink` — `EAGLContext.presentRenderbuffer` is vsync-locked by
iOS regardless of app-level swap-interval configuration, which *should*
satisfy the requirement, but this hasn't been confirmed by watching
actual interpolation behavior on a device, since this environment can't
build or run the project. `setInterpolationEnabled`'s doc comment says
this plainly instead of implying the feature is fully verified.

**`--video-zoom` is a log2 factor, not a linear multiplier or
percentage** — `options.rst` states this directly (0 = unscaled, 1 =
double size, -2 = one fourth size). `VideoSettingsSheet`'s zoom slider
operates on the raw log2 value directly (a symmetric range around 0 is
the natural UI shape for a log-scale control) while its label applies
`pow(2, value)` to show a human-readable "2.0x"-style readout — binding
a slider directly to this property and labeling the raw value would
have shown a confusing "-2...2"-range number with no obvious
relationship to visible zoom level.

**`--tscale` is a separate, smaller filter namespace from `--scale`/
`--cscale`/`--dscale`, confirmed by options.rst stating outright that
only "separable convolution filters" are valid `--tscale` choices.**
`VideoSettingsSheet` keeps two explicitly separate filter-name arrays
(`spatialScaleFilters` vs. `temporalScaleFilters`) rather than one
shared list threaded through both scale-family and tscale pickers —
merging them would have let the UI offer filter names for `--tscale`
that mpv would reject or ignore.

**What wasn't fully resolved:** neither `--scale=help` nor
`--tscale=help` could be run against a real mpv binary from this
environment, so both filter-name arrays are the subset `options.rst`
names explicitly in prose, not a verified-complete list. Flagged in
both the doc comments and in-code as a known gap, rather than presenting
a plausible-looking but unverified "complete" list as authoritative.

**Lesson:** an option's own manual entry stating a specific, named
failure mode ("silently disabled" under condition X) is a strong signal
to check how a mature, already-shipping implementation of the same
feature handles that exact condition, rather than implementing the
option in isolation and discovering the failure mode via user reports
later. Separately: verifying via documentation and cross-referencing an
existing implementation reaches a real ceiling at some point (the
GL-swap-interval question here) — the honest response is recording
exactly what wasn't verified and why, not extrapolating confidence from
how well-verified the rest of the feature is.

---

## 32. A real compile error shipped in earlier work: `@objc`/`#selector` on plain Swift classes, found while wiring up persisted playback position

**What was added:** playback-position persistence
(`MPVCore.writeWatchLaterConfig()`/`deleteWatchLaterConfig()`, built on
mpv's own built-in watch-later mechanism rather than a custom
save/restore implementation — matching mpv-android's own choice to lean
on mpv's built-in system, and its `savePosition()`'s `eof-reached` check
to avoid resuming a just-finished file at its own ending), wired into
`PlayerViewModel.stop()` and an app-backgrounding observer.

**While adding that backgrounding observer, a genuine compile-breaking
mistake was found in code from an earlier session — not new code, code
already presented as finished.** `MediaSessionManager` (entry 27) uses
`NotificationCenter.default.addObserver(self, selector:
#selector(handleInterruption(_:)), ...)` for its interruption/route-
change handling. `@objc`-exposed methods and `#selector` both require
the containing type to inherit from `NSObject` — `MediaSessionManager`
is declared `public final class MediaSessionManager` with no such
inheritance, matching this codebase's general preference for plain
Swift coordinator types (see `PictureInPictureCoordinator`'s docs on
the same point). This would not have been a subtle runtime bug; it's a
straightforward compile error, sitting in code that had already been
written, reasoned about at length, and presented as complete in a prior
turn.

**The fix surfaced a second, non-obvious issue**: switching to the
block-based `addObserver(forName:object:queue:using:)` API (which needs
no `@objc`/`NSObject`) doesn't fully resolve things on its own, because
both `MediaSessionManager` and `PlayerViewModel` are `@MainActor`-
isolated types. `queue: .main` guarantees the closure runs on the main
thread at runtime, but a plain closure's *static* isolation is still
`nonisolated` to the type system — referencing `self` from inside it
still triggers a Swift concurrency error, confirmed against a matching
Apple Developer Forums report of the exact same "`@MainActor` type +
`addObserver`/`addTarget` closure" combination failing for another
developer. `MainActor.assumeIsolated { }` around the closure body is
the documented resolution for exactly this situation (asserting at
runtime what `queue: .main` already guarantees, without making every
call site `async`) — applied to every affected closure:
`MediaSessionManager`'s two `NotificationCenter` observers, all eight of
its `MPRemoteCommand.addTarget` handlers, and `PlayerViewModel`'s new
backgrounding observer. `PictureInPictureCoordinator`'s
`AVPictureInPictureControllerDelegate`/
`AVPictureInPictureSampleBufferPlaybackDelegate` conformances were
audited for the same risk and left as-is with a comment explaining why
(Apple's own system-framework delegate protocols are expected to be
annotated for exactly this `@MainActor`-conforming-type case) and what
to do if a real build disagrees — this project has no way to verify by
actually compiling, so the honest record is "audited and reasoned
through, not confirmed by a build."

**Lesson, stated plainly:** presenting code as finished in an earlier
turn is not the same as it being correct, and a mistake doesn't become
harder to find just because it shipped a while ago — the same
disciplined checking applied to brand-new code needs to extend to
re-examining prior work when a closely related pattern comes up again
(here, writing a *second* NotificationCenter observer was what
prompted noticing the first one was broken). A `grep` across the whole
project for the broken pattern (`@objc`/`#selector`) after fixing the
two known instances confirmed no third occurrence was hiding elsewhere
— worth doing that sweep rather than assuming the two found instances
were the only ones, once a pattern is known to be wrong.

---

## 33. Stats overlay: an initial "this property doesn't exist" conclusion was wrong, caught by reading mpv's C source instead of stopping at input.rst

**What was added:** `MPVCore.PlaybackStats`/`currentStats()` (codec,
resolution, fps, hwdec, bitrate, A/V sync, dropped frames, cache state)
and a `StatsOverlay` SwiftUI view polling it once per second while
visible — equivalent in spirit to mpv-android's `updateStats()`, though
mpv-android's own version only ever surfaces FPS; this implementation's
scope is closer to mpv's own `stats.lua` OSD script.

**A wrong conclusion, caught before it shipped by going one layer
deeper than the usual source.** An initial `grep` across `input.rst`
for "video-codec"/"audio-codec" turned up nothing, leading to a first
draft that assumed these properties simply don't exist and worked
around it by manually cross-referencing `track-list`'s entries against
the currently-selected `vid`/`aid` track ids instead. That conclusion
was wrong. Checking mpv's own C source (`player/command.c`) — a step
this project doesn't normally need, since `input.rst` is usually
authoritative and sufficient — turned up
`M_PROPERTY_ALIAS("video-codec", "current-tracks/video/codec-desc")`
and its `audio-codec` counterpart: both properties are real, just
implemented as property *aliases* rather than being independently
documented as top-level properties in the section of `input.rst` the
first search covered. The simpler, correct implementation
(`getPropertyString("video-codec")` directly) replaced the manual
track-list cross-referencing entirely once this was found.

**A second, more consequential mistake from the same round of
guessing: assuming `video-bitrate` was a DOUBLE property.** Nothing
about the property's docstring states its type either way, and "a
bitrate" reads intuitively as a fractional value. mpv's own source
settled it unambiguously: `mp_property_packet_bitrate` computes an
internal `double` but returns it via `m_property_int64_ro`, i.e. the
value is rounded and exposed as INT64 at the client-API boundary. This
would not have been a cosmetic bug — mpv's client API refuses a
property read requested in the wrong format rather than silently
converting, so calling `getPropertyDouble` (this codebase's existing,
correctly-typed helper for genuinely double-typed properties) against
an INT64 property returns `nil` unconditionally. Every bitrate reading
in the stats overlay would have silently shown as absent, with nothing
in the UI or logs pointing at why. Checked and fixed to
`getPropertyInt`, with the bits-per-second-to-kilobits conversion moved
to happen in `Double` *after* the correctly-typed read rather than
during it.

**One property's type could not be fully settled and is flagged as
such rather than guessed with false confidence.** `container-fps` is
implemented internally as a C `float` (`CONF_TYPE_FLOAT`), a third
distinct type from both `int64` and `double` at the C level — but mpv's
client API only defines `MPV_FORMAT_INT64`/`MPV_FORMAT_DOUBLE` for
numeric properties (no float format exists at that boundary), so
`float`s are necessarily promoted to `double` when read from client
code. `getPropertyDouble` is used on that reasoning, documented
in-code as reasoning rather than a confirmed on-device result — this
environment has no way to compile and run the project to check
directly, and a wrong guess here fails safe (a `nil` reading, not a
crash or bad value), which is why this one specific property was
flagged rather than silently assumed correct alongside the others that
were fully verified.

**Lesson:** "grep the manual and get zero results" is evidence the
manual doesn't document something *at that exact name, in that exact
section* — it is not equivalent to "this doesn't exist," and property
aliases are exactly the gap between those two claims. When a
conclusion drawn from documentation search leads to visibly more
complex code than expected (here: manually cross-referencing
`track-list` against selected track ids, instead of reading one
property), that complexity gap is itself worth treating as a signal to
check a level deeper — in this case, the actual property-registration
table in mpv's own source — before accepting the conclusion.

---

## 34. Orientation lock: SwiftUI has no hook for this at all, and the API that does exist is documented-broken on the exact iOS version this project targets

**What was added:** `OrientationLockController` (auto/landscape/
portrait/unlocked modes, matching mpv-android's `cycleOrientation()`/
`updateOrientation()`), a new minimal `AppDelegate` wired in via
`@UIApplicationDelegateAdaptor`, and a tap-cycles/long-press-picks
orientation control in `MPVPlayerView`'s top bar.

**This is the one feature in this whole project that required adding
new app-lifecycle infrastructure (an `AppDelegate`) specifically
because SwiftUI's own `App` protocol has no equivalent hook at all** —
confirmed across every source consulted on this topic, not just one:
`application(_:supportedInterfaceOrientationsFor:)` is only ever called
on a `UIApplicationDelegate`, full stop. A separate source
(a Medium writeup specifically about SwiftUI orientation locking)
documented having tried the obvious SwiftUI-native-feeling workarounds
first — `windowScene?.effectiveGeometry.setValue(true, forKey:
"isInterfaceOrientationLocked")` and equivalent KVC calls on
`rootViewController` — and reported both **crash** with "this class is
not key value coding-compliant for the key ...". That's a materially
different situation from most of this project's other iOS-API
research, where the question was "which of several working approaches
is correct" — here, most of the approaches that don't involve adding an
`AppDelegate` don't work at all.

**The API that does exist is separately reported broken on iOS 16
specifically, in an Apple Developer Forums thread from an Apple
context** (not a random blog): `application:supportedInterfaceOrientationsForWindow:`
"does not lock the orientation" on iOS 16, changing orientation before
asking the delegate rather than after, backwards from its own
documented sequencing — with multiple independent forum replies
confirming the same symptom, not one isolated report. The **working**
combination synthesized from several forum threads describing the same
migration is: `UIWindowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))`
(the iOS 16+ replacement for directly setting device orientation) paired
with `UIViewController.setNeedsUpdateOfSupportedInterfaceOrientations()`
on the current root view controller, so the delegate's
`supportedInterfaceOrientationsFor:` gets explicitly re-queried rather
than relying on whatever the (reportedly broken) automatic re-check
does. `OrientationLockController.applyChange()` calls both, in that
order, specifically because no single source described only one of
them as sufficient.

**Design choices carried over from mpv-android, and one deliberately
not:** the auto-mode aspect-ratio threshold (treating near-square video
as "let the system rotate freely" rather than force-locking) mirrors
mpv-android's own `ASPECT_RATIO_MIN`-gated behavior in
`updateOrientation()`, though the specific numeric threshold (1.2) is
this project's own choice, not a value read out of mpv-android's
source — recorded as such rather than implied to be a ported constant.
`cycleOrientation()` mirrors mpv-android's exactly (a two-state
landscape/portrait toggle, not a cycle through all four `Mode` cases) —
mpv-android's own cycle button never reaches its `auto`/unspecified
state, that's only reachable from its separate settings screen, and
this project's tap-cycles/long-press-for-full-picker control preserves
that same split (tap = the two-state toggle, long-press = all four
modes) rather than inventing a different interaction model.

**Lesson:** when *every* source consulted on a topic converges on "the
direct/obvious way doesn't exist for this UI framework" and "the
documented replacement API is itself reported broken on the exact OS
version in question," that's a meaningfully different research
situation from the usual "which approach is correct" question this
project has faced for most other features — it calls for synthesizing
a specific combination from multiple problem-reports and their
replies (not just one canonical doc page), and for being explicit in
the resulting code and commit history about which parts of that
combination came from which specific report, since no single source
described the whole working solution end to end.

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

---

## 36. `touchMoved` called with the wrong argument label: `at:` instead of `to:`

**What happened:** CI failed while building `MPVIOSPlayer` for the iOS
Simulator with:
```
error: incorrect argument label in call (have 'at:', expected 'to:')
    if viewModel.touchGestures.touchMoved(at: value.location) {
```
`MPVTouchGestures` (added in entry #26) declares three touch-forwarding
methods: `touchDown(at:)`, `touchMoved(to:)`, and `touchUp(at:)` — two of
the three use `at:`, but `touchMoved` uses `to:`. `MPVPlayerView`'s
`DragGesture` handler calls all three from the same `onChanged`/`onEnded`
closures, and the `touchMoved` call site was written with the same `at:`
label as its neighbors rather than the label the method actually
declares.

**Actual fix:** changed the call site in `MPVPlayerView.swift` from
`touchGestures.touchMoved(at: value.location)` to
`touchGestures.touchMoved(to: value.location)`, matching
`MPVTouchGestures.swift`'s existing declaration. The method's own
signature was left as-is: `touchDown`/`touchUp` model a point the touch
*is at*, while `touchMoved` models a point the touch *moved to* — the
inconsistency is a pre-existing naming choice in the gesture API, not a
bug, so the fix corrects the caller rather than renaming the API and
risking other callers or future ports (e.g. mpv-android parity) expecting
`to:`.

**Verification:** confirmed via the actual CI failure log rather than
inspection alone, then grepped `mpv-ios-player/` and `MPVKit/` for every
call site of `touchDown`, `touchMoved`, and `touchUp` to check no other
call used the wrong label — `MPVPlayerView.swift`'s single `touchMoved`
call was the only mismatch; `touchDown(at:)` and `touchUp(at:)` were
already correct.

**Lesson:** a set of sibling methods that are mostly-but-not-entirely
consistent in argument-label naming is an easy trap when writing a call
site by pattern-matching neighboring lines rather than checking each
method's actual signature — the compiler catches it immediately here
(Swift argument labels are part of the function's type), but the same
copy-neighboring-line habit could silently pick the wrong *value* instead
of just the wrong *label* in a language without that guarantee. Worth a
quick grep for a method's declaration before calling it in a block that
already calls two or three of its close siblings.

---

## General patterns worth carrying forward

A few things that recurred across multiple entries above, worth stating
once at the end rather than repeating per-entry:

1. **Read the actual current upstream source before writing a fix**, not
   just the error message or a search-engine snippet. Multiple fixes here
   (Lua's `LUA_USE_IOS` guard, libxml2's option list, the avfoundation
   guards) would have been wrong or incomplete if based on assumption or
   on documentation for a different version than what's actually pinned.
2. **Check whether a reference implementation already solved the same
   problem.** mpv-android's own build scripts, checked directly rather
   than approximated from memory, resolved or clarified several of the
   entries above (`INSTALL=ginstall`, libxml2's minimal flag set,
   `v_ci_ffmpeg`-style CI pinning).
3. **Test-apply and balance-check any patch before trusting a diff.** The
   `#if`/`#endif` balance checker described in `patches/mpv/README.md`
   caught a real bug in our own patch-writing process (a guard we forgot
   to close) before it reached CI.
4. **A fix to build configuration can need a cache-invalidation
   companion.** The `objc`/`objcpp` crossfile fix, and later the
   `-fembed-bitcode` removal, both needed a manual cache-key bump (what
   started as `CROSSFILE_REV` and was later renamed `BUILD_LOGIC_REV` once
   it was clearly covering more than just crossfile generation) — because
   the CI cache key was keyed only on dependency versions, not on
   build-script logic changes. Two unrelated fixes needing the same kind
   of cache bump is itself a signal this was worth generalizing into one
   clearly-named, clearly-documented marker rather than inventing a new
   one-off each time.
5. **A guard condition covering "too much" is a recurring failure mode**
   in a codebase ported across platforms incrementally over years (as
   mpv's iOS/macOS audio code has been) — the same imprecise
   `HAVE_COREAUDIO || HAVE_AVFOUNDATION` pattern caused CI failures in two
   different functions of the same file (entries 10, 11), and then showed
   up again one level higher, in `meson.build`'s own file-list logic
   rather than an in-file `#if` (entry 12). Worth checking a build
   system's feature-to-file mapping, not just in-file guards, once this
   pattern has been found once in a codebase — it tends to repeat at
   multiple layers of the same project, not just within a single file.
6. **A past fix being documented doesn't mean it was correct.** Entry 8
   is the clearest example: an earlier fix for a `-Bsymbolic`-related log
   line was itself based on an option (`b_symbolic`) that never existed in
   meson at all, and the underlying "problem" turned out to be mpv's own
   harmless capability-detection code working as designed — not a build
   failure. It took a second look (prompted by the same symptom
   reappearing in a later CI run) to trace the log line to its actual
   source and realize the original fix never did anything. Worth revisiting
   old fixes with the same rigor as new bugs when a symptom that was
   supposedly already resolved shows up again, rather than assuming the
   earlier fix must have been right and looking elsewhere first.
7. **A symptom caused by a category of thing can have more than one
   independent source.** Entry 13's four rounds are the clearest example
   in this whole log: an "embedded LLVM bitcode/IR" symptom was first
   (correctly) traced to an explicit `-fembed-bitcode` flag, but after
   removing it the identical symptom persisted — because LTO
   (`-Db_lto=true`, a meson option with no naming resemblance to
   "bitcode" at all) produces the same class of embedded-IR object via a
   completely different, unrelated mechanism. Once a bug is understood at
   the level of "what category of thing causes this," it's worth
   searching for every known way to produce that category, not stopping
   at the first match — grepping a codebase for the literal string that
   fixed a similar bug before will miss a different flag causing the same
   underlying problem.
8. **A fix that looks plausible and matches the error message isn't
   confirmed until the next CI run actually passes.** Entry 19 shipped an
   explicit closure-type annotation as a fix for an "ambiguous use of
   sync(execute:)" error, reasoning correctly about *what* Dispatch's two
   overloads were but incompletely about *why* the ambiguity existed —
   and the exact same error reappeared, completely unchanged, in the very
   next CI run, with the "fix" plainly visible in the quoted failing
   line. The real fix (extracting nested generic calls out of the
---