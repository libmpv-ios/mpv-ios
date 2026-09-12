---
id: 21-mpv-render-context-render-fbo-flipy-skip-inside-an-array-lit
title: "`mpv_render_context_render`: `&fbo`/`&flipY`/`&skip` inside an array literal don't outlive the call"
sidebar_label: "21. `mpv_render_context_render`: `&fbo`/`&flipY`/`&skip` inside an array literal don't outlive the call"
sidebar_position: 22
---

## 21. `mpv_render_context_render`: `&fbo`/`&flipY`/`&skip` inside an array literal don't outlive the call

**What happened:** CI failed at `MPVGLView.swift`'s per-frame render call,
not the render-context-setup code entry 17/20 dealt with, with three
instances of the same error:
```
cannot use inout expression here; argument 'data' must be a pointer that
outlives the call to 'init(type:data:)'
    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &fbo),
```
The offending code built the `renderParams` array as a literal, taking
`&fbo`, `&flipY`, and `&skip` directly inline:
```swift
var renderParams: [mpv_render_param] = [
    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &fbo),
    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: &flipY),
    mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: &skip),
    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
]
let result = mpv_render_context_render(ctx, &renderParams)
```

**Why this doesn't work:** Swift's inout-to-pointer (`&x`) conversion
only guarantees the resulting pointer is valid for the duration of the
single call it's passed directly to. Here, `&fbo` is passed to
`mpv_render_param.init(type:data:)`, not to `mpv_render_context_render`
itself — so the pointer's guaranteed lifetime ends right there, before
the `mpv_render_param` value (now holding a use-after-scope pointer) gets
stored into the array and read later by `mpv_render_context_render`. This
is the same category of bug as entry 17 (a value being used somewhere its
guaranteed lifetime doesn't reach), just surfacing through the compiler's
pointer-lifetime diagnostics instead of a module-import error. Notably,
the near-identical-looking code in `createRenderContext` (entry 17/20)
never had this problem, because it never takes `&x` inline in an array
literal — it always goes through `withUnsafeMutablePointer(to:)` first
and only stores the resulting, explicitly-scoped pointer.

**Actual fix:** wrap the three per-frame values in `withUnsafeMutablePointer`,
nested (one call per pointer, matching the existing pattern in
`createRenderContext`), and build `renderParams` plus call
`mpv_render_context_render` *inside* the innermost closure, so all three
pointers are still within their guaranteed-valid scope at the moment
they're actually used:
```swift
let result = withUnsafeMutablePointer(to: &fbo) { fboPtr in
    withUnsafeMutablePointer(to: &flipY) { flipYPtr in
        withUnsafeMutablePointer(to: &skip) { skipPtr in
            var renderParams: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipYPtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(skipPtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            return mpv_render_context_render(ctx, &renderParams)
        }
    }
}
```

**Lesson:** taking `&x` inline as an argument to a *value initializer*
(here, `mpv_render_param.init`) is a different, weaker guarantee than
taking `&x` as an argument to the function that actually dereferences it.
The compiler only tracks the pointer as valid up to the boundary of
whichever call directly receives the `&`-expression — wrapping it in
another initializer first and stashing the result doesn't extend that
lifetime, even though the code visually appears to hand the pointer
straight to the C API a few lines later. Any per-frame/hot-path render
parameter struct built from local mutable state needs the same
`withUnsafeMutablePointer`-and-call-inside-the-closure treatment as the
one-time render-context setup already used, not just the one-time setup
path — a bug class missed here the first time specifically because it
"looked like" the already-correct code nearby, differing only in being a
plain array literal instead of a nested closure.
