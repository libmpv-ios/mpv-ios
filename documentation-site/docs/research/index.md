---
id: index
title: Research Log
sidebar_label: Overview
sidebar_position: 0
---

# Research Log: Porting mpv/libmpv to iOS

This is a chronological record of what was actually discovered, what
broke, and how it was fixed while building this project — not a polished
retrospective, but a working log intended so a future maintainer (or a
past one revisiting this after months away) doesn't have to re-derive any
of this from scratch. Where an earlier assumption turned out to be wrong,
that's recorded too, since knowing *why* something was tried and
abandoned is often as useful as knowing what finally worked.

Each entry follows roughly the same shape: what we assumed or attempted,
what actually happened (an error, or a fact found by reading source
directly), and what we did about it. Entries are ordered chronologically
in the sidebar, which is also roughly the order a from-scratch attempt at
this project would naturally hit them.

:::tip Before opening a new issue
If you've hit a build error, skim the entry titles in the sidebar first —
a striking number of iOS cross-compilation problems turn out to be
version-drift in a dependency's meson/autotools options, a macOS-only API
called from otherwise-portable code, or a build-tool limitation that
looks like a configuration mistake but isn't. There's a good chance
someone (an earlier instance of this same investigation) already hit your
error.
:::

## How to read this

- Entries are numbered in the order they were discovered, not by
  severity or topic — some are one-line fixes, others (like the entry
  covering `0xb17c0de`) took multiple rounds across several CI runs to
  fully diagnose.
- The **General Patterns** page at the end distills the recurring lessons
  across every entry — worth reading even if you don't read every
  individual entry first.
- Several entries reference each other by number (e.g. "see entry 8") —
  these numbers correspond to the sidebar order.
