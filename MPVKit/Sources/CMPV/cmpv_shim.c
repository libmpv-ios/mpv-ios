#include "include/cmpv_shim.h"
#include <stdlib.h>
#include <dlfcn.h>

// iOS OpenGL ES entry points are exported directly from the process image
// (statically linked against the OpenGLES framework), so a plain dlsym
// against RTLD_DEFAULT resolves any GLES/EAGL symbol mpv's OpenGL render
// backend asks for through mpv_opengl_init_params.get_proc_address.
void *cmpv_gles_get_proc_address(void *ctx, const char *name) {
    (void)ctx;
    return dlsym(RTLD_DEFAULT, name);
}


// mpv has two distinct "something happened, come check" notification
// channels that both use the same bare `void(*)(void*)` C signature:
//
//   1. mpv_render_context_set_update_callback — "a new video frame is ready
//      to render" (fires on mpv's internal render thread)
//   2. mpv_set_wakeup_callback — "an event is now available in the mpv
//      event queue" (fires from whatever thread mpv's core happens to be
//      running on)
//
// These must NOT share one trampoline slot: mixing them means a render
// update could incorrectly wake the event-polling path and vice versa.
// Each gets its own static slot + its own trampoline symbol.

static cmpv_wakeup_fn g_render_update_notify = NULL;
static void *g_render_update_ctx = NULL;

static cmpv_wakeup_fn g_core_wakeup_notify = NULL;
static void *g_core_wakeup_ctx = NULL;

static void cmpv_render_update_trampoline_impl(void *ctx) {
    (void)ctx;
    if (g_render_update_notify) {
        g_render_update_notify(g_render_update_ctx);
    }
}

static void cmpv_core_wakeup_trampoline_impl(void *ctx) {
    (void)ctx;
    if (g_core_wakeup_notify) {
        g_core_wakeup_notify(g_core_wakeup_ctx);
    }
}

void cmpv_render_update_trampoline(void *ctx) {
    cmpv_render_update_trampoline_impl(ctx);
}

void cmpv_set_render_update_callback(mpv_render_context *render_ctx, void *ctx) {
    mpv_render_context_set_update_callback(render_ctx, cmpv_render_update_trampoline_impl, ctx);
}

void cmpv_register_render_update_fn(cmpv_wakeup_fn fn, void *ctx) {
    g_render_update_notify = fn;
    g_render_update_ctx = ctx;
}

void cmpv_set_wakeup_callback(mpv_handle *mpv, cmpv_wakeup_fn callback, void *ctx) {
    g_core_wakeup_notify = callback;
    g_core_wakeup_ctx = ctx;
    mpv_set_wakeup_callback(mpv, cmpv_core_wakeup_trampoline_impl, ctx);
}
