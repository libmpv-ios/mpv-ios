#!/bin/bash -e

. ../../include/path.sh

build=_build$ndk_suffix

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf $build
	exit 0
else
	exit 255
fi

unset CC CXX

# NOTE: -Dftp=disabled was removed here after a CI failure — libxml2 2.14.0
# removed the FTP module and its corresponding meson option entirely (see
# libxml2's NEWS file: "The FTP module and related functions were
# removed."). Passing -Dftp=disabled against libxml2 2.15.3 (our pinned
# version, see depinfo.sh) fails meson setup with "Unknown option: ftp"
# since the option no longer exists to be set at all — there's nothing to
# disable, FTP support is simply gone from the codebase. -Dhttp=disabled is
# also technically redundant against 2.13+ (HTTP support defaults to off
# already), but is kept explicit here since passing it is still valid and
# documents the intent even though it's a no-op.
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	-Dminimum=true -D{push,reader,sax1,iso8859x,pattern}=enabled \
	-Dhttp=disabled -Dlzma=disabled -Dzlib=disabled

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install
