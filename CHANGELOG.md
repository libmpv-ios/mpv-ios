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

- `buildscripts/download.sh`: a dead variable with broken syntax
  (`docs/RESEARCH.md` #2).
- `buildscripts/buildall.sh`: `declare -g` doesn't work in macOS's bash
  3.2 (`docs/RESEARCH.md` #3).
- `buildscripts/include/path.sh`: `INSTALL=install` vs
  `INSTALL=$(which ginstall)` (`docs/RESEARCH.md` #4).
- libxml2: meson build options removed upstream, twice in a row
  (`docs/RESEARCH.md` #5).
- mpv's meson cross file needed an Objective-C compiler declared
  (`docs/RESEARCH.md` #6).
- Legacy `config.sub` didn't recognize modern Apple simulator triples
  (`docs/RESEARCH.md` #7).
- A stray `-Bsymbolic` "fix" for a harmless mpv capability-detection log
  line, which was never actually broken (`docs/RESEARCH.md` #8).
- Lua 5.2.4's `os.execute()` calling `system()`, unavailable on iOS
  (`docs/RESEARCH.md` #9).
- `AudioDeviceID` referenced in avfoundation/coreaudio code that doesn't
  exist on iOS, across three related files/functions found over three
  separate CI runs (`docs/RESEARCH.md` #10–12).
- A four-round investigation into embedded LLVM bitcode/IR: an explicit
  `-fembed-bitcode` flag, then a misleading error, then a real build
  ordering bug, and finally an unrelated LTO flag producing the same
  symptom (`docs/RESEARCH.md` #13).
- Swift Package Manager not propagating a binaryTarget's headers
  automatically (`docs/RESEARCH.md` #15).
- `swift build` unable to build a binaryTarget package for iOS at all,
  requiring an Xcode-based build instead (`docs/RESEARCH.md` #16).
- Swift/C interop issues surfaced while wiring `MPVKit` to the built
  framework: invalid `import Libmpv` of a non-Swift binary target
  (`docs/RESEARCH.md` #17), C enum bridging mismatches
  (`docs/RESEARCH.md` #18), `DispatchQueue.sync` overload ambiguity
  (`docs/RESEARCH.md` #19), and an Xcode 16.2 change in how a
  `const char *` macro imports into Swift (`docs/RESEARCH.md` #20).
- Per-frame render call in `MPVGLView.swift` passing `&fbo`/`&flipY`/
  `&skip` inline inside an `mpv_render_param` array literal, whose
  pointers didn't outlive the call to `mpv_render_context_render`; now
  scoped explicitly via `withUnsafeMutablePointer` (`docs/RESEARCH.md`
  #21).
- `project.yml`'s `MPVIOSPlayer` app target deployment target raised from
  14.0 to 16.0 to match the iOS 16+ SwiftUI APIs (`NavigationStack`,
  `@Environment(\.dismiss)`) the example app's own source already uses;
  `MPVKit`'s own iOS 14.0+ floor is unaffected (`docs/RESEARCH.md` #22).

<!--
## [X.Y.Z] - YYYY-MM-DD

### Added
### Changed
### Fixed
### Removed
### Security
-->
