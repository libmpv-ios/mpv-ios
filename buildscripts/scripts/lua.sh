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

mycflags=(
	-fPIC
	-DLUA_USE_IOS
)

make CC="$CC" AR="$AR rcu" RANLIB="$RANLIB" \
	MYCFLAGS="${mycflags[*]}" \
	PLAT=generic LUA_T= LUAC_T= -j$cores

make INSTALL="${INSTALL:-install}" INSTALL_TOP="$prefix_dir" TO_BIN=/dev/null install

mkdir -p $prefix_dir/lib/pkgconfig
make pc >$prefix_dir/lib/pkgconfig/lua.pc
cat >>$prefix_dir/lib/pkgconfig/lua.pc <<'EOF'
Name: Lua
Description:
Version: ${version}
Libs: -L${libdir} -llua
Cflags: -I${includedir}
EOF
