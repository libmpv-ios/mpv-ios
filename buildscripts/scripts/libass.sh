#!/bin/bash -e

. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf _build$ndk_suffix
	exit 0
else
	exit 255
fi

[ -f configure ] || ./autogen.sh

mkdir -p _build$ndk_suffix
cd _build$ndk_suffix

# no fontconfig on iOS: libass falls back to its CoreText backend
# (autodetected by configure on Darwin targets) for system font matching
../configure \
	--host=$host_triple --with-pic \
	--enable-static --disable-shared \
	--enable-libunibreak --disable-fontconfig \
	CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
	CFLAGS="-I$prefix_dir/include" LDFLAGS="$LDFLAGS -L$prefix_dir/lib" \
	PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"

make -j$cores
make DESTDIR="$prefix_dir" install
