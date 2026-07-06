#!/bin/bash -e

. ./include/depinfo.sh

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

# When IN_CI=1 (set by build.yml/release.yml/appetize-preview.yml), the five
# git-cloned dependencies below (dav1d, ffmpeg, libass, libplacebo, mpv) are
# pinned to the tag/commit in v_ci_* (see depinfo.sh) instead of cloning
# whatever the default branch's HEAD happens to be at that moment.
#
# This mirrors mpv-android's own download-deps.sh pattern exactly
# (`[ $IN_CI -eq 1 ] && args+=(--depth=1 -b "$v_ci_ffmpeg")`) — local/manual
# builds still get the convenience of always-latest-HEAD for quick
# iteration, but CI gets a reproducible, intentionally-chosen version so a
# totally unrelated upstream commit landing between two of our own pushes
# can't silently break the build. See depinfo.sh's comments for how to
# update these pins.
IN_CI=${IN_CI:-0}

git_clone_pinned () {
        # git_clone_pinned <url> <destdir> <ref>
        if [ "$IN_CI" -eq 1 ]; then
                git clone --depth=1 -b "$3" "$1" "$2"
        else
                git clone "$1" "$2"
        fi
}

# mbedtls
[ ! -d mbedtls ] && fetch_tarbz2 \
        "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$v_mbedtls/mbedtls-$v_mbedtls.tar.bz2" mbedtls

# dav1d
[ ! -d dav1d ] && git_clone_pinned https://github.com/videolan/dav1d dav1d "$v_ci_dav1d"

# ffmpeg
[ ! -d ffmpeg ] && git_clone_pinned https://github.com/FFmpeg/FFmpeg ffmpeg "$v_ci_ffmpeg"

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
[ ! -d libass ] && git_clone_pinned https://github.com/libass/libass libass "$v_ci_libass"

# lua
[ ! -d lua ] && fetch_targz "https://www.lua.org/ftp/lua-$v_lua.tar.gz" lua

# libplacebo
if [ ! -d libplacebo ]; then
        git_clone_pinned https://github.com/haasn/libplacebo libplacebo "$v_ci_libplacebo"
        git -C libplacebo submodule update --init --recursive
fi

# mpv
[ ! -d mpv ] && git_clone_pinned https://github.com/mpv-player/mpv mpv "$v_ci_mpv"

cd ..

# Ensure the patch script has execution privileges before calling it, 
# preventing 'Permission denied' faults in isolated environments.
chmod +x ./include/apply-mpv-patches.sh

# Apply iOS-compatibility patches to mpv (see patches/mpv/README.md and
# include/apply-mpv-patches.sh for what these do and why). Runs every time
# download.sh runs, whether mpv was just freshly cloned above or already
# existed from a previous run — the script itself detects and skips
# already-applied patches safely.
./include/apply-mpv-patches.sh

echo "All sources downloaded into buildscripts/deps/"
