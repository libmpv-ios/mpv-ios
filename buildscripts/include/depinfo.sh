#!/bin/bash -e

## Dependency versions
## Kept in sync with mpv-android's buildscripts/include/depinfo.sh where applicable.
## iOS does not need an NDK/SDK downloader (Xcode provides the toolchain), so
## those variables from the Android version are dropped here.

v_lua=5.2.4
v_unibreak=7.0
v_harfbuzz=14.2.1
v_fribidi=1.0.16
v_freetype=2.14.3
v_mbedtls=3.6.5
v_libxml2=2.15.3
v_fontconfig=2.18.1

# iOS minimum deployment target
v_ios_min=13.0

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
