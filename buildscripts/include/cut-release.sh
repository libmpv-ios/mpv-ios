#!/bin/bash -e
#
# Turns CHANGELOG.md's [Unreleased] section into this release's notes, and
# rewrites CHANGELOG.md so [Unreleased] is emptied out and that content now
# lives under a dated version heading instead. This is the one place
# "how do we turn what's in CHANGELOG.md into a GitHub release body"
# lives — release.yml calls this instead of hand-writing notes inline or
# relying on GitHub's generic auto-generated notes.
#
# Usage:
#   ./cut-release.sh notes <tag>      # print release-note body to stdout
#   ./cut-release.sh bump <tag>       # rewrite CHANGELOG.md in place
#
# "notes" is read-only (safe to call in CI before deciding anything).
# "bump" actually edits CHANGELOG.md and is meant to be committed back
# (see release.yml's "Update CHANGELOG.md" step) — kept separate from
# "notes" so CI can generate+publish the release body without needing to
# have already committed the bump, and so a maintainer can preview "notes"
# locally without touching the file.
#
# Exits non-zero if [Unreleased] has no entries under it — an empty
# release is almost always a mistake (forgot to update CHANGELOG.md in
# the PR that should have touched it), not something to silently publish.

cd "$( dirname "${BASH_SOURCE[0]}" )/../.."
. ./buildscripts/include/depinfo.sh

changelog="CHANGELOG.md"
mode="$1"
tag="$2"

if [ -z "$mode" ] || [ -z "$tag" ]; then
	echo "Usage: $0 <notes|bump> <tag>" >&2
	exit 2
fi

if [ ! -f "$changelog" ]; then
	echo "$changelog not found" >&2
	exit 1
fi

# Extract everything between "## [Unreleased]" and the next "## [" heading,
# HTML comment block (the "<!-- ## [X.Y.Z] -->" template at the end of the
# file), or end of file — whichever comes first. Deliberately tolerant of
# which sub-sections (Added/Changed/Fixed/...) are present, and of empty
# ones: this is a slice by heading, not a full parse of the Keep a
# Changelog sub-structure, so CHANGELOG.md's authors stay free to omit or
# leave blank sections without this script needing to know the full list
# of valid ones. Empty "### Heading" lines with no bullets under them are
# dropped so the emptiness check below and the published notes aren't
# cluttered with headings that have nothing under them.
unreleased_raw=$(awk '
	/^## \[Unreleased\]/ { capture=1; next }
	/^## \[/ { if (capture) exit }
	/^<!--/ { if (capture) exit }
	capture { print }
' "$changelog")

unreleased_body=$(echo "$unreleased_raw" | awk '
	/^### / {
		if (pending != "") print pending
		pending=$0
		next
	}
	/^[[:space:]]*$/ { print; next }
	{
		if (pending != "") { print pending; pending="" }
		print
	}
')

# Strip leading/trailing blank lines so emptiness-checking and formatting
# below aren't thrown off by incidental whitespace in the source file.
unreleased_trimmed=$(echo "$unreleased_body" | sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')

if [ -z "$(echo "$unreleased_trimmed" | tr -d '[:space:]')" ]; then
	echo "CHANGELOG.md's [Unreleased] section is empty — nothing to release." >&2
	echo "Add entries there before tagging, or this release has no changelog." >&2
	exit 1
fi

release_date=$(date +%Y-%m-%d)

case "$mode" in
	notes)
		echo "$unreleased_trimmed"
		echo ""
		echo "---"
		echo ""
		echo "**Dependency versions pinned at this release:**"
		echo ""
		echo "| Dependency | Version |"
		echo "|---|---|"
		echo "| lua | \`${v_lua}\` |"
		echo "| unibreak | \`${v_unibreak}\` |"
		echo "| harfbuzz | \`${v_harfbuzz}\` |"
		echo "| fribidi | \`${v_fribidi}\` |"
		echo "| freetype | \`${v_freetype}\` |"
		echo "| mbedtls | \`${v_mbedtls}\` |"
		echo "| libxml2 | \`${v_libxml2}\` |"
		echo "| iOS minimum target | \`${v_ios_min}\` |"
		echo "| mpv (git ref) | \`${v_ci_mpv}\` |"
		echo "| ffmpeg (git ref) | \`${v_ci_ffmpeg}\` |"
		echo "| dav1d (git ref) | \`${v_ci_dav1d}\` |"
		echo "| libass (git ref) | \`${v_ci_libass}\` |"
		echo "| libplacebo (git ref) | \`${v_ci_libplacebo}\` |"
		echo ""
		echo "See [docs/RESEARCH.md](docs/RESEARCH.md) for the full build/porting"
		echo "log, and [README.md](README.md) for integration steps."
		;;
	bump)
		# Replace the "## [Unreleased]" heading line with a *fresh, empty*
		# Unreleased heading followed immediately by "## [tag] - date" — the
		# body text that used to belong to [Unreleased] is untouched and
		# left exactly where it is in the file, so it now reads as the
		# content of the new version heading instead. Only the heading line
		# itself is replaced; every line after it (the actual entries) is
		# passed through unmodified via awk's default print.
		tmp=$(mktemp)
		awk -v tag="$tag" -v date="$release_date" '
			/^## \[Unreleased\]/ && !done {
				print "## [Unreleased]"
				print ""
				print "## [" tag "] - " date
				done=1
				next
			}
			{ print }
		' "$changelog" > "$tmp"
		mv "$tmp" "$changelog"
		echo "CHANGELOG.md updated: [Unreleased] emptied, content moved under [$tag] - $release_date" >&2
		;;
	*)
		echo "Unknown mode: $mode (expected 'notes' or 'bump')" >&2
		exit 2
		;;
esac
