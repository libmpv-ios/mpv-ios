import Foundation

/// Baseline mpv options applied before `initialize()`, equivalent to the
/// block of `MPVLib.setOptionString(...)` calls mpv-android's
/// MainActivity/BaseMPVActivity runs after `create()` and before `init()`
/// (see mpv-android's `initOptions()` in MPVView.kt).
public struct MPVConfiguration {
    /// Hardware decoding mode. On iOS this selects mpv's VideoToolbox
    /// hwdec interop (implemented for the OpenGL ES render path in mpv's
    /// video/out/hwdec/hwdec_ios_gl.m via CVOpenGLESTextureCache), which
    /// gives zero-copy decode-to-texture. "no" disables hw decode entirely;
    /// "auto" lets mpv choose.
    public var hwdec: String = "videotoolbox"

    /// GPU-next is mpv's modern rendering pipeline (libplacebo-backed).
    /// Recommended on Apple platforms since it has first-class Metal support.
    public var useGpuNext: Bool = true

    /// Cache settings, analogous to mpv-android's network-caching defaults
    /// for smoother playback over HTTP/HLS sources.
    public var cacheSeconds: Int = 30

    /// Path mpv should use for its config/watch-later/scripts directory.
    /// Equivalent to mpv-android pointing MPV_HOME at the app's files dir.
    public var mpvConfigDirectory: URL?

    /// Screenshot output directory.
    public var screenshotDirectory: URL?

    public init() {}

    /// Applies this configuration to a freshly-created (but not yet
    /// initialized) MPVCore instance. Must be called after `create()` and
    /// before `initialize()`, matching mpv-android's ordering constraint
    /// (mpv only accepts `set_option_string` pre-init for some options).
    public func apply(to core: MPVCore) {
        // IMPORTANT: mpv's public render API (include/mpv/render.h) only
        // defines two backends: MPV_RENDER_API_TYPE_OPENGL and the software
        // (CPU) renderer. There is no Metal render-API type in libmpv.
        // On macOS, mpv drives Metal internally via Vulkan+MoltenVK through
        // its own AppKit-dependent VO window path (video/out/vulkan/context_mac.m),
        // which requires NSApplication and is not usable on iOS.
        // The correct, actually-supported iOS path — and the one mpv's own
        // upstream iOS support targets (see video/out/hwdec/hwdec_ios_gl.m,
        // gated by the `ios-gl` meson feature) — is OpenGL ES via EAGL:
        // mpv_render_context_create() with MPV_RENDER_API_TYPE_OPENGL,
        // rendering into an FBO backed by a CAEAGLLayer-based view
        // (see MPVGLView). "vo=libmpv" here just tells mpv to hand frames
        // to whoever created the render context, instead of opening its
        // own window — same meaning on every platform/backend.
        core.setOptionString("vo", "libmpv")
        core.setOptionString("hwdec", hwdec)
        core.setOptionString("gpu-api", "opengl")
        core.setOptionString("opengl-es", "yes")

        if useGpuNext {
            core.setOptionString("vd-lavc-dr", "yes")
            core.setOptionString("gpu-context", "libmpv")
        }

        core.setOptionString("cache", "yes")
        core.setOptionString("demuxer-max-bytes", "\(cacheSeconds * 1_000_000)")
        core.setOptionString("demuxer-readahead-secs", "\(cacheSeconds)")

        if let dir = mpvConfigDirectory {
            core.setOptionString("config-dir", dir.path)
            core.setOptionString("config", "yes")
        }
        if let dir = screenshotDirectory {
            core.setOptionString("screenshot-directory", dir.path)
        }

        // Subtitle rendering defaults matching mpv-android's baseline
        // (ASS-styled subs, embedded fonts allowed).
        core.setOptionString("sub-auto", "fuzzy")
        core.setOptionString("embeddedfonts", "yes")

        // iOS-specific: keep the audio session alive appropriately;
        // actual AVAudioSession category/activation is handled at the app
        // layer (see MPVPlayerViewController), mpv only needs to know not
        // to fight over exclusive audio hardware access.
        core.setOptionString("audio-exclusive", "no")
    }
}
