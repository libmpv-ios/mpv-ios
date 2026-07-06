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

# CORRECTED from an earlier draft of this script: libmpv has no Metal
# render-API backend (see include/mpv/render.h — only OpenGL and SW exist).
# mpv's own upstream iOS support (video/out/hwdec/hwdec_ios_gl.m, gated by
# meson's `ios-gl` feature) targets OpenGL ES via EAGL, with VideoToolbox
# hardware frames imported through CVOpenGLESTextureCache. That is the path
# this build enables:
#   -Dgl=enabled:      builds the OpenGL/GLES backend (required for libmpv's
#                       render API to expose MPV_RENDER_API_TYPE_OPENGL)
#   -Dios-gl=enabled:   builds the CVOpenGLESTextureCache-based VideoToolbox
#                       hwdec interop for GLES specifically
#   -Dvideotoolbox-gl=disabled: FOUND IN CI — meson.build's own
#                       `videotoolbox-gl = get_option('videotoolbox-gl').require(
#                       features['gl-cocoa'] or features['ios-gl'], ...)` means
#                       this feature defaults to auto and silently enables
#                       itself whenever ios-gl is true, since it treats
#                       gl-cocoa (macOS) and ios-gl (iOS) as two alternate
#                       ways to satisfy the same feature. hwdec_vt.h's
#                       `struct priv` then picks its layout with
#                       `#if HAVE_VIDEOTOOLBOX_GL / #elif HAVE_IOS_GL` — with
#                       both true, the first (macOS) branch wins, giving the
#                       struct a plain `GLuint gl_planes[]` with no
#                       `gl_texture_cache` member. hwdec_ios_gl.m
#                       unconditionally expects the iOS layout
#                       (CVOpenGLESTextureCacheRef gl_texture_cache +
#                       CVOpenGLESTextureRef gl_planes[]), so it fails with
#                       "no member named 'gl_texture_cache' in 'struct priv'"
#                       plus GLuint/CVOpenGLESTextureRef mismatch errors.
#                       Explicitly disabling videotoolbox-gl here (mirroring
#                       how vulkan/vdpau/vaapi/drm/x11/wayland/cocoa/
#                       coreaudio are all explicit below rather than left on
#                       auto) forces struct priv into the HAVE_IOS_GL branch
#                       hwdec_ios_gl.m actually matches. Not an mpv oversight
#                       like the patches/ series — meson.build's intent is
#                       correct on its own; this build just needs to pick
#                       one of the two alternatives explicitly.
#   -Dvulkan=disabled:  no MoltenVK path on iOS in this build (that path
#                       depends on AppKit/NSApplication and doesn't apply)
# --Dlibmpv=true: build the C API library our Swift wrapper links against.
# --Dcplayer=false: we don't need the mpv CLI player binary, only libmpv.
#
# UPDATED after adding buildscripts/patches/mpv/: -Dcoreaudio and
# -Davfoundation were previously both force-disabled here after a CI
# failure, because auto-detection had enabled both (Apple frameworks were
# present) and both are audio outputs whose shared utility code
# (audio/out/ao_coreaudio_utils.{c,h}, ao_coreaudio_chmap.{c,h}) referenced
# AudioDeviceID/AudioStreamID (real CoreAudio HAL types that don't exist on
# iOS) inside a shared `#if HAVE_COREAUDIO || HAVE_AVFOUNDATION` guard.
#
# We verified directly against mpv's own source that ao_avfoundation.m
# itself never calls any of the actual AudioDeviceID-taking functions in
# that shared code (only the genuinely device-independent ca_get_acl and
# its dependencies) — the shared guard was simply too broad, grouping
# device-independent and device-dependent code together. The patches in
# patches/mpv/ narrow those guards so the device-independent parts stay
# available to avfoundation while the true HAL-only parts become
# coreaudio-exclusive. A separate patch also guards avfoundation.m's one
# genuinely macOS-only call (device selection via
# setAudioOutputDeviceUniqueID:, which Apple's own headers mark
# unavailable on iOS) behind `#if !TARGET_OS_IPHONE`.
#
# With those patches applied (see download.sh, which calls
# include/apply-mpv-patches.sh automatically), avfoundation now builds
# correctly for iOS and is re-enabled below, giving mpv on iOS the more
# modern AVSampleBufferAudioRenderer-based output (including things like
# spatial audio support) in addition to audiounit.
#
# coreaudio itself (audio/out/ao_coreaudio.c, ao_coreaudio_exclusive.c)
# remains disabled — those files are genuinely macOS-only in their
# fundamental design (full HAL device enumeration/selection has no iOS
# equivalent at all, unlike avfoundation's narrower, already-mostly-iOS
# renderer API), so patching them wouldn't be "fixing an oversight" the
# way the avfoundation patches are — it would mean building an iOS
# feature that doesn't exist yet upstream, well beyond this project's
# current scope.
# Force clear any stale meson telemetry or cache inside the build dir
rm -rf "$build"

meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	--default-library=static \
	-Diconv=disabled -Dlua=enabled \
	-Dlibmpv=true -Dcplayer=false \
	-Dmanpage-build=disabled \
	-Dgl=enabled -Dios-gl=enabled -Dvideotoolbox-gl=disabled \
	-Dvulkan=disabled -Dvdpau=disabled -Dvaapi=disabled -Ddrm=disabled \
	-Dx11=disabled -Dwayland=disabled \
	-Dcocoa=disabled \
	-Dcoreaudio=disabled -Davfoundation=enabled -Daudiounit=enabled

ninja -C $build -j$cores

# mpv-android's own mpv.sh carries an equivalent check in the opposite
# direction (it requests --default-library shared and forces a clean
# rebuild if meson produced a static .a instead, due to a known meson
# caching quirk where a stale build dir can retain the previous
# --default-library choice after it's changed). We request static here, so
# the failure mode we guard against is the mirror image: a stale build dir
# still holding a shared .dylib from an earlier run/config.
if [ -f "$build/libmpv.dylib" ] || ls "$build"/libmpv.*.dylib >/dev/null 2>&1; then
	echo >&2 "meson produced a shared library despite --default-library=static (stale build dir?), forcing clean rebuild."
	$0 clean
	exec $0 build
fi

DESTDIR="$prefix_dir" ninja -C $build install
