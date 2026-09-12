import Foundation
import CoreVideo
import CoreMedia
import OpenGLES

/// Copies an already-rendered GL framebuffer into an IOSurface-backed
/// `CVPixelBuffer` via `glBlitFramebuffer`, and wraps the result as a
/// `CMSampleBuffer` ready for `AVSampleBufferDisplayLayer.enqueue(_:)`.
///
/// Deliberately does NOT call `mpv_render_context_render()` a second
/// time. mpv's own render.h documents that each render call "implicitly
/// pulls a video frame from the internal queue" — calling it twice per
/// displayed frame (once for the screen, once for PiP) risks the two
/// outputs showing different frames, or one path starving the other of
/// frames. Instead this reads back the *same* frame mpv already
/// rendered once for the screen (`MPVGLView`'s existing `colorRenderbuffer`)
/// via a GPU-side blit — no second mpv render, no CPU pixel readback
/// (`glReadPixels`), so this adds no meaningful cost to the existing
/// per-frame screen render.
///
/// This is intentionally a separate, self-contained type rather than
/// code folded into `MPVGLView` itself — everything here is additive
/// (it reads from a framebuffer `MPVGLView` already created and
/// populated, immediately after `MPVGLView`'s own present call) and can
/// be deleted or disabled entirely without touching a single line of
/// the existing screen-rendering path.
public final class PictureInPictureRenderer {
    private var pixelBufferPool: CVPixelBufferPool?
    private var textureCache: CVOpenGLESTextureCache?
    private var currentTexture: CVOpenGLESTexture?
    private var blitFBO: GLuint = 0
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0

    /// Presentation timestamps for enqueued sample buffers must be
    /// monotonically increasing (CMSampleBuffer/display-layer
    /// requirement) — mpv's own `time-pos` isn't guaranteed monotonic
    /// across seeks, so this generates its own timeline instead of
    /// reusing mpv's playback clock.
    private var frameCount: Int64 = 0

    public init() {}

    deinit {
        if blitFBO != 0 {
            glDeleteFramebuffers(1, &blitFBO)
        }
        // CVOpenGLESTextureCache and CVPixelBufferPool are CFTypes,
        // released automatically by ARC/CF bridging — no explicit
        // teardown call needed for either, unlike the mpv_render_context
        // in MPVGLView.teardown() (that one wraps a C API resource with
        // no ARC bridging).
    }

    /// Must be called with `eaglContext` current on the calling thread —
    /// mirrors `MPVGLView.attachRenderContext()`'s own requirement for
    /// the same reason (`CVOpenGLESTextureCacheCreate` binds to whichever
    /// EAGLContext is current at creation time).
    public func setUp(eaglContext: EAGLContext) -> Bool {
        var cache: CVOpenGLESTextureCache?
        let result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, eaglContext, nil, &cache)
        guard result == kCVReturnSuccess, let cache else { return false }
        textureCache = cache

