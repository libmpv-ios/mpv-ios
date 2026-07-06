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
# CROSSFILE_REV below exists because crossfile.txt itself lives inside the
# cached prefix/ directory (it's written by buildall.sh's setup_prefix()
# alongside the actual compiled dependency output). A change to how
# crossfile.txt is generated — e.g. adding the objc/objcpp binaries mpv's
# meson.build needs to compile hwdec_ios_gl.m — does NOT change any
# v_whatever dependency version, so without this marker such a change
# would silently be masked by a stale cache still holding the old
# crossfile.txt. Bump this integer any time buildall.sh's setup_prefix()
# changes, even if no dependency version changed.
CROSSFILE_REV=3

cache_id() {
	local platform=$1
	echo "ios-deps-${platform}-crossfile${CROSSFILE_REV}-lua${v_lua}-unibreak${v_unibreak}-harfbuzz${v_harfbuzz}-fribidi${v_fribidi}-freetype${v_freetype}-mbedtls${v_mbedtls}-libxml2${v_libxml2}"
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
		./buildall.sh --platform "$platform" -n mpv-ios || {
			log_file="deps/mpv/_build_${platform}/meson-logs/meson-log.txt"
			[ -f "$log_file" ] && cat "$log_file"
			exit 1
		}
	done

	msg "Assembling XCFramework"
	(cd .. && ./buildscripts/scripts/mpv-ios.sh build)
	exit 0

else
	exit 1
fi
