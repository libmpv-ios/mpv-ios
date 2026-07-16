import UIKit
import OpenGLES
import CMPV

/// Renders mpv video output using OpenGL ES + the mpv render API.
///
/// This is the iOS counterpart to mpv-android's rendering path
/// (MPVView.kt driving a SurfaceView/GLSurfaceView, with render.cpp's
/// mpv_render_context_render() calls happening on the GL thread there).
/// Since libmpv has no Metal render backend (see the note in
/// MPVConfiguration.swift and buildscripts/README.md), this uses the
/// backend mpv upstream actually supports and ships for iOS: OpenGL ES via
/// EAGL, with hardware-decoded frames imported zero-copy through
/// CVOpenGLESTextureCache (handled internally by mpv's hwdec_ios_gl.m —
/// nothing extra is required here beyond making an EAGLContext current).
///
/// Threading model (mirrors mpv-android's render.cpp comments and the
/// render API's own threading requirements in render.h):
///  - All mpv_render_* calls happen on a dedicated serial render queue,
///    never on the main thread, to avoid blocking UI on decode/render work.
///  - The EAGLContext is made current on that same queue before any GL or
///    mpv_render_* call — EAGLContext, like all GL contexts, is implicitly
///    per-thread.
///  - mpv's update callback (fired from mpv's own internal thread) hops
///    onto our render queue to schedule a redraw; it never touches GL
///    directly itself (per render.h's rules: "never call libmpv API
///    functions... from within the update callback").
public final class MPVGLView: UIView {

    public override class var layerClass: AnyClass { CAEAGLLayer.self }

    private var eaglLayer: CAEAGLLayer { layer as! CAEAGLLayer }

    private let eaglContext: EAGLContext
    private let renderQueue = DispatchQueue(label: "mpv.gl.render", qos: .userInteractive)

    private var renderContext: OpaquePointer? // mpv_render_context*
    private weak var core: MPVCore?

    private var framebuffer: GLuint = 0
    private var colorRenderbuffer: GLuint = 0
    private var drawableWidth: GLint = 0
    private var drawableHeight: GLint = 0

    /// Guards against redrawing after teardown started, and against
    /// concurrent render calls (mpv_render_context_render is not
    /// re-entrant for a given context — see render.h's Threading section).
    private var isDestroyed = false
    private var isRendering = false
    private var needsRedraw = true

    // advanced-control flag storage; kept as a static so its address is
    // stable for the lifetime of the render_param array construction.
    private static var advancedControlOn: CInt = 1

    public init?(core: MPVCore) {
        guard let context = EAGLContext(api: .openGLES3) else {
            return nil
        }
        self.eaglContext = context
        self.core = core
        super.init(frame: .zero)

        eaglLayer.isOpaque = true
        eaglLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
        ]

