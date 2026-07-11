---
id: 01-the-render-backend-metal-was-assumed-then-found-not-to-exist
title: "The render backend: Metal was assumed, then found not to exist"
sidebar_label: "1. The render backend: Metal was assumed, then found not to exist"
sidebar_position: 1
---

## 1. The render backend: Metal was assumed, then found not to exist

**Initial assumption:** libmpv would have a Metal render-API backend,
analogous to its OpenGL backend, since Metal is Apple's modern graphics
API and mpv already runs well on macOS.

**What we actually found:** reading libmpv's own public headers directly
(`include/mpv/render.h`, `include/mpv/render_gl.h`) shows only two render
API types are defined: `MPV_RENDER_API_TYPE_OPENGL` and
`MPV_RENDER_API_TYPE_SW` (software rendering). No Metal type exists in
the public render API at all.

mpv's own Metal usage on macOS (`video/out/vulkan/context_mac.m`) doesn't
go through the render API at all — it uses mpv's internal Vulkan context
system, translated to Metal via MoltenVK, and depends directly on
`NSApplication`/AppKit (`if (!NSApp) { ... "no NSApplication initialized" }`).
This path is fundamentally tied to desktop windowing and doesn't apply to
an embedded-in-an-app-view scenario like iOS.

**What mpv actually ships for iOS:** `video/out/hwdec/hwdec_ios_gl.m`,
gated by meson's `ios-gl` feature — OpenGL ES via EAGL, with VideoToolbox
hardware-decoded frames imported through `CVOpenGLESTextureCache`. This is
the real, upstream-supported iOS path.

**What we did:** built `MPVGLView.swift` around `CAEAGLLayer` +
`EAGLContext` + libmpv's OpenGL render API, matching mpv's own intended
iOS integration rather than inventing a Metal path that doesn't exist.
See the main README's "Architecture notes" section for the full write-up
this became.

**Lesson:** "this modern API surely has a backend for the modern graphics
framework" is a reasonable-sounding assumption that turned out false —
checking the actual public header before writing any dependent code
avoided building an entire render view around an API that doesn't exist.
