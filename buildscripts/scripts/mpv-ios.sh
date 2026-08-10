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
#
# "avdevice" is required even though this build has no actual device
# input/output drivers enabled (see ffmpeg.sh's --disable-indevs
# --disable-outdevs) - mpv's own common_av_log.c calls
# avdevice_register_all()/avdevice_version() unconditionally, so the
# (mostly-empty) libavdevice.a still needs to be present, or the final
# app-level link fails with undefined symbols for those two names.
#
# "lua" (not "lua54"): Lua 5.2.4's own Makefile install target always
# produces liblua.a regardless of the Lua version being built - it is
# never suffixed with the version number the way some other libraries in
# this list are. The candidate-name loop below tries "lib$name.a" first,
# so listing the entry as "lua54" meant neither "liblua54.a" nor
# "liblua5454.a" (the second candidate, from the loop's own "${name}54"
# fallback) ever matched the real "liblua.a" - Lua's static lib was
# silently skipped from every combine, which is why every mpv Lua-related
# symbol (_luaL_*, _lua_*) came back undefined at final app link despite
# lua.sh itself building and installing successfully.
LIBNAMES=(
	mpv avformat avcodec avutil avfilter avdevice swscale swresample
	ass freetype fribidi harfbuzz unibreak lua dav1d
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
	local missing=()
	for name in "${LIBNAMES[@]}"; do
		local found=""
		for candidate in "$prefix/lib/lib$name.a" "$prefix/lib/lib${name}54.a"; do
			if [ -f "$candidate" ]; then
				libs+=("$candidate")
				found="1"
				break
			fi
		done
		[ -z "$found" ] && missing+=("$name")
	done

	# A silent skip here is exactly how the Lua-naming bug shipped
	# undetected before: liblua54.a never existed (Lua 5.2.4 always
	# installs as liblua.a), so it was quietly dropped from every combine
	# and only surfaced much later as a wall of undefined _lua*/_luaL_*
	# symbols at final app-level link - a stage far removed from this
	# script, with no obvious connection back to "a static lib silently
	# went missing from LIBNAMES's candidate matching." Failing loudly
	# here, at combine time, catches any future name mismatch (or an
	# upstream lib rename) immediately instead of producing a confusing
	# link error in an entirely different build step.
	if [ ${#missing[@]} -gt 0 ]; then
		echo >&2 "Error: expected static libs not found for $platform: ${missing[*]}"
		echo >&2 "Checked for lib<name>.a and lib<name>54.a under $prefix/lib/"
		echo >&2 "Either the corresponding buildscripts/scripts/<name>.sh didn't run/install for this platform, or LIBNAMES in this script no longer matches that library's actual installed filename."
		return 1
	fi

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