        contentScaleFactor = UIScreen.main.scale
    }

    public required init?(coder: NSCoder) {
        fatalError("MPVGLView must be created with init(core:)")
    }

    deinit {
        teardown()
    }

    // MARK: - Setup

    /// Creates the mpv render context bound to this view's EAGL context.
    /// Must be called after `core.initialize()` has succeeded (mpv needs an
    /// initialized core before a render context can attach to it) and
    /// before the view is asked to draw.
    ///
    /// Equivalent role to mpv-android's render.cpp `create()` /
    /// mpv_render_context_create() call, which there is invoked once the
    /// Android Surface is ready.
    public func attachRenderContext() throws {
        guard let core else { throw MPVError.notCreated }
        guard renderContext == nil else { return }

        var creationError: MPVError?

        renderQueue.sync { () -> Void in
            EAGLContext.setCurrent(eaglContext)
            creationError = self.createRenderContext(core: core)
        }

        if let creationError {
            throw creationError
        }
    }

    /// Does the actual mpv_render_context_create() call and wires up the
    /// update callback. Pulled out of attachRenderContext()'s `sync`
    /// closure into its own non-generic method specifically to resolve a
    /// real "ambiguous use of 'sync(execute:)'" compile error: nesting
    /// generic, `rethrows` calls (`withUnsafeMutablePointer(to:_:)`)
    /// directly inside the `renderQueue.sync { ... }` trailing closure
    /// defeated Swift's ability to confidently resolve which of
    /// DispatchQueue's two `sync` overloads (the generic/throwing one vs.
    /// the plain `() -> Void` one) was intended — even with an explicit
    /// `() -> Void in` annotation on the outer closure itself. Moving the
    /// nested-generic-call pyramid into its own ordinary method removes
    /// the nested generics from the `sync` closure's body entirely, which
    /// is what actually resolves the ambiguity (the annotation alone did
    /// not). See docs/RESEARCH.md for the full incident, including the
    /// first, insufficient attempt at fixing this.
    private func createRenderContext(core: MPVCore) -> MPVError? {
        var initParams = mpv_opengl_init_params(
            get_proc_address: { ctx, name in
                cmpv_gles_get_proc_address(ctx, name)
            },
            get_proc_address_ctx: nil
        )

        let apiTypeGL = UnsafeMutablePointer(mutating: MPV_RENDER_API_TYPE_OPENGL)

        return withUnsafeMutablePointer(to: &Self.advancedControlOn) { advancedControlPtr -> MPVError? in
            withUnsafeMutablePointer(to: &initParams) { initParamsPtr -> MPVError? in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiTypeGL)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initParamsPtr)),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: UnsafeMutableRawPointer(advancedControlPtr)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]

                var ctx: OpaquePointer?
                let result = mpv_render_context_create(&ctx, core.handle, &params)
                guard result >= 0, let ctx else {
                    return MPVError(result)
                }
                self.renderContext = ctx

                // Route mpv's "new frame ready" notifications to our
                // render queue. The C-trampoline indirection here is
                // required because Swift closures that capture context
                // cannot be passed where the C API expects a bare
                // function pointer (see cmpv_shim.h).
                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                cmpv_register_render_update_fn({ ctxPtr in
                    guard let ctxPtr else { return }
                    let view = Unmanaged<MPVGLView>.fromOpaque(ctxPtr).takeUnretainedValue()
                    view.renderQueue.async { [weak view] in
                        view?.needsRedraw = true
                        view?.drawIfNeeded()
                    }
                }, selfPtr)
                cmpv_set_render_update_callback(ctx, selfPtr)

                return nil
            }
        }
    }

    /// Tears down the mpv render context and GL objects. Must be called
    /// before the underlying MPVCore is destroyed (render.h: "You must free
    /// the context with mpv_render_context_free() before the mpv core is
    /// destroyed"). Safe to call multiple times.
    public func teardown() {
        renderQueue.sync { () -> Void in
            guard !isDestroyed else { return }
            isDestroyed = true

            EAGLContext.setCurrent(eaglContext)

            if let ctx = renderContext {
                mpv_render_context_free(ctx)
                renderContext = nil
            }

            deleteFramebuffer()
            if EAGLContext.current() === eaglContext {
                EAGLContext.setCurrent(nil)
            }
        }
    }

    // MARK: - Layout / drawable sizing

    public override func layoutSubviews() {
        super.layoutSubviews()
        renderQueue.async { [weak self] in
            self?.rebuildFramebufferIfNeeded()
            self?.needsRedraw = true
            self?.drawIfNeeded()
        }
    }

    private func rebuildFramebufferIfNeeded() {
        EAGLContext.setCurrent(eaglContext)

        let newWidth = GLint(bounds.width * contentScaleFactor)
        let newHeight = GLint(bounds.height * contentScaleFactor)
        guard newWidth > 0, newHeight > 0 else { return }
        guard newWidth != drawableWidth || newHeight != drawableHeight || framebuffer == 0 else { return }

        deleteFramebuffer()

        glGenRenderbuffers(1, &colorRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        eaglContext.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer)

        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                   GLenum(GL_RENDERBUFFER), colorRenderbuffer)

        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &drawableWidth)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &drawableHeight)

        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            assertionFailure("MPVGLView: incomplete framebuffer, status \(status)")
        }
    }

    private func deleteFramebuffer() {
        if framebuffer != 0 {
            glDeleteFramebuffers(1, &framebuffer)
            framebuffer = 0
        }
        if colorRenderbuffer != 0 {
            glDeleteRenderbuffers(1, &colorRenderbuffer)
            colorRenderbuffer = 0
        }
    }

    // MARK: - Drawing

    /// Renders the current mpv frame into our FBO-backed renderbuffer and
    /// presents it. Called from the render queue only.
    ///
    /// Equivalent to mpv-android's render.cpp draw path
    /// (mpv_render_context_render into the GLSurfaceView's implicit FBO,
    /// followed by eglSwapBuffers); here we render into our own named FBO
    /// (id 0 is not the default framebuffer under CAEAGLLayer, unlike
    /// desktop GL) and then call presentRenderbuffer ourselves.
    private func drawIfNeeded() {
        dispatchPrecondition(condition: .onQueue(renderQueue))
        guard !isDestroyed, !isRendering else { return }
        guard let ctx = renderContext else { return }
        guard needsRedraw else { return }
        guard framebuffer != 0 else { return }

        isRendering = true
        defer { isRendering = false }

        EAGLContext.setCurrent(eaglContext)

        // Ask mpv whether a new frame is actually ready. Required when
        // MPV_RENDER_PARAM_ADVANCED_CONTROL is set (render.h: "it's a hard
        // requirement that this is called after each update callback").
        let flags = mpv_render_context_update(ctx)
        guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else {
            return
        }
        needsRedraw = false

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glViewport(0, 0, drawableWidth, drawableHeight)

        var fbo = mpv_opengl_fbo(
            fbo: Int32(framebuffer),
            w: Int32(drawableWidth),
            h: Int32(drawableHeight),
            internal_format: 0
        )
        // CAEAGLLayer's coordinate origin matches what mpv expects by
        // default when flip_y is 0 (unlike a desktop GL default
        // framebuffer, which is bottom-left and needs FLIP_Y=1).
        var flipY: CInt = 0
        var skip: CInt = 0

        var renderParams: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &fbo),
            mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: &flipY),
            mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: &skip),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
        ]

        let result = mpv_render_context_render(ctx, &renderParams)
        if result < 0 {
            return
        }

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        eaglContext.presentRenderbuffer(Int(GL_RENDERBUFFER))

        mpv_render_context_report_swap(ctx)
    }

    /// Forces an immediate redraw regardless of the "new frame available"
    /// state — used for paused-frame redraws after a resize, subtitle
    /// toggle, etc. Equivalent to mpv-android's explicit
    /// MPVView.requestRender() call sites.
    public func requestRedraw() {
        renderQueue.async { [weak self] in
            self?.needsRedraw = true
            self?.drawIfNeeded()
        }
    }
}
