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
  brew install meson ninja pkg-config gnu-sed nasm autoconf automake libtool coreutils
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
- **Lua's `os.execute()` is stubbed out.** iOS's SDK marks `system(3)` as
  explicitly unavailable (App Store sandboxing forbids arbitrary shell
  execution), which is a hard compile error, not just a runtime failure.
  `-DLUA_USE_IOS` alone doesn't fix this on the Lua 5.2.4 this project
  pins (that guard was only added in Lua 5.4, and mpv itself will never
  support Lua 5.3+ — see `lua.sh`'s comments for the full explanation), so
  `lua.sh` force-includes a small header that redefines `system()` to a
  stub before it's ever referenced. `os.execute()` calls from any Lua
  script become a no-op reporting failure, rather than the build failing
  to compile at all.
- **The meson cross file declares an Objective-C compiler.** mpv's iOS
  VideoToolbox/GLES hardware-decode interop
  (`video/out/hwdec/hwdec_ios_gl.m`) is Objective-C, so meson needs `objc`
  and `objcpp` entries under `[binaries]` in `crossfile.txt` — without
  them, `meson setup` for mpv itself fails with `'objc' compiler binary
  not defined in cross file [binaries] section`. Since Apple's `clang`
  handles C, C++, and Objective-C from the same binary depending on file
  extension, this just points `objc`/`objcpp` at the same `clang`/`clang++`
  already used for `c`/`cpp`. See `buildall.sh`'s `setup_prefix()`.
- **mpv's source is patched for iOS before building.** A small number of
  mpv's audio-output files (`ao_avfoundation.m` and the CoreAudio utility
  files it shares code with) call macOS-only APIs from otherwise
  iOS-compatible code paths. Rather than disabling those features
  entirely, `buildscripts/patches/mpv/` contains small, targeted patches
  that narrow the actual problem down to the specific unavailable
  call/type, applied automatically by `download.sh` via
  `include/apply-mpv-patches.sh`. See `patches/mpv/README.md` for exactly
  what each patch does and why. This is what lets `mpv.sh` re-enable
  `-Davfoundation=enabled` (mpv's more modern audio output, with spatial
  audio support) instead of only the more limited `audiounit`.
- **Autotools Simulator Host Triple Compatibility.** Legacy autotools-based 
  dependencies (such as `fribidi`, `harfbuzz`, and `libxml2`) carry outdated 
  `config.sub` scripts that do not recognize modern Apple simulator target triples 
  (e.g., `aarch64-apple-ios-simulator` or `x86_64-apple-ios-simulator`). Rather than 
  manually bootstrapping or updating `config.sub` inside every extraction root 
  during runtime, `buildall.sh` dynamically overrides the `host_triple` variable 
  to a generic Darwin target (`aarch64-apple-darwin` / `x86_64-apple-darwin`) 
  strictly for the simulator configurations. This satisfies the validation constraints 
  of legacy `configure` setups while the actual underlying compilation architecture, 
  sysroot, and deployment constraints remain locked to the iOS Simulator platform 
  via explicit environment flags passed into `CC` and `LDFLAGS`.
- **Meson `-Bsymbolic` Linker Test Override.** During the `mpv` configuration 
  step, modern Meson build scripts attempt to test whether the compiler and linker 
  support the `-Bsymbolic` flag. Because Apple's native linker (`ld`) does 
  not support symbolic linking flags, this configuration test can trigger invalid 
  compiler failures or emit malformed telemetry that breaks strict CI pipelines. 
  To safeguard the build orchestration without modifying upstream source code, 
  `buildall.sh` explicitly injects `b_symbolic = false` under the `[properties]` 
  section of the dynamically generated `crossfile.txt`. This forces Meson to 
  bypass the unsupported linker check entirely, ensuring a clean and uninterrupted 
  build generation phase for both iOS devices and simulators.

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
