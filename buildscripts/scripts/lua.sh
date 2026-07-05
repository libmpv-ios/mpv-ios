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

# WHY THIS IS NEEDED: iOS's SDK marks system(3) as explicitly unavailable
# (App Store sandboxing forbids arbitrary shell command execution), so any
# call to it is a hard compile error, not just a runtime failure.
# -DLUA_USE_IOS alone does NOT fix this: Lua's own guard for it (an
# `l_system` macro in loslib.c that skips calling system() when
# LUA_USE_IOS is defined) was only added in Lua 5.4 — verified directly
# against Lua's published source for 5.1, 5.2, 5.3, and 5.4. This project
# is pinned to Lua 5.2.4 (see depinfo.sh) because mpv itself only ever
# supports Lua 5.1, 5.2, or LuaJIT and explicitly will not support 5.3+
# (see mpv's own FAQ), so upgrading Lua to pick up the 5.4 fix isn't an
# option here.
#
# Instead, we force-include a small header (via -include, applied to every
# translation unit) that #defines system(cmd) to a stub before loslib.c's
# unconditional `system(cmd)` call (Lua 5.2.4's os_execute) ever sees the
# real, unavailable-on-iOS declaration from <stdlib.h>. This makes
# os.execute() in any mpv Lua script a no-op reporting "no shell available"
# (returns -1, matching system(NULL)'s own convention for "no command
# processor is available") instead of refusing to compile at all. No mpv
# default script actually calls os.execute, so this only matters for
# third-party user scripts that might.
cat > ios_no_system.h <<'EOF'
#ifndef IOS_NO_SYSTEM_H
#define IOS_NO_SYSTEM_H
#include <stdlib.h>
#undef system
#define system(cmd) ((cmd) ? -1 : 0)
#endif
EOF

mycflags=(
	-fPIC
	-DLUA_USE_IOS
	-include "$(pwd)/ios_no_system.h"
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
