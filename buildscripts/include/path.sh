#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

os=$(uname -s)
if [[ "$os" != "Darwin" ]]; then
	echo "iOS cross-compilation requires macOS + Xcode. Detected: $os" >&2
	exit 1
fi

[ -z "$cores" ] && cores=$(sysctl -n hw.ncpu)
cores=${cores:-4}

export INSTALL=install
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
