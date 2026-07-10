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

unset CC CXX # meson wants these unset; the cross file supplies them

# NOTE: -Db_lto=true was removed here after a real CI failure that took
# three rounds of investigation to fully diagnose (see docs/RESEARCH.md).
# Clang's LTO mechanism embeds LLVM bitcode/IR directly in object files as
# part of how it works - not just when the separate, already-removed
# -fembed-bitcode flag is passed (see ffmpeg.sh's own history) - and
# meson's b_lto has a documented, longstanding incompatibility with static
# libraries (mesonbuild/meson#1646), which is exactly the --default-library
# configuration this whole project's crossfile forces everywhere. The
# practical symptom: `xcodebuild -create-xcframework`'s strict archive
# validation fails with "unable to find any architecture information...
# Unknown header: 0xb17c0de" when merging a static lib built this way,
# even though `libtool -static` itself merges the tainted objects without
# any complaint at all - the corruption is only caught much later, by a
# different, stricter tool.
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	-Denable_tests=false -Dstack_alignment=16

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install
