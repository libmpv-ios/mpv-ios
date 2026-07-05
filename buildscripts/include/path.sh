#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

os=$(uname -s)
if [[ "$os" != "Darwin" ]]; then
	echo "iOS cross-compilation requires macOS + Xcode. Detected: $os" >&2
	exit 1
fi

[ -z "$cores" ] && cores=$(sysctl -n hw.ncpu)
cores=${cores:-4}

# GNU coreutils' `install` (installed as `ginstall` by `brew install
# coreutils`, since macOS's own BSD /usr/bin/install isn't fully
# command-line-compatible with what autotools-generated Makefiles expect).
# This MUST be an absolute path, not the bare word "install" — several
# libtool-driven `make install` steps (e.g. unibreak.sh) build their own
# install invocation as "$(INSTALL) ../install", and a non-absolute value
# here gets misresolved as a literal relative path from deep inside a
# per-target build directory, failing with "../install: No such file or
# directory" instead of actually running the install program. Matches
# mpv-android's own path.sh (`export INSTALL=\`which ginstall\``) exactly.
export INSTALL=$(which ginstall)
if [ -z "$INSTALL" ]; then
	echo "ginstall not found. Install with: brew install coreutils" >&2
	exit 1
fi

export SED=gsed
if ! command -v gsed >/dev/null; then
	echo "gsed not found. Install with: brew install gnu-sed" >&2
	exit 1
fi

# xcrun-provided toolchain paths, needed by several ./configure scripts
export XCODE_DEVELOPER=$(xcode-select -p)
if [ -z "$XCODE_DEVELOPER" ]; then
	echo "Xcode command line tools not found. Run: xcode-select --install" >&2
	exit 1
fi
