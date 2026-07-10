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
            path: "Sources/MPVKit"
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx17
)
