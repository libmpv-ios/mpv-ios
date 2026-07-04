#!/bin/bash -e

. ./include/depinfo.sh

[ -z "$WGET" ] && WGET=curl -L -o

fetch_targz () {
	# fetch_targz <url> <destdir>
	mkdir -p "$2"
	curl -fL "$1" -o /tmp/mpvios-dl.tar.gz
	tar -xzf /tmp/mpvios-dl.tar.gz -C "$2" --strip-components=1
	rm -f /tmp/mpvios-dl.tar.gz
}

fetch_tarxz () {
	mkdir -p "$2"
	curl -fL "$1" -o /tmp/mpvios-dl.tar.xz
	tar -xJf /tmp/mpvios-dl.tar.xz -C "$2" --strip-components=1
	rm -f /tmp/mpvios-dl.tar.xz
}

fetch_tarbz2 () {
	mkdir -p "$2"
	curl -fL "$1" -o /tmp/mpvios-dl.tar.bz2
	tar -xjf /tmp/mpvios-dl.tar.bz2 -C "$2" --strip-components=1
	rm -f /tmp/mpvios-dl.tar.bz2
}

mkdir -p deps && cd deps

# mbedtls
[ ! -d mbedtls ] && fetch_tarbz2 \
	"https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$v_mbedtls/mbedtls-$v_mbedtls.tar.bz2" mbedtls

# dav1d
[ ! -d dav1d ] && git clone https://github.com/videolan/dav1d

# ffmpeg
[ ! -d ffmpeg ] && git clone https://github.com/FFmpeg/FFmpeg ffmpeg

# freetype2
[ ! -d freetype2 ] && git clone --recurse-submodules \
	https://gitlab.freedesktop.org/freetype/freetype.git freetype2 -b VER-${v_freetype//./-}

# fribidi
[ ! -d fribidi ] && fetch_tarxz \
	"https://github.com/fribidi/fribidi/releases/download/v$v_fribidi/fribidi-$v_fribidi.tar.xz" fribidi

# harfbuzz
[ ! -d harfbuzz ] && fetch_tarxz \
	"https://github.com/harfbuzz/harfbuzz/releases/download/$v_harfbuzz/harfbuzz-$v_harfbuzz.tar.xz" harfbuzz

# unibreak
[ ! -d unibreak ] && fetch_targz \
	"https://github.com/adah1972/libunibreak/releases/download/libunibreak_${v_unibreak//./_}/libunibreak-${v_unibreak}.tar.gz" unibreak

# libxml2
[ ! -d libxml2 ] && fetch_targz \
	"https://gitlab.gnome.org/GNOME/libxml2/-/archive/v${v_libxml2}/libxml2-v${v_libxml2}.tar.gz" libxml2

# libass
[ ! -d libass ] && git clone https://github.com/libass/libass

# lua
[ ! -d lua ] && fetch_targz "https://www.lua.org/ftp/lua-$v_lua.tar.gz" lua

# libplacebo
[ ! -d libplacebo ] && git clone --recursive https://github.com/haasn/libplacebo

# mpv
[ ! -d mpv ] && git clone https://github.com/mpv-player/mpv

cd ..
echo "All sources downloaded into buildscripts/deps/"
