#ifndef CMPV_SHIM_H
#define CMPV_SHIM_H

#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>

/// get_proc_address trampoline for mpv_opengl_init_params. mpv calls this
/// to resolve GLES function pointers by name. iOS's OpenGL ES entry points
/// are statically linked into the process (unlike desktop GL's
/// extension-loading model), so this simply forwards to dlsym against the
/// process image — the standard approach for EAGL/GLES + libmpv render-API
/// integrations.
void *cmpv_gles_get_proc_address(void *ctx, const char *name);

/// Swift closures cannot be passed as C function pointers directly when they
/// capture context, so mpv_render_context_set_update_callback needs a plain
/// `void (*)(void*)` trampoline defined in C. This function forwards into
/// Swift via a stored context pointer that MPVRenderContext manages.
///
/// Equivalent role to mpv-android's render.cpp on_update() callback, which
/// forwards mpv's "please redraw" signal into a Java-visible mechanism
/// (there, a Handler.post(); here, a Swift closure invoked off this
/// trampoline).
void cmpv_render_update_trampoline(void *ctx);

typedef void (*cmpv_wakeup_fn)(void *ctx);

/// Registers the Swift-side function that should run whenever mpv signals
/// a new frame is ready. Must be called BEFORE cmpv_set_render_update_callback
/// so the trampoline has somewhere to forward to.
void cmpv_register_render_update_fn(cmpv_wakeup_fn fn, void *ctx);

/// Registers cmpv_render_update_trampoline as the update callback for the
/// given render context. Uses the fn/ctx registered via
/// cmpv_register_render_update_fn above — kept as a separate call because
/// mpv's C API itself only accepts a bare function pointer, not a closure.
void cmpv_set_render_update_callback(mpv_render_context *render_ctx, void *ctx);

/// Registers a wakeup callback on the mpv core context, used for waking the
/// Swift-side event polling loop instead of pthread's mpv_wait_event(-1.0)
/// blocking loop from mpv-android's event.cpp. `ctx` is passed back verbatim.
/// Uses its own independent callback slot, separate from the render-update
/// slot above.
void cmpv_set_wakeup_callback(mpv_handle *mpv, cmpv_wakeup_fn callback, void *ctx);

#endif /* CMPV_SHIM_H */
