# Contributing to mpv-ios

This project ports [mpv-android](https://github.com/mpv-android/mpv-android)'s
approach (cross-compiled libmpv + a native UI) to iOS. It's functional but
young, and there are real, concrete gaps where help is genuinely useful —
listed below rather than a generic "PRs welcome."

## Why contribute to this project

### For iOS users, directly

Most iOS video players fall into one of two camps: they use `AVPlayer`
(Apple's built-in player, which has real gaps — no MKV support, limited
subtitle format support, no advanced audio/video filter chain, no support
for many container/codec combinations common outside the US/mainstream-
streaming world), or they're closed-source apps with ads, subscriptions,
or upload/analytics behavior a privacy-conscious user might not want.

libmpv is different: it's the same playback engine that VLC, IINA (macOS),
and mpv-android are built on — it plays nearly anything (MKV, obscure
subtitle formats, unusual audio codecs, unusual container/stream
combinations) that AVPlayer simply refuses to open. An iOS app built on it
gives iOS users a capability gap that currently doesn't have a great
free/open answer on the platform: a player as capable as the desktop mpv
experience, natively on iPhone/iPad. Every contribution that moves this
project closer to a polished, real-device-tested app is a contribution
toward iOS actually having that option.

### For you, as a contributor

- **Real cross-compilation experience.** Very few day-to-day iOS
  development tasks involve cross-compiling a C/C++ dependency tree
  (ffmpeg, libass, libplacebo, mbedtls, etc.) for multiple Apple
  architectures and merging them into an XCFramework. This project is a
  concrete, hands-on way to learn that — skills directly transferable to
  any other project that wraps a native C/C++ library for iOS/macOS (which
  describes a large fraction of performance-sensitive iOS SDKs: image
  processing, ML runtimes, codecs, crypto libraries).
- **Real render-pipeline experience.** `MPVGLView.swift` is a working
  example of driving OpenGL ES via EAGL against an external render API,
  including the callback-trampoline pattern needed to bridge a C library's
  update callbacks into Swift safely. This pattern — C library owns the
  render loop, Swift/UIKit owns the presentable surface — recurs anywhere
  a native media/graphics library needs to be embedded in an iOS app.
- **A visible, usable result.** Unlike many learning projects, contributions
  here produce something a real user can install and use immediately —
  your fix to gesture-seek, or your signed-release setup, or your icon
  redraw, ends up in someone's hands, not just in a private repo.
- **A project with unusually detailed "why" documentation.** Because this
  codebase was built iteratively with real debugging along the way
  (bash-version incompatibilities, file-permission issues, an entire
  render-backend approach that was tried, found not to exist in libmpv,
  and corrected), the comments throughout explain *why* things are the way
  they are, not just what they do — useful if you're newer to iOS native
  development and want to learn from a project's actual decision history
  rather than only its final state.

### For the broader iOS development community

- **A reference implementation.** There is comparatively little public,
  well-commented example code showing libmpv wired into a modern SwiftUI
  app via the render API (as opposed to, say, wrapping `AVPlayer` or using
  a higher-level closed-source SDK). Improvements here become a resource
  other developers can learn from or build on, the way mpv-android itself
  has served that role on the Android side for years.
- **Pressure-testing an approach other forks can reuse.** Projects like
  mpvKt and mpvEx (Kotlin/Compose forks of mpv-android's approach) show
  there's an active ecosystem of people building on top of "libmpv +
  modern native UI framework." A solid, maintained mpv-ios equivalent
  gives the iOS side of that ecosystem the same kind of foundation to fork
  and extend.

## Before you start

1. Read the main [README.md](README.md) — especially "What's real here vs.
   what you still need to do" and "Architecture notes" — so you know what's
   already been tried, and why some earlier approaches (e.g. a Metal render
   backend) were abandoned for what's here now.
2. Check [ROADMAP.md](ROADMAP.md) for the current phase and priorities —
   it explains *why* certain things are sequenced the way they are (e.g.
   why player features come after real-device validation, not before).
3. You'll need a Mac to build and test changes to `MPVKit` or
   `buildscripts/`. Pure documentation or workflow-file contributions can
   often be done without one.
4. See "How to contribute, step by step" below before opening a PR —
   almost every contribution should start with an issue, not a PR directly.

## How to contribute, step by step

This project uses the issue templates under `.github/ISSUE_TEMPLATE/` as
the required starting point for any non-trivial contribution. This isn't
bureaucracy for its own sake — it exists because:

- it gives a place to confirm an approach *before* time is spent writing
  code that might not fit the project's direction,
- it prevents two people from independently working on the same thing, and
- for bug fixes especially, the structured fields (device/OS/Xcode version,
  full logs, reproduction steps) are usually what actually makes a fix
  possible — a PR that "fixes a bug" no one can reproduce is much harder to
  review and merge than one with a linked issue containing the full context.

**The process:**

1. **Search first.** Check [open and closed issues](../../issues?q=is%3Aissue)
   and [open PRs](../../pulls) for anything related to what you're about to
   do. If it's already tracked, comment there instead of opening a
   duplicate.
2. **Open an issue using the right template** (Issues → New Issue):
   - Found something broken? Use **Bug Report**.
   - Hit a failure in `buildscripts/` or a GitHub Actions run? Use
     **Build / CI Failure** — it asks for the exact step and full log,
     which is almost always what's needed to actually diagnose a
     cross-compilation issue.
   - Want to propose something new (a player feature, an API addition to
     MPVKit, etc.)? Use **Feature Request**, including the use case, not
     just the ask.
   - Not sure, or just want clarification on how something works? Use
     **Question** — but check README.md/TESTING.md/CONTRIBUTING.md first,
     since many common questions are already answered there.
3. **Wait for a signal before starting large work.** For small, obvious
   fixes (a typo, a broken link, an off-by-one in a comment) feel free to
   just open the PR and reference "Closes #<issue-number>" in it. For
   anything larger — a new feature, a refactor, a new workflow — wait for
   at least a brief acknowledgment on the issue first. This is the single
   biggest thing that prevents wasted effort on both sides.
4. **Reference the issue in your PR.** Use a closing keyword
   (`Closes #123`, `Fixes #123`) in the PR description so it links
   automatically and closes the issue when merged.
5. **Follow the code style and testing notes below** before requesting
   review.

## Where help is genuinely needed right now

### Signed release builds / TestFlight (biggest gap)
There's currently no Apple Developer Program account behind this project,
so `release.yml` only publishes `Libmpv.xcframework.zip` and an *unsigned*
Simulator build — there's no signed `.ipa` for real-device installation or
TestFlight distribution. If you have a paid Apple Developer account and are
willing to either:
- help set up fastlane match / manual certificate + provisioning profile
  secrets so CI can produce signed builds, or
- sponsor/co-maintain a dedicated Developer Program account for this
  project,

this would unlock real-device testing and TestFlight betas for everyone,
not just people with a Mac. See the "Testing without a Mac or iPhone"
section of the README for the current no-signing-required alternative.

### Native 1024×1024 app icon
The current `AppIcon.appiconset` is a 512×512 source (mpv-android's own
launcher icon) upscaled 2x. It's fine for development but not ideal for an
App Store submission. A cleanly redrawn/vectorized 1024×1024 icon (mpv's
own `mpv_logo.xml` is a vector drawable and could be a good starting point
for a from-scratch redraw) would be a welcome, self-contained contribution.

### Real-device testing and performance feedback
Everything in this repo has been built and reasoned through without access
to a physical iPhone or a Mac during development (see the git history /
issue tracker for that context). If you have a real device, testing actual
playback — hardware decode via VideoToolbox, thermal behavior during long
playback, battery drain, PiP, background audio — and reporting what you
find (good or bad) is extremely valuable and doesn't require writing any
code.

### Dependency version bumps
`buildscripts/include/depinfo.sh` pins exact versions for `lua`, `freetype`,
`harfbuzz`, `fribidi`, `mbedtls`, `libxml2`, and `unibreak`. These aren't
covered by Dependabot (see `.github/dependabot.yml`'s comments for why —
no package-ecosystem exists for versions embedded in a shell script), so
`.github/workflows/dependency-check.yml` runs weekly and opens a PR
automatically whenever one of these has a newer upstream release. `mpv`,
`ffmpeg`, `dav1d`, `libass`, and `libplacebo` are already built from their
latest default branch on every run, so those don't need version bumps at
all.

You don't need to open these bump PRs yourself — where help is genuinely
useful is **reviewing and fixing them** when CI fails on one. A version
bump can break the build (a real example: libxml2 2.14 removed its `ftp`
meson option entirely, breaking the flag `libxml2.sh` was passing) —
turning a red CI run on one of these PRs into a green one, usually by
updating a flag in the corresponding `buildscripts/scripts/<dep>.sh`, is a
small, well-scoped, and genuinely helpful contribution.

### Player features
Compared to mpv-android's PlayerActivity, `MPVPlayerView`/`PlayerViewModel`
currently cover the basics (play/pause/seek/volume/tracks) but not, for
example: chapter navigation, subtitle style/delay adjustment, A-B repeat,
playback speed presets, gesture-based seek/volume/brightness (mpv-android
has swipe gestures; this doesn't yet), or a proper Now Playing / remote
control center integration. Any of these, implemented as a focused PR
against `MPVPlayer.swift` (core) + `MPVPlayerView.swift` (UI), is welcome.

### Build script robustness
The `buildscripts/` cross-compilation pipeline has been debugged
iteratively against real CI failures (see closed issues/PRs for examples:
bash 3.2 vs 4+ incompatibilities, file permission issues, path-resolution
bugs). More dependency version combinations, Xcode versions, and macOS
runner images than have been tested so far exist — if you hit a build
failure not already covered, a fix plus a one-line comment explaining *why*
(matching the style already used throughout `buildscripts/`) is ideal.

## Code style

- Shell scripts: match the existing style in `buildscripts/` — tabs for
  indentation, a comment above any non-obvious flag explaining what it does
  and why (especially where it differs from mpv-android's equivalent
  script), and `bash -n script.sh` run locally before committing to catch
  syntax errors early (this project's early CI runs caught several this
  way — cheaper to catch before pushing).
- Swift: standard Swift API design guidelines. Match `MPVKit`'s existing
  pattern of a doc comment on public APIs noting the mpv-android equivalent
  where one exists, since that cross-reference has been useful for
  understanding *why* something is implemented the way it is.
- Keep PRs focused — one logical change per PR is much easier to review
  and, if needed, revert.

## Testing your changes

- For `MPVKit`/`buildscripts` changes: you'll need to run the build
  pipeline on a Mac (see README's Build steps) since GitHub-hosted macOS
  runners are the only CI option and a full pipeline run takes a while —
  faster to catch build errors locally first where possible.
- For `mpv-ios-player` UI changes: the `appetize-preview.yml` workflow (see
  [TESTING.md](TESTING.md)) lets you validate UI changes without a Mac or
  iPhone, using a free Appetize.io account.
- Run `bash -n` on any shell script you touch, and check YAML workflow
  syntax (`python3 -c "import yaml; yaml.safe_load(open('file.yml'))"` or
  similar) before pushing — both categories of error have caused real CI
  failures during this project's development, and both are free to catch
  locally.

## Thank you

Even small fixes — a typo in a comment, a broken link, a version bump —
are genuinely appreciated. See "How to contribute, step by step" above for
the process, and the issue templates under `.github/ISSUE_TEMPLATE/` to get
started.
