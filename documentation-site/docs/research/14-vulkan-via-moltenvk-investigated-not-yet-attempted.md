---
id: 14-vulkan-via-moltenvk-investigated-not-yet-attempted
title: "Vulkan via MoltenVK: investigated, not yet attempted"
sidebar_label: "14. Vulkan via MoltenVK: investigated, not yet attempted"
sidebar_position: 14
---

## 14. Vulkan via MoltenVK: investigated, not yet attempted

Documented in full in `ROADMAP.md`'s Phase 4 — summarized here for
completeness of this research log:

- Confirmed `VK_EXT_metal_surface`/`vkCreateMetalSurfaceEXT` can create a
  `VkSurfaceKHR` directly from a `CAMetalLayer`, with **no**
  `NSApplication`/AppKit dependency — unlike mpv's existing macOS Vulkan
  context (`context_mac.m`), which does require it and is why that
  existing file can't simply be reused for iOS.
- Identified `video/out/vulkan/context_android.c` (104 lines, no desktop
  windowing dependency) as the right reference pattern for a hypothetical
  `context_ios.m` — Android has the same "no desktop windowing system"
  constraint iOS does, and mpv already solved it there.
- Checked whether Homebrew's `molten-vk` formula could shortcut building
  MoltenVK from source — it can't; that formula only builds MoltenVK's
  macOS slice, not iOS, since it uses `MoltenVKPackaging.xcodeproj`'s
  macOS-only build scheme.
- Concluded this is a substantially larger undertaking than any single
  fix in this log — five different files/scripts across two build
  systems (meson and MoltenVK's own Xcode-project-based build), none of
  which could be verified without Mac access, unlike the avfoundation
  patches which were debugged against real CI compiler errors one at a
  time. Deliberately not started yet; see `ROADMAP.md` for the full
  breakdown of what it would take.
