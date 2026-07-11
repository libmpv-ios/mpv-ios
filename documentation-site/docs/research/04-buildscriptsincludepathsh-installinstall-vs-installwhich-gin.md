---
id: 04-buildscriptsincludepathsh-installinstall-vs-installwhich-gin
title: "`buildscripts/include/path.sh`: `INSTALL=install` vs `INSTALL=$(which ginstall)`"
sidebar_label: "4. buildscripts/include/path.sh: INSTALL=install vs INSTALL=$(which ginstall)"
sidebar_position: 4
---

## 4. `buildscripts/include/path.sh`: `INSTALL=install` vs `INSTALL=$(which ginstall)`

**What happened:** the `unibreak` dependency failed during `make install`
with:
```
../libtool: line 1883: ../install: No such file or directory
```

**Root cause:** `path.sh` set `export INSTALL=install` — a bare word, not
an absolute path. Several autotools-generated Makefiles (via libtool)
construct their own install invocation in a way that resolves a
non-absolute `$(INSTALL)` value as a literal relative path from deep
inside a per-target build directory, rather than searching `$PATH` the
way a plain shell command would. The result: it looked for a literal
file named `../install` relative to the build directory, which doesn't
exist.

mpv-android's own `path.sh` (checked directly, since this project mirrors
its structure) does this correctly on macOS: `` export INSTALL=`which
ginstall` `` — GNU coreutils' `install` (installed as `ginstall` via
`brew install coreutils`, since macOS's BSD `/usr/bin/install` isn't
fully command-line-compatible with what autotools-generated Makefiles
expect), as a full absolute path.

**Fix:** matched mpv-android's approach — `INSTALL=$(which ginstall)`,
with an explicit error if `ginstall` isn't found (telling the user to
`brew install coreutils`). Added `coreutils` to every `brew install` list
in this repo (both READMEs, `build.yml`, `release.yml`).

**Lesson:** when porting a build-script pattern from another platform's
equivalent project (mpv-android, in this case), copy the *reasoning*, not
just an approximation of the syntax — the original bare-word choice here
looked like a plausible simplification but silently broke a real
constraint the original code was satisfying.
