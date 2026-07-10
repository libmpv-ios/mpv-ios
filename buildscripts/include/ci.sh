#!/bin/bash -e

# go to buildscripts root folder
cd "$( dirname "${BASH_SOURCE[0]}" )/.."

. ./include/depinfo.sh

msg() {
	printf '==> %s\n' "$1"
}

# Cache identifier: changes whenever any dependency version bumps, so a
# stale cache from before a version bump is never reused. $1 is the
# platform slice (ios-arm64 / ios-arm64-simulator / ios-x86_64-simulator),
# since each slice's prefix/ contents are architecture-specific and must be
# cached separately.
#
# BUILD_LOGIC_REV below exists because the cached prefix/<platform>/
# directory contains more than just "whatever version of each dependency
# was requested" — it's the actual compiled OUTPUT of running this
# project's own build scripts (buildall.sh's generated crossfile.txt,
# plus every scripts/*.sh's compiled result) against those versions. A
# change to any of those scripts' build LOGIC — not just a v_whatever
# version bump — can silently be masked by a stale cache that still
# holds output from the old, buggy script. Two real examples that
# required bumping this:
#   - buildall.sh's setup_prefix() gained objc/objcpp crossfile entries
#     (mpv's meson.build needs them to compile hwdec_ios_gl.m).
#   - ffmpeg.sh's -fembed-bitcode flag was removed (Xcode 14+ deprecated
#     bitcode entirely; Xcode 16 produces a corrupted, unreadable-by-
#     libtool .a file if this flag is still passed — see docs/RESEARCH.md
#     for the full incident).
# Bump this integer any time a change to buildall.sh or any scripts/*.sh
# file could alter its compiled output, even if no dependency version
# changed — "did I just change what this script produces" is the
# question to ask, not "did I just change a version number."
BUILD_LOGIC_REV=6

cache_id() {
	local platform=$1
	echo "ios-deps-${platform}-buildrev${BUILD_LOGIC_REV}-lua${v_lua}-unibreak${v_unibreak}-harfbuzz${v_harfbuzz}-fribidi${v_fribidi}-freetype${v_freetype}-mbedtls${v_mbedtls}-libxml2${v_libxml2}"
}

fetch_prefix() {
	local platform=$1
	local id
	id=$(cache_id "$platform")

	if [[ "$CACHE_MODE" == folder ]]; then
		local text=
		if [ -f "$CACHE_FOLDER/id-$platform.txt" ]; then
			text=$(cat "$CACHE_FOLDER/id-$platform.txt")
		else
			echo "Cache seems to be empty for $platform"
		fi
		printf 'Expecting "%s",\nfound     "%s".\n' "$id" "$text"
		if [[ "$text" == "$id" ]]; then
			mkdir -p "prefix/$platform"
			tar -xzf "$CACHE_FOLDER/data-$platform.tgz" -C "prefix/$platform" && return 0
		fi
	fi
	return 1
}

build_prefix() {
	local platform=$1
	local id
	id=$(cache_id "$platform")

	msg "Building the $platform prefix ($id)..."
	./buildall.sh --platform "$platform" --only-deps mpv-ios

	if [[ "$CACHE_MODE" == folder && -w "$CACHE_FOLDER" ]]; then
		msg "Compressing the $platform prefix"
		tar -czf "$CACHE_FOLDER/data-$platform.tgz" -C "prefix/$platform" .
		echo "$id" >"$CACHE_FOLDER/id-$platform.txt"
	fi
}

if [ "$1" = "export" ]; then
	# export a cache key covering all three platform slices at once, for a
	# single actions/cache step keyed on the whole deps/ + prefix/ tree
	echo "CACHE_IDENTIFIER=$(cache_id ios-arm64)-$(cache_id ios-arm64-simulator)-$(cache_id ios-x86_64-simulator)"
	exit 0

elif [ "$1" = "install" ]; then
	# Download all dependency sources once (shared across platform slices;
	# only the compiled prefix/ output differs per-slice).
	msg "Downloading dependency sources"
	./download.sh

	for platform in ios-arm64 ios-arm64-simulator ios-x86_64-simulator; do
		msg "Trying to fetch existing prefix for $platform"
		fetch_prefix "$platform" || build_prefix "$platform"
	done
	exit 0

elif [ "$1" = "build" ]; then
	for platform in ios-arm64 ios-arm64-simulator ios-x86_64-simulator; do
		msg "Building mpv for $platform"
		# IMPORTANT: the target argument here MUST be "mpv", not "mpv-ios".
		# buildall.sh treats a target literally named "mpv-ios" as a special
		# case (see its build() function) that directly invokes
		# scripts/mpv-ios.sh - the full, all-three-platforms XCFramework
		# assembly script - instead of building the "mpv" dependency for
		# just the one platform this loop iteration is working on. Passing
		# "mpv-ios" here (an earlier version of this script's actual bug)
		# meant every iteration of this loop prematurely re-ran the entire
		# XCFramework assembly, including on the very first (ios-arm64)
		# iteration before ios-arm64-simulator or ios-x86_64-simulator had
		# even been built yet. See docs/RESEARCH.md for the full incident -
		# this produced a corrupted, unreadable build-xcframework/*/libmpv-combined.a
		# (libtool merging whatever partial/stale set of per-platform .a
		# files happened to exist in prefix/ at that premature moment) that
		# looked at first like a leftover -fembed-bitcode issue, but wasn't.
		./buildall.sh --platform "$platform" -n mpv || {
			build_dir="deps/mpv/_build_${platform}"
			echo "::group::meson-log.txt (configure-phase only)"
			echo "NOTE: this log covers 'meson setup' only. If it ends with a"
			echo "successful-looking feature summary (Build targets in project: N,"
			echo "Found ninja...), the actual failure was in the COMPILE step"
			echo "(ninja), not here - scroll up in this job's own console output"
			echo "for the real compiler/linker error, since ninja's output goes"
			echo "directly to this same CI step rather than to a separate log file."
			echo "A successful-looking meson-log.txt dump here is not evidence"
			echo "the build actually succeeded - see docs/RESEARCH.md entries 8"
			echo "and this incident's own entry for a real example of this."
			[ -f "$build_dir/meson-logs/meson-log.txt" ] && cat "$build_dir/meson-logs/meson-log.txt"
			echo "::endgroup::"
			exit 1
		}
	done

	msg "Assembling XCFramework"
	(cd .. && ./buildscripts/scripts/mpv-ios.sh build)
	exit 0

else
	exit 1
fi
