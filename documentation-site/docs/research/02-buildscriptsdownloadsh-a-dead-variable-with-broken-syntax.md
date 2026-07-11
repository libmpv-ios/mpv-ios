---
id: 02-buildscriptsdownloadsh-a-dead-variable-with-broken-syntax
title: "`buildscripts/download.sh`: a dead variable with broken syntax"
sidebar_label: "2. buildscripts/download.sh: a dead variable with broken syntax"
sidebar_position: 2
---

## 2. `buildscripts/download.sh`: a dead variable with broken syntax

**What happened:** an early version of `download.sh` had this line, meant
to optionally allow overriding the download tool:

```bash
[ -z "$WGET" ] && WGET=curl -L -o
```

This is invalid — in bash, `=` with a space after it stops being a plain
variable assignment. `WGET=curl` gets set, and `-L` gets interpreted as a
separate command to run, immediately failing CI with `-L: command not
found`.

**Root cause on inspection:** the `$WGET` variable was never actually
referenced anywhere else in the script — every `fetch_*` function called
`curl` directly. It was dead, unused leftover.

**Fix:** deleted the line entirely.

**Lesson:** dead code that "looks like configuration" is worth deleting
rather than leaving in — it added a bug with zero corresponding benefit.
