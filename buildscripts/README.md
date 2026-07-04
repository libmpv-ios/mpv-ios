# mpv-ios build scripts

Cross-compiles libmpv and all of its dependencies for iOS (device + simulator,
arm64 + x86_64) and packages the result as `Libmpv.xcframework`, ready to be
linked into an Xcode project or consumed via Swift Package Manager.

This mirrors the structure of [mpv-android's buildscripts](https://github.com/mpv-android/mpv-android/tree/master/buildscripts),
adapted for Apple's toolchain (Xcode clang instead of the Android NDK,
XCFramework instead of `.so` + Gradle).

## Requirements

- **macOS** (Xcode cross-compilation cannot run on Linux/Windows — Apple's
  linker, codesigning, and SDKs are macOS-only)
- Xcode + Command Line Tools: `xcode-select --install`
- Homebrew packages:
  ```
  brew install meson ninja pkg-config gnu-sed nasm autoconf automake libtool
  ```
- `git`, `curl` (both ship with macOS)

## Usage

```bash
cd buildscripts

# 1. Download all dependency sources (mpv, ffmpeg, dav1d, libass, etc.)
./download.sh

# 2. Build every dependency + libmpv for all three platform slices
#    (device arm64, simulator arm64, simulator x86_64)
./buildall.sh --all-platforms

# 3. Merge the per-platform static libs and produce the XCFramework
#    (must run from the repo root — this script expects to be invoked as
#    ./buildscripts/scripts/mpv-ios.sh from one level above buildscripts/)
cd ..
./buildscripts/scripts/mpv-ios.sh build
```

After step 3, `Libmpv.xcframework` will exist at the repo root. Copy or
symlink it into `MPVKit/Frameworks/Libmpv.xcframework` so the Swift package
can find it.

### Building a single platform slice

Useful while iterating, since a full `--all-platforms` build takes a while:

```bash
./buildall.sh --platform ios-arm64          # device only
./buildall.sh --platform ios-arm64-simulator
./buildall.sh --platform ios-x86_64-simulator
```

### Cleaning

```bash
./buildall.sh --clean [target]     # clean one target's build dir
(cd .. && ./buildscripts/scripts/mpv-ios.sh clean)   # remove the assembled XCFramework
rm -rf prefix deps                 # nuke everything and start over
```

## Dependency tree

Same topology as mpv-android:

```
mbedtls, dav1d, libxml2 ─┬─> ffmpeg ─┐
freetype2 ───────────────┤           │
fribidi ──────────────────┼─> libass ─┼─> mpv ─> mpv-ios (XCFramework)
harfbuzz ─────────────────┤           │
unibreak ─────────────────┘           │
lua ───────────────────────────────────┤
libplacebo ─────────────────────────────┘
```

Notable differences from the Android build:

- **No fontconfig.** iOS provides CoreText; libass and harfbuzz are built
  with their CoreText backends instead of fontconfig + libxml2-based font
  matching.
- **VideoToolbox instead of MediaCodec/JNI.** ffmpeg is configured with
  `--enable-videotoolbox` for hardware decode, replacing Android's
  `--enable-jni --enable-mediacodec`.
- **OpenGL ES via EAGL, not Metal.** libmpv's public render API
  (`include/mpv/render.h`) only defines two backends: OpenGL and a
  CPU/software renderer — there is no Metal render-API type. mpv's Metal
  usage on Apple platforms goes through Vulkan+MoltenVK inside its own
  AppKit-based window path (`video/out/vulkan/context_mac.m`), which
  requires `NSApplication` and does not run on iOS. The actual supported
  iOS path — and the one mpv upstream itself ships (see
  `video/out/hwdec/hwdec_ios_gl.m`, gated by meson's `ios-gl` feature) — is
  `MPV_RENDER_API_TYPE_OPENGL` rendering into an FBO backed by a
  `CAEAGLLayer`, with VideoToolbox hardware frames imported via
  `CVOpenGLESTextureCache` for zero-copy decode. This build enables
  `-Dgl=enabled -Dios-gl=enabled` and disables Vulkan entirely.
- **Static linking throughout.** Everything is merged into one static
  `libmpv-combined.a` per platform via `libtool -static`, then wrapped in an
  XCFramework — App Store apps can't casually ship arbitrary `.dylib`s the
  way Android apps ship `.so` files.

## Output

```
Libmpv.xcframework/
├── ios-arm64/                  (device)
│   ├── Headers/
│   └── libmpv-combined.a
└── ios-arm64_x86_64-simulator/ (simulator, fat binary)
    ├── Headers/
    └── libmpv-combined.a
```
