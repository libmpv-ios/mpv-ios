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

# Meson, not autotools: libass's autotools Makefile.am never lists
# libass/aarch64/*.S (the NEON asm sources) in any _SOURCES variable — only
# libass/meson.build does. Building with autotools still defines CONFIG_ASM=1
# and ARCH_AARCH64=1 (configure.ac does wire those up for aarch64), so
# ass_bitmap_engine_init compiles a call path into the NEON functions, but
# the .a ends up with no object code providing them at all, e.g.:
#   Undefined symbols for architecture arm64: "_ass_add_bitmaps_neon" ...
# on device (arm64) builds specifically — the scalar "_c" fallback path
# taken by the simulator's x86_64 slice never references the missing
# symbols, which is why this didn't surface there.
#
# coretext is auto-detected by meson on Darwin (feature: auto), same as
# autotools; fontconfig is explicitly disabled since it isn't available on
# iOS and libass falls back to CoreText for system font matching.
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	-Dfontconfig=disabled -Dlibunibreak=enabled \
	-D{test,compare,profile,fuzz,checkasm}=disabled

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install
