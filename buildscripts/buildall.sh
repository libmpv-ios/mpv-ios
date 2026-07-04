#!/bin/bash -e
#
# mpv-ios build orchestrator.
# Mirrors mpv-android/buildscripts/buildall.sh in structure and behavior,
# but targets Apple platforms (iOS device, iOS simulator) via Xcode's clang
# instead of the Android NDK, and produces XCFrameworks instead of .so files.

cd "$( dirname "${BASH_SOURCE[0]}" )"
. ./include/depinfo.sh
. ./include/path.sh

cleanbuild=0
nodeps=0
onlydeps=0
target=mpv-ios
# platform values: ios-arm64 (device), ios-arm64-simulator, ios-x86_64-simulator
platform=ios-arm64

getdeps () {
	varname="dep_${1//-/_}[*]"
	echo ${!varname}
}

wasbuilt () {
	varname="built_${1//-/_}_${platform//-/_}"
	return "${!varname:-1}"
}

markbuilt () {
	varname="built_${1//-/_}_${platform//-/_}"
	declare -g "$varname=0"
}

# loadplatform: sets up SDK sysroot, target triple, and compiler flags for
# one of the three Apple platform/arch combinations we ship.
loadplatform () {
	unset CC CXX CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
	unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
	unset PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR

	case "$1" in
	ios-arm64)
		export sdk=iphoneos
		export arch=arm64
		export host_triple=aarch64-apple-ios
		export min_version_flag="-mios-version-min=${v_ios_min}"
		prefix_name=ios-arm64
		;;
	ios-arm64-simulator)
		export sdk=iphonesimulator
		export arch=arm64
		export host_triple=aarch64-apple-ios-simulator
		export min_version_flag="-mios-simulator-version-min=${v_ios_min}"
		prefix_name=ios-arm64-simulator
		;;
	ios-x86_64-simulator)
		export sdk=iphonesimulator
		export arch=x86_64
		export host_triple=x86_64-apple-ios-simulator
		export min_version_flag="-mios-simulator-version-min=${v_ios_min}"
		prefix_name=ios-x86_64-simulator
		;;
	*)
		echo "Invalid platform: $1" >&2
		echo "Supported: ios-arm64, ios-arm64-simulator, ios-x86_64-simulator" >&2
		exit 1
		;;
	esac

	export sysroot=$(xcrun --sdk $sdk --show-sdk-path)
	export ndk_triple=$host_triple   # kept for drop-in compat with scripts ported verbatim
	export ndk_suffix=_$prefix_name
	export prefix_dir="$PWD/prefix/$prefix_name"

	export CC="$(xcrun --sdk $sdk --find clang) -arch $arch -isysroot $sysroot $min_version_flag"
	export CXX="$(xcrun --sdk $sdk --find clang++) -arch $arch -isysroot $sysroot $min_version_flag"
	export AR=$(xcrun --sdk $sdk --find ar)
	export RANLIB=$(xcrun --sdk $sdk --find ranlib)
	export LD=$(xcrun --sdk $sdk --find ld)
	export STRIP=$(xcrun --sdk $sdk --find strip)
	export LDFLAGS="-arch $arch -isysroot $sysroot $min_version_flag"

	if ! command -v pkg-config >/dev/null; then
		echo "pkg-config is missing! Install with: brew install pkg-config" >&2
		return 1
	fi
	export PKG_CONFIG_SYSROOT_DIR="$prefix_dir"
	export PKG_CONFIG_LIBDIR="$PKG_CONFIG_SYSROOT_DIR/lib/pkgconfig"
	export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
}

