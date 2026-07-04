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

# Vulkan is not available on iOS; mpv will use libplacebo purely as a
# shader/rendering helper library through its own Metal-backed GPU context
# rather than through libplacebo's Vulkan backend.
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	-Dvulkan=disabled -Dd3d11=disabled -Dopengl=disabled -Ddemos=false \
	-Dglslang=disabled -Dshaderc=disabled

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install

# add missing library for static linking (same meson bug noted upstream:
# https://github.com/mesonbuild/meson/issues/11300)
${SED:-sed} '/^Libs:/ s|$| -lc++|' "$prefix_dir/lib/pkgconfig/libplacebo.pc" -i
