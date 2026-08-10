// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MPVKit",
    platforms: [
        .iOS(.v14),
        .tvOS(.v14)
    ],
    products: [
        .library(
            name: "MPVKit",
            targets: ["MPVKit"]
        ),
    ],
    dependencies: [],
    targets: [
        // Binary target: the cross-compiled libmpv + all its static
        // dependencies, produced by buildscripts/scripts/mpv-ios.sh
        .binaryTarget(
            name: "Libmpv",
            path: "Frameworks/Libmpv.xcframework"
        ),
        // Thin C shim exposing anything libmpv's headers don't cleanly
        // expose to Swift as-is (mostly needed for render API callbacks,
        // which use raw C function pointers that Swift closures can't
        // satisfy directly).
        //
        // headerSearchPath entries below are REQUIRED, not optional or
        // redundant with the Libmpv dependency above: Swift Package
        // Manager does not automatically propagate a binaryTarget's
        // headers into a dependent C/Objective-C target's include path
        // (a well-documented SPM limitation - see
        // https://github.com/swiftlang/swift-package-manager/issues/7626
        // and https://forums.swift.org/t/binary-target-infer-header-search-path/72222
        // for confirmation this affects other projects identically).
        // Without these, cmpv_shim.c's `#include <mpv/client.h>` fails
        // with "file not found" even though Libmpv is listed as a
        // dependency. The two paths cover both platform-slice folder
        // names xcodebuild -create-xcframework actually produces for
        // this project's XCFramework (see buildscripts/scripts/mpv-ios.sh):
        // a plain device slice ("ios-arm64") and a lipo-merged simulator
        // fat binary slice ("ios-arm64_x86_64-simulator"). A path that
        // doesn't exist for the platform currently being built is simply
        // ignored by the compiler, so listing both unconditionally is
        // safe for every build target (device or simulator).
        .target(
            name: "CMPV",
            dependencies: ["Libmpv"],
            path: "Sources/CMPV",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../Frameworks/Libmpv.xcframework/ios-arm64/Headers"),
                .headerSearchPath("../../Frameworks/Libmpv.xcframework/ios-arm64_x86_64-simulator/Headers"),
            ]
        ),
        // The Swift-facing API: MPVCore, MPVProperty, MPVEvent, etc.
        .target(
            name: "MPVKit",
            dependencies: ["CMPV", "Libmpv"],
            path: "Sources/MPVKit",
            linkerSettings: [
                // libmpv-combined.a bundles object code from ffmpeg,
                // libass, and Lua that calls into these three Apple/BSD
                // system libraries (zlib for PNG/subtitle-stream
                // decompression, bz2 for Matroska block decompression,
                // iconv for subtitle charset conversion in ffmpeg's own
                // decode path and in libass, independent of mpv's own
                // -Diconv=disabled meson option, which only controls
                // mpv's *own* charset-conversion code, not ffmpeg's or
                // libass's). A static library never pulls in its own
                // system-library dependencies automatically the way a
                // dynamic framework does - whatever links the final
                // combined static lib has to declare them explicitly, or
                // the app-level link fails with "Undefined symbols" for
                // _BZ2_bz*, _deflate*/_inflate*, and _iconv* despite
                // MPVKit itself compiling and linking cleanly (found in
                // CI: MPVKit's own module compiled fine; the failure only
                // showed up building the mpv-ios-player *app* target,
                // which is the first point anything actually produces a
                // final Mach-O binary out of libmpv-combined.a).
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                // mpv is built with -Davfoundation=enabled -Daudiounit=enabled
                // (audio output) and ffmpeg with --enable-videotoolbox
                // (hardware decode) - see buildscripts/scripts/mpv.sh and
                // ffmpeg.sh. Object code from those paths
                // (audio_out_ao_avfoundation.m.o, videotoolbox.o) needed
                // these frameworks, but nothing declared them explicitly
                // anywhere in this package before, because a plain .a
                // build never required them - only building an actual app
                // binary against the combined static lib does.
                // CoreAudioTypes specifically: Xcode's own auto-linking
                // tried to infer it from AVFoundation/CoreAudio type
                // metadata embedded in the combined static lib's object
                // files, and failed with "framework 'CoreAudioTypes' not
                // found" - listing it explicitly here resolves that.
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
            ]
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx17
)
