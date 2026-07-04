import SwiftUI
import MPVKit

/// SwiftUI bridge for MPVGLView. Equivalent in role to how mpv-android's
/// PlayerActivity.kt embeds a raw MPVView (a GLSurfaceView subclass) inside
/// its Activity layout — here the "layout" is a SwiftUI view tree instead
/// of an XML layout + findViewById.
struct MPVVideoView: UIViewRepresentable {
    let core: MPVCore

    func makeUIView(context: Context) -> MPVGLView {
        guard let view = MPVGLView(core: core) else {
            fatalError("MPVGLView failed to create an EAGLContext (OpenGLES3 unavailable on this device)")
        }
        view.backgroundColor = .black
        do {
            try view.attachRenderContext()
        } catch {
            // Surfaced as a delegate event in production rather than a
            // hard crash — PlayerViewModel observes MPVCoreDelegate and
            // will show an error state if render context creation fails.
            print("MPVVideoView: attachRenderContext failed: \(error)")
        }
        return view
    }

    func updateUIView(_ uiView: MPVGLView, context: Context) {
        // No-op: mpv drives redraws itself via the render update callback.
        // SwiftUI state changes that affect video (e.g. aspect ratio mode)
        // go through mpv properties/commands on `core`, not through view
        // updates here.
    }

    static func dismantleUIView(_ uiView: MPVGLView, coordinator: ()) {
        uiView.teardown()
    }
}
