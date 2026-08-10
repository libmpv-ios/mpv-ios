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

	--extra-cflags="-I$prefix_dir/include"
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
	--disable-{muxers,encoders}
	# NOT --disable-devices: mpv's own common_av_log.c calls
	# avdevice_register_all() and avdevice_version() unconditionally at
	# startup (for its own version-check/registration bookkeeping), not
	# gated behind any of mpv's device-input meson options - so even a
	# build with zero actual device backends needed still needs
	# libavdevice.a to exist and export those two symbols, or the final
	# app-level link fails with "Undefined symbols: _avdevice_register_all,
	# _avdevice_version" (found in CI; libmpv-combined.a on its own doesn't
	# surface this until something actually calls avdevice_register_all).
	# --disable-indevs and --disable-outdevs below still build the
	# avdevice library itself (registration table + these two entry
	# points) while disabling every actual OS-specific device driver
	# ffmpeg knows about (none of which exist on iOS anyway - no v4l2, no
	# dshow, no avfoundation *input* device driver is enabled here since
	# this project only uses avfoundation for mpv's own audio output, a
	# separate thing from ffmpeg's avdevice input drivers).
	--disable-indevs --disable-outdevs
	--enable-encoder=mjpeg,png
	--enable-muxer=mov,matroska,mpegts

	--disable-securetransport
	--disable-audiotoolbox
)
../configure "${args[@]}"

make -j$cores
make DESTDIR="$prefix_dir" install