setup_prefix () {
	if [ ! -d "$prefix_dir" ]; then
		mkdir -p "$prefix_dir"
		ln -s . "$prefix_dir/usr"
		ln -s . "$prefix_dir/local"
	fi

	# meson cross file, analogous to mpv-android's crossfile.txt generation
	local meson_cpu_family=aarch64
	[[ "$arch" == "x86_64" ]] && meson_cpu_family=x86_64

	cat >"$prefix_dir/crossfile.tmp" <<CROSSFILE
[built-in options]
buildtype = 'release'
default_library = 'static'
wrap_mode = 'nodownload'
prefix = '/usr/local'
c_args = ['-arch', '$arch', '-isysroot', '$sysroot', '$min_version_flag']
c_link_args = ['-arch', '$arch', '-isysroot', '$sysroot', '$min_version_flag']
cpp_args = ['-arch', '$arch', '-isysroot', '$sysroot', '$min_version_flag']
cpp_link_args = ['-arch', '$arch', '-isysroot', '$sysroot', '$min_version_flag']
[binaries]
c = '$(xcrun --sdk $sdk --find clang)'
cpp = '$(xcrun --sdk $sdk --find clang++)'
ar = '$AR'
strip = '$STRIP'
pkgconfig = 'pkg-config'
pkg-config = 'pkg-config'
[host_machine]
system = 'darwin'
cpu_family = '$meson_cpu_family'
cpu = '$arch'
endian = 'little'
CROSSFILE
	if cmp -s "$prefix_dir"/crossfile.{tmp,txt} 2>/dev/null; then
		rm "$prefix_dir/crossfile.tmp"
	else
		mv "$prefix_dir"/crossfile.{tmp,txt}
	fi
}

build () {
	if [[ $1 != "mpv-ios" && ! -d deps/$1 ]]; then
		printf >&2 '\e[1;31m%s\e[m\n' "Target $1 not found (did you run download.sh?)"
		return 1
	fi
	wasbuilt "$1" && return 0
	if [ $nodeps -eq 0 ]; then
		printf >&2 '\e[1;34m%s\e[m\n' "Preparing $1 for $platform..."
		local deps=$(getdeps $1)
		echo >&2 "Dependencies: $deps"
		for dep in $deps; do
			build $dep
		done
	fi
	printf >&2 '\e[1;34m%s\e[m\n' "Building $1 for $platform..."
	if [[ "$1" == "mpv-ios" ]]; then
		pushd .. >/dev/null
		BUILDSCRIPT=buildscripts/scripts/$1.sh
	else
		pushd deps/$1 >/dev/null
		BUILDSCRIPT=../../scripts/$1.sh
	fi
	[ $cleanbuild -eq 1 ] && $BUILDSCRIPT clean
	$BUILDSCRIPT build
	popd >/dev/null
	markbuilt "$1"
}

usage () {
	printf '%s\n' \
		"Usage: buildall.sh [options] [target]" \
		"Builds the specified target (default: $target) for one platform slice." \
		"Run once per platform, then use lipo-frameworks.sh to merge into XCFrameworks." \
		"" \
		"-n                Do not build dependencies" \
		"--only-deps       Build only dependencies of the specified target" \
		"--clean           Clean build dirs before compiling" \
		"--platform <p>    ios-arm64 (device) | ios-arm64-simulator | ios-x86_64-simulator" \
		"--all-platforms   Build all three platform slices in sequence"
	exit 0
}

allplatforms=0
while [ $# -gt 0 ]; do
	case "$1" in
		--clean)
		cleanbuild=1
		;;
		-n|--no-deps)
		nodeps=1
		;;
		--only-deps)
		onlydeps=1
		;;
		--platform)
		shift
		platform=$1
		;;
		--all-platforms)
		allplatforms=1
		;;
		-h|--help)
		usage
		;;
		-*)
		echo "Unknown flag $1" >&2
		exit 1
		;;
		*)
		target=$1
		;;
	esac
	shift
done

do_one_platform () {
	loadplatform "$platform"
	setup_prefix
	if [ $onlydeps -eq 1 ]; then
		deps=$(getdeps $target)
		for dep in $deps; do
			build $dep
		done
	else
		build $target
	fi
}

if [ $allplatforms -eq 1 ]; then
	for platform in ios-arm64 ios-arm64-simulator ios-x86_64-simulator; do
		do_one_platform
	done
else
	do_one_platform
fi

exit 0
