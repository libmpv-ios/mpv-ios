#!/bin/bash -e

. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	make clean 2>/dev/null || true
	exit 0
else
	exit 255
fi

$0 clean

# AES-NI is x86-only; ARM has its own crypto extensions handled elsewhere
if [[ "$arch" == "arm64" ]]; then
	./scripts/config.py unset MBEDTLS_AESNI_C
fi

make -j$cores no_test \
	CC="$CC" AR="$AR" LD="$LD" \
	WARNING_CFLAGS="" \
	CFLAGS="-O2 -fPIC"
make DESTDIR="$prefix_dir" install
