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
