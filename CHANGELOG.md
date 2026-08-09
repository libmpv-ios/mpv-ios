# Changelog

All notable changes to this project are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/) as defined
in [docs/release_process.md](docs/release_process.md#versioning).

**How this file is used:** entries go under `[Unreleased]` *as the work
happens* — in the same PR as the change, not reconstructed afterward from
memory or commit messages. When `buildscripts/include/cut-release.sh` runs
at release time, it moves `[Unreleased]`'s content under the new version
heading automatically and generates the GitHub release body from it — see
[docs/release_process.md](docs/release_process.md). An empty `[Unreleased]`
at release time means nothing gets published, so keep it current.

Group entries under `Added`, `Changed`, `Fixed`, `Removed`, or `Security`
(omit sections that don't apply). Write each entry as one clear sentence
describing the user- or contributor-facing effect — link back to a
`docs/RESEARCH.md` entry number for anything with a longer investigation
behind it, rather than repeating that investigation here.

## [Unreleased]

### Added

- OpenGL ES / EAGL rendering path in `MPVGLView.swift`, with VideoToolbox
  hardware-decoded frames imported zero-copy via `CVOpenGLESTextureCache`
  (see `docs/RESEARCH.md` #1).
- `MPVKit` Swift Package: `MPVCore` (lifecycle, commands, event loop),
  `MPVProperty` (typed get/set/observe), `MPVPlayer`
  (play/pause/seek/volume/tracks).
- `mpv-ios-player` example SwiftUI app: file/URL loading, playback
  controls, seek bar, track selection.
- `buildscripts/` cross-compiles libmpv and its full dependency chain
  (mbedtls, dav1d, libxml2, ffmpeg, freetype, fribidi, harfbuzz, unibreak,
  libass, lua, libplacebo) for iOS device + simulator into
  `Libmpv.xcframework`.
- CI: build verification on every push, weekly dependency version-bump
  PRs, and a no-Mac/no-iPhone-required Simulator preview via Appetize.io.

### Fixed

- A cluster of macOS-bash-3.2 and autotools/libtool path issues in the
  build scripts (`docs/RESEARCH.md` #2–4).
- Two rounds of upstream libxml2 meson-option removals (`docs/RESEARCH.md`
  #5).
- Swift/C interop issues surfaced while wiring `MPVKit` to the built
  framework: invalid `import Libmpv` of a non-Swift binary target, C enum
  bridging mismatches, `DispatchQueue.sync` overload ambiguity, and an
  Xcode 16.2 change in how a `const char *` macro imports into Swift
  (`docs/RESEARCH.md` #17–20).

<!--
## [X.Y.Z] - YYYY-MM-DD

### Added
### Changed
### Fixed
### Removed
### Security
-->
