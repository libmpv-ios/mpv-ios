#!/bin/bash -e
#
# Checks ONE version-pinned dependency (named by $1) against its latest
# upstream GitHub release/tag, and rewrites its version variable in
# depinfo.sh if a newer one is found. Designed to be called once per
# dependency by dependency-check.yml, which opens a separate PR per bump —
# deliberately not a "bump everything at once" script, since a single
# combined PR makes it much harder to bisect which bump actually caused a
# build failure (see the libxml2 2.15.3 -Dftp=disabled break for a real
# example of exactly this kind of breakage).
#
# Usage: ./check-and-update-version.sh <dep-name>
#   e.g. ./check-and-update-version.sh libxml2
#
# On update, prints two lines to stdout for the calling workflow to parse:
#   OLD_VERSION=<old>
#   NEW_VERSION=<new>
# and exits 0. If already current, prints nothing and exits 1 (so the
# calling workflow can skip opening a PR for that dependency).
#
# Deliberately NOT covered by this script: mpv, ffmpeg, dav1d, libass,
# libplacebo. Those are already cloned from their default git branch with
# no pinned tag/commit (see download.sh) — every build already pulls
# their current upstream HEAD, so there's no fixed version here to check
# or bump.

cd "$( dirname "${BASH_SOURCE[0]}" )/.."
. ./include/depinfo.sh

dep="$1"
if [ -z "$dep" ]; then
	echo "Usage: $0 <dep-name>" >&2
	exit 2
fi

# name -> variable name in depinfo.sh | GitHub repo | tag prefix to strip
case "$dep" in
	lua)       varname=v_lua;       repo="lua/lua";              prefix="" ;;
	unibreak)  varname=v_unibreak;  repo="adah1972/libunibreak";  prefix="libunibreak_" ;;
	harfbuzz)  varname=v_harfbuzz;  repo="harfbuzz/harfbuzz";     prefix="" ;;
	fribidi)   varname=v_fribidi;   repo="fribidi/fribidi";       prefix="v" ;;
	freetype)  varname=v_freetype;  repo="freetype/freetype2";    prefix="VER-" ;;
	mbedtls)   varname=v_mbedtls;   repo="Mbed-TLS/mbedtls";      prefix="mbedtls-" ;;
	libxml2)   varname=v_libxml2;   repo="GNOME/libxml2";         prefix="v" ;;
	*)
		echo "Unknown dependency: $dep" >&2
		echo "Known: lua unibreak harfbuzz fribidi freetype mbedtls libxml2" >&2
		exit 2
		;;
esac

current="${!varname}"

# Authenticate if GH_TOKEN is available — GitHub's unauthenticated rate
# limit (60 req/hour) is per-IP and GitHub-hosted runners share IPs across
# many concurrent jobs from unrelated repos, so it's easy to hit by
# accident even from a single workflow run.
auth_header=()
[ -n "$GH_TOKEN" ] && auth_header=(-H "Authorization: Bearer $GH_TOKEN")

tags_json=$(curl -fsSL "${auth_header[@]}" -H "Accept: application/vnd.github+json" \
	"https://api.github.com/repos/$repo/tags?per_page=30") || {
	echo "Could not fetch tags for $repo" >&2
	exit 1
}

# Tags aren't guaranteed to arrive in strict semver order from this
# endpoint, so collect everything matching the expected prefix + clean
# version shape, then pick the actual highest by version sort. This also
# filters out unrelated tags (e.g. a "docs-v1" or release-candidate suffix)
# that we don't want to auto-adopt.
latest=$(echo "$tags_json" \
	| grep -o '"name": *"[^"]*"' \
	| sed -E 's/"name": *"//; s/"$//' \
	| grep -E "^${prefix}[0-9]+(\.[0-9]+)*$" \
	| sed -E "s/^${prefix}//" \
	| sort -t. -k1,1n -k2,2n -k3,3n \
	| tail -1)

if [ -z "$latest" ]; then
	echo "No clean version tags found for $repo (prefix '$prefix')" >&2
	exit 1
fi

if [ "$latest" == "$current" ]; then
	echo "$dep is already at the latest version ($current)" >&2
	exit 1
fi

# Update depinfo.sh in place. Uses a distinct sed pattern anchored to the
# exact variable assignment (v_foo=X) rather than a loose text match, so
# this can't accidentally touch an unrelated line that happens to contain
# the same version string.
sed -i.bak -E "s/^${varname}=.*/${varname}=${latest}/" include/depinfo.sh
rm -f include/depinfo.sh.bak

echo "OLD_VERSION=$current"
echo "NEW_VERSION=$latest"