        glGenFramebuffers(1, &blitFBO)
        return true
    }

    /// Rebuilds the backing pixel buffer pool if the source size changed.
    /// Called from `blit(from:width:height:)` itself so callers never
    /// need to track size changes separately.
    private func ensurePool(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        guard width != poolWidth || height != poolHeight || pixelBufferPool == nil else { return true }

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            // Required for CVOpenGLESTextureCacheCreateTextureFromImage
            // to accept this buffer at all (kCVReturnPixelBufferNotOpenGLCompatible
            // otherwise) — confirmed via Apple Technical Q&A QA1781, which
            // documents this exact requirement and error code.
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            // Lets AVSampleBufferDisplayLayer / Core Animation display
            // this buffer directly without an extra copy on their side.
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            pixelBufferAttributes as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else { return false }

        pixelBufferPool = pool
        poolWidth = width
        poolHeight = height
        return true
    }

    /// Blits the color contents of `sourceFramebuffer` (assumed already
    /// bound-renderable, i.e. framebuffer-complete, in the currently
    /// current EAGLContext) into a fresh IOSurface-backed pixel buffer,
    /// and returns it wrapped as a `CMSampleBuffer`. Returns nil if setup
    /// hasn't succeeded yet or any step fails — callers should treat a
    /// nil result as "skip this frame for PiP", not a fatal error, since
    /// an occasional dropped PiP frame is far less disruptive than
    /// interrupting the main screen render over it.
    public func makeSampleBuffer(
        blittingFrom sourceFramebuffer: GLuint,
        width: Int,
        height: Int
    ) -> CMSampleBuffer? {
        guard let textureCache else { return nil }
        guard ensurePool(width: width, height: height) else { return nil }
        guard let pool = pixelBufferPool else { return nil }

        var pixelBufferOut: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut) == kCVReturnSuccess,
              let pixelBuffer = pixelBufferOut
        else { return nil }

        currentTexture = nil // release the previous frame's texture before creating a new one
        var texture: CVOpenGLESTexture?
        // GL_RENDERBUFFER here (not GL_TEXTURE_2D): per Apple's own
        // CVOpenGLESTextureCache documentation and the widely-used
        // "render to IOSurface-backed CVPixelBuffer" pattern it
        // describes, a pixel buffer used as a *render target* (as
        // opposed to a decoded-frame *source*, which is what
        // MPVKit's existing hwdec_ios_gl.m-equivalent path maps as a
        // GL_TEXTURE_2D) is mapped as a renderbuffer attachment.
        //
        // internalFormat=GL_RGBA / format=GL_BGRA / type=GL_UNSIGNED_BYTE
        // is the exact combination documented for wrapping a BGRA
        // CVPixelBuffer this way — internalFormat describes channel
        // *count* to the cache (not byte order or an OES sized-format
        // enum), while format/type describe the buffer's actual memory
        // layout (native iOS pixel data is BGRA). Passing a sized OES
        // enum (e.g. GL_RGBA8_OES) for internalFormat here is a
        // documented-elsewhere-but-wrong-here mistake for this specific
        // API — verified directly against a working reference
        // implementation rather than assumed from the render-target
        // GL_RGBA8_OES usage seen in unrelated iOS texture-storage code.
        let result = CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            GLenum(GL_RENDERBUFFER),
            GL_RGBA,
            GLsizei(width),
            GLsizei(height),
            GLenum(GL_BGRA),
            GLenum(GL_UNSIGNED_BYTE),
            0,
            &texture
        )
        guard result == kCVReturnSuccess, let texture else { return nil }
        currentTexture = texture

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), blitFBO)
        glFramebufferRenderbuffer(
            GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_RENDERBUFFER), CVOpenGLESTextureGetName(texture)
        )
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        guard status == GLenum(GL_FRAMEBUFFER_COMPLETE) else {
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
            return nil
        }

        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), sourceFramebuffer)
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), blitFBO)
        glBlitFramebuffer(
            0, 0, GLint(width), GLint(height),
            0, 0, GLint(width), GLint(height),
            GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_LINEAR)
        )
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)

        // Required after rendering into an IOSurface-backed texture and
        // before any non-GL consumer (here, AVSampleBufferDisplayLayer)
        // reads it — without this, glBlitFramebuffer's writes are not
        // guaranteed visible outside the GL command stream yet.
        glFlush()

        return makeSampleBuffer(from: pixelBuffer)
    }

    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else { return nil }

        frameCount += 1
        // 600 timescale (matches common video timescales like 29.97/59.94
        // fps without rounding error) — the actual numeric value doesn't
        // need to match mpv's own clock, only needs to keep increasing,
        // since PiP's sample buffer timeline is independent of mpv's
        // internal `time-pos` (see `frameCount`'s doc comment above).
        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: frameCount, timescale: 600),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr else { return nil }
        return sampleBuffer
    }

    /// Call when the EAGLContext/render pipeline is being torn down
    /// (mirrors `MPVGLView.teardown()`), so the texture cache releases
    /// its GL objects while the context that created them is still
    /// current — the same ordering constraint `MPVGLView.teardown()`
    /// already documents for its own GL objects.
    public func tearDown() {
        currentTexture = nil
        if let textureCache {
            CVOpenGLESTextureCacheFlush(textureCache, 0)
        }
        textureCache = nil
        pixelBufferPool = nil
        if blitFBO != 0 {
            glDeleteFramebuffers(1, &blitFBO)
            blitFBO = 0
        }
    }
}
