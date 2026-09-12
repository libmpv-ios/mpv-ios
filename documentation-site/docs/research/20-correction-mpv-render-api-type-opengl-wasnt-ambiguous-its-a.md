---
id: 20-correction-mpv-render-api-type-opengl-wasnt-ambiguous-its-a
title: "Correction: `MPV_RENDER_API_TYPE_OPENGL` wasn't ambiguous — it's a plain `String`"
sidebar_label: "20. Correction: `MPV_RENDER_API_TYPE_OPENGL` wasn't ambiguous — it's a plain `String`"
sidebar_position: 21
---

## 20. Correction: `MPV_RENDER_API_TYPE_OPENGL` wasn't ambiguous — it's a plain `String`

**What happened:** the fix described in the entry above (binding
`MPV_RENDER_API_TYPE_OPENGL` to an explicit `UnsafePointer<CChar>`
constant) was believed to resolve the type issue, but the very next CI
run failed at the same line with a different, more specific error:
```
MPVGLView.swift:139:54: error: cannot convert value of type 'String' to
specified type 'UnsafePointer<CChar>' (aka 'UnsafePointer<Int8>')
```

**What this reveals about the previous entry's diagnosis:** the earlier
fix assumed the Clang Importer was offering *two* possible types for this
macro (an "ambiguous" overload situation) and that pinning one down
explicitly would settle it. The actual compiler error shows this wasn't
quite right — under the Xcode 16.2 / iOS 18.2 SDK combination this
project's CI uses, `MPV_RENDER_API_TYPE_OPENGL` (`#define
MPV_RENDER_API_TYPE_OPENGL "opengl"` in libmpv's `render_gl.h`) imports
as a plain Swift `String`, not as anything resembling
`UnsafePointer<CChar>` at all. There was no ambiguity to resolve — the
`let apiTypeGLCString: UnsafePointer<CChar> = MPV_RENDER_API_TYPE_OPENGL`
line was a direct type mismatch, doomed to fail regardless of how
explicitly it was annotated, since a `String` cannot be assigned to an
`UnsafePointer<CChar>`-typed constant no matter how that constant is
declared.

**Actual fix:** bridge the `String` to a C string pointer properly, using
`MPV_RENDER_API_TYPE_OPENGL.withCString { apiTypeGL in ... }`. Since
`withCString`'s pointer is only valid for the duration of its closure,
and `mpv_render_context_create` is a synchronous call that doesn't retain
the pointer past its own return, the entire render-context-creation logic
(previously two levels of nested `withUnsafeMutablePointer` calls) was
moved one level deeper, inside this closure, rather than trying to
extract a longer-lived pointer via `strdup` (which would need matching
manual `free` cleanup for no actual benefit, since nothing needs the
string to outlive this one call).

A missing closing brace was also introduced when the previous fix
attempt added its own nesting level without adjusting the function's
final closing braces to match — worth specifically re-counting brace
nesting depth by hand after adding or removing a closure level in a
deeply-nested function like this one, since a brace-count mismatch can
produce confusing, seemingly unrelated compile errors far from the
actual missing brace.

**Lesson:** "ambiguous" and "cannot convert" are different diagnoses that
call for different fixes, even when they point at the same line and
involve the same values — worth reading the *exact* error text on each
new CI failure rather than assuming a previous, related-looking error
was just incompletely fixed by the same mechanism. Here, the first fix's
own reasoning (macros can import as multiple possible types under newer
interop rules) was a real, generally-true fact about Swift/C interop, but
didn't happen to be what was actually going wrong at this specific call
site — the real answer was simpler (a single, unambiguous `String`
import) than the theorized one (an unresolved overload).
