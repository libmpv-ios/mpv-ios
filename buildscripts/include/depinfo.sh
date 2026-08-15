#!/bin/bash -e

## Dependency versions
## Kept in sync with mpv-android's buildscripts/include/depinfo.sh where applicable.
## iOS does not need an NDK/SDK downloader (Xcode provides the toolchain), so
## those variables from the Android version are dropped here.

v_lua=5.2.4
v_unibreak=7.0
v_harfbuzz=14.3.1
v_fribidi=1.0.16
v_freetype=2.14.3
v_mbedtls=3.6.5
v_libxml2=2.15.3

# iOS minimum deployment target
v_ios_min=13.0

## CI-pinned versions for git-cloned dependencies (mpv, ffmpeg, dav1d,
## libass, libplacebo).
##
## These five are cloned from their default branch with no pin during
## local/manual builds (see download.sh) — convenient while iterating, and
## matches mpv-android's own local-dev behavior. But an *unconditional*
## always-latest-HEAD clone in CI means a totally unrelated upstream commit
## can break our build on a push that touched none of our own code — CI
## should be reproducible, not a lottery on whatever landed upstream five
## minutes earlier.
##
## mpv-android solves this the same way: buildscripts/include/depinfo.sh
## pins v_ci_ffmpeg, and download-deps.sh does
## `[ $IN_CI -eq 1 ] && args+=(--depth=1 -b "$v_ci_ffmpeg")` — only pinning
## in the CI path, not for local dev. We follow the identical pattern here
## for all five git-based deps, not just ffmpeg, since mpv/dav1d/libass/
## libplacebo are exactly as capable of an upstream breaking change as
## ffmpeg is.
##
## HOW TO UPDATE THESE: check the latest tag (preferred, since tags are
## intentional release points) or a recent known-good commit for each repo,
## then bump the value below. mpv-android's own release notes
## (https://github.com/mpv-android/mpv-android/releases) publish the exact
## commit they pin for each of these on every release — a reasonable
## reference point if you want a version known to work together, since
## these libraries do have version compatibility constraints on each other
## (e.g. mpv's own release notes state minimum required ffmpeg/libplacebo
## versions).
v_ci_mpv=master
v_ci_ffmpeg=master
v_ci_dav1d=master
v_ci_libass=master
v_ci_libplacebo=master

## Dependency tree (identical topology to mpv-android; fontconfig is dropped
## because iOS provides system fonts + CoreText, and libass on Apple platforms
## is conventionally built with --disable-fontconfig, using CoreText instead
## via libass's own coretext backend detection at configure time)

dep_mbedtls=()
dep_dav1d=()
dep_libxml2=()
dep_ffmpeg=(mbedtls dav1d libxml2)
dep_freetype2=()
dep_fribidi=()
dep_harfbuzz=()
dep_unibreak=()
dep_libass=(freetype2 fribidi harfbuzz unibreak)
dep_lua=()
dep_libplacebo=()
dep_mpv=(ffmpeg libass lua libplacebo)
dep_mpv_ios=(mpv)
