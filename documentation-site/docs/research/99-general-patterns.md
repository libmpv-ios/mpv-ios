---
id: 99-general-patterns
title: "General patterns worth carrying forward"
sidebar_label: "General Patterns"
sidebar_position: 99
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
