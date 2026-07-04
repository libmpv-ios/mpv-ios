#!/bin/bash -e
#
# Assembles a Libmpv.xcframework from the static libs built for each
# platform slice (device arm64, simulator arm64, simulator x86_64).
#
# This is the iOS equivalent of mpv-android's mpv-android.sh, which runs
# ndk-build + gradle to produce libmpv.so per ABI and package it into the
# APK. Here we instead lipo-merge simulator slices into one fat static
# library, bundle every dependency's .a together with libmpv.a into a
# single combined static lib per platform, then run `xcodebuild
# -create-xcframework` to produce the final distributable artifact that
# Xcode/SwiftPM can link against.

BUILD="./buildscripts"

. $BUILD/include/path.sh
. $BUILD/include/depinfo.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf Libmpv.xcframework MPVKit/Sources/CMPV/lib
	exit 0
else
	exit 255
fi

OUT="$PWD/build-xcframework"
rm -rf "$OUT"
mkdir -p "$OUT"

# All static libs that need to end up inside libmpv-combined.a.
# mpv itself only depends on these transitively; listing them explicitly
# avoids relying on link order guesses.
LIBNAMES=(
	mpv avformat avcodec avutil avfilter swscale swresample
	ass freetype fribidi harfbuzz unibreak lua54 dav1d
	mbedtls mbedx509 mbedcrypto xml2 placebo
)

combine_platform () {
	local platform=$1
	local prefix="$BUILD/prefix/$platform"

	if [ ! -f "$prefix/lib/libmpv.a" ]; then
		echo >&2 "Warning: libmpv.a not found for $platform, skipping (did buildall.sh run for it?)"
		return 1
	fi

	local libs=()
	for name in "${LIBNAMES[@]}"; do
		for candidate in "$prefix/lib/lib$name.a" "$prefix/lib/lib${name}54.a"; do
			if [ -f "$candidate" ]; then
				libs+=("$candidate")
				break
			fi
		done
	done

	echo >&2 "Combining ${#libs[@]} static libs for $platform..."
	mkdir -p "$OUT/$platform"
	# libtool merges multiple static archives into one, resolving the
	# duplicate-symbol-table issue that a plain `ar` cat would cause.
	libtool -static -o "$OUT/$platform/libmpv-combined.a" "${libs[@]}"
}

# Build each available platform slice
declare -a available_platforms
for platform in ios-arm64 ios-arm64-simulator ios-x86_64-simulator; do
	if combine_platform "$platform"; then
		available_platforms+=("$platform")
	fi
done

if [ ${#available_platforms[@]} -eq 0 ]; then
	echo >&2 "Error: no platform slices were built. Run buildall.sh --all-platforms first."
	exit 1
fi

# lipo the two simulator slices (arm64 + x86_64) into one fat binary,
# since a single XCFramework slot can only target one "simulator" library
# but that library can itself be a multi-arch fat file.
mkdir -p "$OUT/ios-simulator-fat"
sim_libs=()
[ -f "$OUT/ios-arm64-simulator/libmpv-combined.a" ] && sim_libs+=("$OUT/ios-arm64-simulator/libmpv-combined.a")
[ -f "$OUT/ios-x86_64-simulator/libmpv-combined.a" ] && sim_libs+=("$OUT/ios-x86_64-simulator/libmpv-combined.a")

xcframework_args=()

if [ -f "$OUT/ios-arm64/libmpv-combined.a" ]; then
	mkdir -p "$OUT/device-headers/include"
	cp -R "$BUILD/prefix/ios-arm64/include/"* "$OUT/device-headers/include/"
	xcframework_args+=(-library "$OUT/ios-arm64/libmpv-combined.a" -headers "$OUT/device-headers/include")
fi

if [ ${#sim_libs[@]} -gt 1 ]; then
	lipo -create "${sim_libs[@]}" -output "$OUT/ios-simulator-fat/libmpv-combined.a"
	mkdir -p "$OUT/sim-headers/include"
	cp -R "$BUILD/prefix/ios-arm64-simulator/include/"* "$OUT/sim-headers/include/"
	xcframework_args+=(-library "$OUT/ios-simulator-fat/libmpv-combined.a" -headers "$OUT/sim-headers/include")
elif [ ${#sim_libs[@]} -eq 1 ]; then
	cp "${sim_libs[0]}" "$OUT/ios-simulator-fat/libmpv-combined.a"
	mkdir -p "$OUT/sim-headers/include"
	cp -R "$BUILD/prefix/ios-arm64-simulator/include/"* "$OUT/sim-headers/include/" 2>/dev/null || \
		cp -R "$BUILD/prefix/ios-x86_64-simulator/include/"* "$OUT/sim-headers/include/"
	xcframework_args+=(-library "$OUT/ios-simulator-fat/libmpv-combined.a" -headers "$OUT/sim-headers/include")
fi

if [ ${#xcframework_args[@]} -eq 0 ]; then
	echo >&2 "Error: nothing to package."
	exit 1
fi

rm -rf Libmpv.xcframework
xcodebuild -create-xcframework "${xcframework_args[@]}" -output Libmpv.xcframework

echo ""
echo "Done. Libmpv.xcframework created at: $PWD/Libmpv.xcframework"
echo "Copy or symlink this into MPVKit/Frameworks/ before building the Swift package."
