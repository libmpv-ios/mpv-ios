---
id: 20-xcode-16-2s-stricter-c-string-macro-import-made-mpv-render-a
title: "Xcode 16.2's stricter C-string macro import made `MPV_RENDER_API_TYPE_OPENGL` ambiguous"
sidebar_label: "20. Xcode 16.2's stricter C-string macro import made `MPV_RENDER_API_TYPE_OPENGL` ambiguous"
sidebar_position: 20
---

## 20. Xcode 16.2's stricter C-string macro import made `MPV_RENDER_API_TYPE_OPENGL` ambiguous

**What happened:** after the enum-interop fixes from entry 18 and the
`DispatchQueue.sync` extraction in entry 19, CI progressed further into
`MPVGLView.swift` and then failed at:

```swift
let apiTypeGL = UnsafeMutablePointer(mutating: MPV_RENDER_API_TYPE_OPENGL)
```

with:

```text
error: type of expression is ambiguous without a type annotation
```

The surrounding build log contained many raw Clang module-compilation
messages, but inspection of the final Swift compiler diagnostics showed this
was the first real compilation failure.

**Root cause:** `MPV_RENDER_API_TYPE_OPENGL` is **not** a Swift constant defined
by this project. It comes directly from libmpv's public
`include/mpv/render.h` header as the C macro:

```c
#define MPV_RENDER_API_TYPE_OPENGL "opengl"
```

Under Xcode 16.2 / the iOS 18.2 SDK, Swift's Clang importer became stricter
about C string-literal macros. Instead of unambiguously flowing into
`UnsafeMutablePointer(mutating:)`, the imported macro can now match more than
one valid Swift representation (for example, a C-string pointer versus a
Swift string-like type). As a result, Swift can no longer determine which
`UnsafeMutablePointer(mutating:)` overload should be selected, reporting the
expression itself as ambiguous.

To verify this, the entire package was searched for
`MPV_RENDER_API_TYPE_OPENGL` and the related software-rendering macro.
Neither was used anywhere else, confirming the ambiguity was localized to a
single call site rather than requiring a project-wide migration.

**Fix:** rather than relying on implicit bridging, the imported C macro is
first bound to an explicitly typed C-string pointer, making the conversion
target unambiguous before passing it into
`UnsafeMutablePointer(mutating:)`:

```swift
let apiTypeGLCString: UnsafePointer<CChar> = MPV_RENDER_API_TYPE_OPENGL
let apiTypeGL = UnsafeMutablePointer(mutating: apiTypeGLCString)
```

This preserves the exact runtime behavior while giving Swift's type checker
the information it now requires under the newer SDK.

**Lesson:** when a newer Swift toolchain reports a C macro as "ambiguous,"
the underlying problem may not be the API being called, but how the Clang
Importer now bridges that macro into Swift. Giving imported C values an
explicit intermediate type before passing them into overloaded APIs is often
more robust than depending on implicit inference, especially for legacy
`const char *` macros originating from C libraries. The same C header can
compile unchanged for years while newer Swift/C interop rules require more
explicit typing at the call site.
