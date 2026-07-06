#!/bin/bash -e
#
# Applies iOS-compatibility patches to freshly-cloned mpv source. Called
# automatically by download.sh right after mpv is cloned, so every build
# gets these without a manual step.
#
# WHY THIS EXISTS: a small number of mpv source files call macOS-only APIs
# from code paths that are otherwise perfectly buildable and useful on
# iOS. Rather than disabling the whole feature (coreaudio/avfoundation
# audio output entirely, as an earlier version of this project's mpv.sh
# did), these patches narrow the actual problem down to the specific
# unavailable call/type, so the rest of the feature keeps working. See
# each patch file's own header comment for the specific upstream
# code/limitation it addresses and why the fix is correct for iOS.
#
# DESIGN PRINCIPLES for any patch added to patches/mpv/:
#   1. Patch the exact unavailable call/type, not a whole file or
#      function — smaller patches are more likely to keep applying
#      cleanly across mpv version bumps, and are far easier to review.
#   2. Before writing a patch, verify against mpv's ACTUAL current source
#      (not a search snippet, not an assumption) exactly which functions
#      are called from which files, so a patch never accidentally hides
#      code that's genuinely needed. Every patch in this project was
#      written this way — see this project's own commit history/PR
#      descriptions for the verification steps taken for each one.
#   3. Every patch file must explain WHAT upstream limitation it works
#      around and WHY the workaround is correct for iOS specifically (not
#      just "makes it compile").
#   4. If a future mpv version changes the patched code enough that a
#      patch stops applying, this script fails loudly (see error handling
#      below) rather than silently skipping it — a broken patch should
#      never be mistaken for "this iOS limitation doesn't exist anymore."

cd "$( dirname "${BASH_SOURCE[0]}" )/.."

MPV_SRC="deps/mpv"
PATCH_DIR="patches/mpv"

if [ ! -d "$MPV_SRC" ]; then
	echo "mpv source not found at $MPV_SRC — run download.sh's mpv clone step first" >&2
	exit 1
fi

shopt -s nullglob
patch_files=("$PATCH_DIR"/*.patch)
shopt -u nullglob

if [ ${#patch_files[@]} -eq 0 ]; then
	echo "No patches found in $PATCH_DIR, nothing to do."
	exit 0
fi

for patch_file in "${patch_files[@]}"; do
	name=$(basename "$patch_file")
	echo "==> Checking patch: $name"

	# --dry-run tells us whether this would apply cleanly, without
	# touching anything yet.
	if (cd "$MPV_SRC" && patch -p1 --dry-run < "../../$patch_file") >/tmp/patch-check.log 2>&1; then
		echo "    Applying..."
		(cd "$MPV_SRC" && patch -p1 < "../../$patch_file")
	elif grep -qi "previously applied\|reversed.*applied" /tmp/patch-check.log; then
		echo "    Already applied, skipping."
	else
		echo "::error::Patch '$name' does not apply cleanly to the current mpv source." >&2
		echo "::error::This usually means upstream mpv changed the code this patch targets." >&2
		echo "::error::The iOS limitation this patch worked around may or may not still exist —" >&2
		echo "::error::check upstream's current source before deciding whether to update or drop it." >&2
		echo "::error::(See buildscripts/patches/mpv/README.md for the process.)" >&2
		cat /tmp/patch-check.log >&2
		exit 1
	fi
done

echo "All iOS compatibility patches applied successfully."
