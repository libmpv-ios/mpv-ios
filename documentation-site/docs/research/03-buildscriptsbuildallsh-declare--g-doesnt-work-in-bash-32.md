---
id: 03-buildscriptsbuildallsh-declare--g-doesnt-work-in-bash-32
title: "`buildscripts/buildall.sh`: `declare -g` doesn't work in bash 3.2"
sidebar_label: "3. buildscripts/buildall.sh: declare -g doesn't work in bash 3.2"
sidebar_position: 3
---

## 3. `buildscripts/buildall.sh`: `declare -g` doesn't work in bash 3.2

**What happened:** CI failed with:
```
./buildall.sh: line 31: declare: -g: invalid option
```

**Root cause:** `markbuilt()` used `declare -g "$varname=0"` to set a
dynamically-named global variable. `declare -g` requires bash 4.2+. macOS
ships bash 3.2 as its system `/bin/bash` (Apple stopped updating bash for
GPLv3 licensing reasons around that version), and GitHub's `macos-14`
runner invokes workflow steps with that same system bash unless a script
explicitly re-execs itself under a newer one.

**Fix:** replaced with `eval "$varname=0"`, which achieves the same
dynamic-variable-assignment effect and works identically on bash 3.2 and
newer.

**Lesson:** any bash feature added to this project's scripts needs to be
checked against bash 3.2 compatibility, not just "does this work on my
own machine" — a developer's personal machine likely has a newer
Homebrew-installed bash that CI does not use by default.
