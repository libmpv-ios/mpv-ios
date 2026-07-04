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
        .target(
            name: "CMPV",
            dependencies: ["Libmpv"],
            path: "Sources/CMPV",
            publicHeadersPath: "include"
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
