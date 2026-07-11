---
id: release-process
title: Release Process
sidebar_position: 4
---


This is the maintainer checklist for cutting a release. If you're a
contributor rather than the maintainer, you shouldn't need this — see
[TESTING.md](../TESTING.md) instead for how to test changes from a fork.

## Framework release (Libmpv.xcframework)

This is the release most consumers of this repo actually need — the
prebuilt native library, published so contributors and forks don't have
to cross-compile libmpv themselves (see `appetize-preview.yml`'s reliance
on this).

1. Decide whether this is a routine dependency-bump release (from a merged
   `dependency-check.yml` PR) or a manual release.
2. On `main`/`master`, confirm `build.yml` is currently green. Don't cut a
   release from a red build.
3. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z` (semantic versioning;
   see "Versioning" below for what bumps which number).
4. `release.yml` runs automatically on the tag push. Watch it in the
   Actions tab.
5. Once green, check the Releases page for the new release: it should
   have `Libmpv.xcframework.zip`, `MPVKit-vX.Y.Z.zip`, and `checksum.txt`
   attached.
6. Write release notes. At minimum, include the exact version/commit
   pinned for each dependency at release time — pull these directly from
   `buildscripts/include/depinfo.sh` (`v_lua`, `v_freetype`, `v_harfbuzz`,
   `v_fribidi`, `v_mbedtls`, `v_libxml2`, `v_unibreak`, and the five
   `v_ci_*` git-ref pins for mpv/ffmpeg/dav1d/libass/libplacebo). This
   matches the level of detail mpv-android publishes in its own release
   notes, and is genuinely useful for anyone debugging a build issue later
   ("was this broken in v1.2.0, or did it start with the libass bump in
   v1.3.0?").
7. If anything in "Architecture notes" (main README) changed as part of
   this release — a render backend swap, a new hwdec path, etc. — call
   that out explicitly in the release notes, the way this project's own
   README already documents the Metal-backend correction.

## App release (signed .ipa / TestFlight / App Store)

**Not yet applicable** — this project does not currently have a signed
release pipeline (see ROADMAP.md's Phase 3 and CONTRIBUTING.md's "Signed
release builds / TestFlight" section for why: it's blocked on an Apple
Developer Program account). This section will be filled in once that's
set up. For now, the only way to run the actual app is either Appetize.io's
Simulator preview (see TESTING.md) or building it yourself in Xcode on
your own Mac with your own signing.

## Versioning

Semantic versioning (`vMAJOR.MINOR.PATCH`):

- **PATCH**: a dependency version bump that doesn't change any public
  MPVKit API, a build-script fix, a docs update.
- **MINOR**: a new MPVKit API (a new method on `MPVCore`/`MPVPlayer`/etc.),
  a new app feature, a dependency major-version bump that's still backward
  compatible.
- **MAJOR**: a breaking change to MPVKit's public API (a removed or
  renamed method, a changed method signature), a minimum-iOS-version bump,
  or a render-backend change (the kind of thing documented in the main
  README's "Architecture notes").

## Post-release

1. Verify the Appetize preview workflow still works against the new
   release (run `appetize-preview.yml` manually once after a framework
   release, since it downloads from "the latest release" — see that
   workflow's comments).
2. If ROADMAP.md had this release's work listed as an open item, check it
   off or move it, so the roadmap stays accurate.
