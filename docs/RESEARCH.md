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

## 8. meson's `-Bsymbolic` linker probe fails on Apple's linker

**What happened:** during mpv's meson configuration step, a linker
feature-detection probe for `-Bsymbolic` support could trigger spurious
compiler/linker failures or malformed diagnostic output, in a way that
disrupted the wider CI pipeline's error handling.

**Root cause:** meson's build system includes a built-in check for
whether the linker supports `-Bsymbolic` (a linker flag with no
consistent equivalent in Apple's native `ld`). Running this probe against
Apple's linker doesn't fail gracefully the way meson expects from a
"feature not supported" response on more traditional linkers.

**Fix:** `buildall.sh` explicitly injects `b_symbolic = false` under the
`[properties]` section of the generated `crossfile.txt`, so meson never
attempts the probe against Apple's linker in the first place, rather than
letting it run and deal with the fallout. This required no changes to any
upstream source — purely a cross-file configuration addition.

**Lesson:** meson's own built-in feature probes can assume GNU-linker-like
behavior that Apple's linker doesn't match — when a build fails inside a
meson *capability check* rather than inside actual project code, the fix
often belongs in the cross file's `[properties]`/`[built-in options]`
sections (telling meson what to assume) rather than in any dependency's
own build script.

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

## 13. `-fembed-bitcode` produces a corrupted archive on Xcode 16

**What happened:** the XCFramework assembly step (`mpv-ios.sh`'s
`xcodebuild -create-xcframework`) failed with:
```
error: unable to find any architecture information in the binary at
'.../libmpv-combined.a': Unknown header: 0xb17c0de
```

**Root cause:** `ffmpeg.sh` passed `-fembed-bitcode` in
`--extra-cflags`. Bitcode was Apple's now-abandoned intermediate
representation for App Store binaries, deprecated starting Xcode 14 and
non-functional by Xcode 16 (this project's CI toolchain) — passing this
flag doesn't just produce a warning, it produces a genuinely malformed
object file that `libtool`/`xcodebuild` can no longer parse as a valid
archive at all. The hex value in the error, `0xb17c0de`, is not a
coincidence: read as ASCII-ish bytes it's spelling out "bitcode" — the
tool is choking on a bitcode marker it no longer knows how to handle,
misreading it as a corrupt architecture header.

**Fix:** removed `-fembed-bitcode` from `ffmpeg.sh` entirely. It was
carried over from an era of iOS distribution requirements that no longer
apply and actively breaks the build on any current Xcode version.

**A cache-invalidation lesson learned here too:** this project already
had a cache-busting marker (`CROSSFILE_REV`) from the earlier
`objc`/`objcpp` crossfile fix (see entry 6), but its name and comment
described it as being specifically about `crossfile.txt`. Fixing this
bitcode issue needed the exact same kind of cache invalidation (a stale
cached `ios-arm64`/simulator prefix could still contain a
bitcode-corrupted `libavcodec.a` from before this fix), which prompted
renaming the marker to `BUILD_LOGIC_REV` with a broadened comment — it
now explicitly covers *any* change to `buildall.sh` or `scripts/*.sh`
that alters compiled output, not just crossfile generation specifically.

**Lesson:** a build flag that was correct advice years ago (bitcode was
once an actual App Store requirement) can silently become actively
harmful once the platform moves on — worth periodically checking whether
long-standing flags in a build script are still doing what they were
originally added for, especially ones tied to a specific Apple toolchain
era rather than a stable, version-independent concept.

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
