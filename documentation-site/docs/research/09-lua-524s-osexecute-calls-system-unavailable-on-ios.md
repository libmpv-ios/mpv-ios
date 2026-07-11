---
id: 09-lua-524s-osexecute-calls-system-unavailable-on-ios
title: "Lua 5.2.4's `os.execute()` calls `system()`, unavailable on iOS"
sidebar_label: "9. Lua 5.2.4's os.execute() calls system(), unavailable on iOS"
sidebar_position: 9
---

## 9. Lua 5.2.4's `os.execute()` calls `system()`, unavailable on iOS

**What happened:**
```
loslib.c:82:14: error: 'system' is unavailable: not available on iOS
```

**Initial (wrong) assumption:** that `-DLUA_USE_IOS` (which we'd already
set) would guard this, the way it seemed to elsewhere in Lua.

**What we actually found, by checking Lua's published source across
versions directly:** the `LUA_USE_IOS`-aware guard around `system()` (an
`l_system` macro in `loslib.c`) was only added in **Lua 5.4**. This
project pins Lua 5.2.4 (see `depinfo.sh`), and 5.2.4's `loslib.c` calls
`system(cmd)` unconditionally with no iOS-awareness at all.

**Why we can't just upgrade Lua to fix this:** mpv's own FAQ states
explicitly that mpv does not and will not support Lua 5.3 or newer — only
5.1, 5.2, or LuaJIT. So "upgrade to 5.4" isn't an available option here.

**Fix:** rather than patching Lua's own source, `lua.sh` force-includes
(`-include`) a small generated header that `#undef`s and redefines the
`system` macro to a harmless stub (`return cmd ? -1 : 0`, matching
`system(NULL)`'s own "no command processor available" convention) before
`loslib.c`'s reference to it is ever compiled. `os.execute()` calls from
any Lua script become a no-op reporting failure, rather than the build
refusing to compile. No mpv default script actually calls `os.execute()`,
so this has no practical runtime impact for normal playback.

**Lesson:** a macro that "should" guard something based on its name isn't
guaranteed to — verifying against the actual version in use (not the
latest version's behavior) mattered here, since the fix upstream added in
a later release doesn't retroactively apply to the older, still-in-use
version this project depends on.
