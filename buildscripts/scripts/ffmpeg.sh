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

mkdir -p _build$ndk_suffix
cd _build$ndk_suffix

# ffmpeg arch naming differs slightly from clang -arch naming
ffarch=$arch
[[ "$arch" == "arm64" ]] && ffarch=arm64

args=(
	--target-os=darwin --enable-cross-compile
	--arch=$ffarch --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB"
	--pkg-config=pkg-config --nm="$(xcrun --sdk $sdk --find nm)"

	--extra-cflags="-I$prefix_dir/include -fembed-bitcode"
	--extra-cxxflags="-I$prefix_dir/include"
	--extra-ldflags="-L$prefix_dir/lib $LDFLAGS"

	--sysroot="$sysroot"

	# hardware decode via Apple's VideoToolbox (this is the iOS equivalent of
	# mpv-android's --enable-jni --enable-mediacodec)
	--enable-videotoolbox
	--enable-{mbedtls,libdav1d,libxml2}
	--disable-vulkan

	# static linking is required for iOS App Store distribution of
	# non-system dylibs; mpv-android uses --enable-shared because .so is fine
	# on Android, but iOS needs a static libavcodec/etc merged into one
	# XCFramework (see mpv.sh which links everything into libmpv.a's deps)
	--enable-static --disable-shared

	--enable-{gpl,version3}
	--disable-{stripping,doc,programs}
	--disable-{muxers,encoders,devices}
	--enable-encoder=mjpeg,png
	--enable-muxer=mov,matroska,mpegts

	--disable-securetransport
	--disable-audiotoolbox
)
../configure "${args[@]}"

make -j$cores
make DESTDIR="$prefix_dir" install
