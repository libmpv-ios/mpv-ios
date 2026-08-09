# Release Process

This is the maintainer checklist for cutting a release. If you're a
contributor rather than the maintainer, you shouldn't need this — see
[TESTING.md](../TESTING.md) instead for how to test changes from a fork.

## Framework release (Libmpv.xcframework)

This is the release most consumers of this repo actually need — the
prebuilt native library, published so contributors and forks don't have
to cross-compile libmpv themselves (see `appetize-preview.yml`'s reliance
on this).

**Release notes are written *before* you tag, not after.** As work lands
(in the same PR as the change, ideally), add a bullet under
[CHANGELOG.md](../CHANGELOG.md)'s `[Unreleased]` section describing its
user- or contributor-facing effect. By the time you're ready to cut a
release, the notes already exist — cutting the release just publishes
them. See CHANGELOG.md's own header for the exact format.

1. Decide whether this is a routine dependency-bump release (from a merged
   `dependency-check.yml` PR) or a manual release.
2. On `main`/`master`, confirm `build.yml` is currently green. Don't cut a
   release from a red build.
3. Confirm `CHANGELOG.md`'s `[Unreleased]` section actually has entries —
   if a change landed without a changelog bullet, add it now, before
   tagging. (`release.yml` will refuse to publish an empty release, so
   this is also a hard CI check, not just a reminder.)
4. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z` (semantic versioning;
   see "Versioning" below for what bumps which number).
5. `release.yml` runs automatically on the tag push. Watch it in the
   Actions tab. It will:
   - build `Libmpv.xcframework` and package the release assets as before;
   - generate the release body from `CHANGELOG.md`'s `[Unreleased]`
     section plus a table of every pinned dependency version (pulled live
     from `buildscripts/include/depinfo.sh`), via
     `buildscripts/include/cut-release.sh notes` — see that script for
     exactly what it extracts;
   - publish the GitHub Release with that generated body;
   - move `[Unreleased]`'s content in `CHANGELOG.md` under a new
     `## [vX.Y.Z] - YYYY-MM-DD` heading (via `cut-release.sh bump`) and
     commit that back to the default branch, so `CHANGELOG.md` in the repo
     always matches what was actually published and the next PR starts
     from a clean `[Unreleased]`.
6. Once green, check the Releases page: it should have
   `Libmpv.xcframework.zip`, `MPVKit-vX.Y.Z.zip`, `checksum.txt`, and a
   populated body — no manual note-writing step needed at this point.
7. If anything in "Architecture notes" (main README) changed as part of
   this release — a render backend swap, a new hwdec path, etc. — that
   should already be reflected as a `CHANGELOG.md` entry from step 3,
   the way this project's own README already documents the Metal-backend
   correction.

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
