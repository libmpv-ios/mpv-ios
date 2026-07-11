---
id: 07-legacy-configsub-doesnt-recognize-modern-apple-simulator-tri
title: "Legacy `config.sub` doesn't recognize modern Apple simulator triples"
sidebar_label: "7. Legacy config.sub doesn't recognize modern Apple simulator triples"
sidebar_position: 7
---

## 7. Legacy `config.sub` doesn't recognize modern Apple simulator triples

**What happened:** several autotools-based dependencies (`fribidi`,
`harfbuzz`, `libxml2`) failed their `./configure` step specifically for
the simulator platform slices, rejecting the host triple as unrecognized.

**Root cause:** these dependencies bundle their own copies of GNU
autotools' `config.sub` (the script that validates and canonicalizes
`--host` triples), and older bundled copies predate Apple's simulator
target triples (`aarch64-apple-ios-simulator`,
`x86_64-apple-ios-simulator`) — `config.sub` simply doesn't have a rule
matching them, so `configure` aborts with an "invalid host" style error
before ever reaching the compiler.

**Fix:** rather than patching or regenerating `config.sub` inside every
affected dependency's extracted source (fragile — a per-dependency patch
that would need re-verifying against each project's own bundled
autotools version), `buildall.sh` overrides the `host_triple` value
passed to `configure` for the simulator platforms specifically, to a
generic `aarch64-apple-darwin`/`x86_64-apple-darwin` triple that older
`config.sub` copies **do** recognize. This satisfies `configure`'s
validation step, while the actual compilation target (architecture,
sysroot, and the iOS Simulator deployment constraints) stays correctly
locked in via the explicit `-arch`/`-isysroot`/version-min flags already
present in `CC`/`LDFLAGS` — `config.sub`'s job here is just a string
plausibility check, not the actual source of truth for what gets built.

**Lesson:** an autotools "unrecognized triple" error doesn't necessarily
mean the target is actually unsupported — it can mean the specific bundled
`config.sub` copy predates a legitimate target that the rest of the
toolchain handles fine. Substituting a triple the validation script
already understands, while keeping the real compiler flags accurate, is
a reasonable workaround when patching every dependency's own
autotools files individually would be more fragile.
