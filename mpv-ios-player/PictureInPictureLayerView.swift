import SwiftUI
import AVFoundation

/// Hosts `PictureInPictureCoordinator.displayLayer` at a real, non-zero
/// size. Confirmed against a documented Apple Developer Forums report
/// (thread 37210) that `AVSampleBufferDisplayLayer` renders nothing —
/// and by extension cannot support Picture in Picture — while its frame
/// is zero-sized or it isn't in any view's layer hierarchy at all, even
/// though the layer itself is never meant to be the visible on-screen
/// video during normal (non-PiP) playback (`MPVGLView` is).
///
/// `opacity(0)` (not `.hidden` / zero frame) is used to keep this layer
/// invisible during normal playback without ever letting its frame drop
/// to zero or being removed from the hierarchy — both of which would
/// silently break PiP the next time it's requested.
struct PictureInPictureLayerView: UIViewRepresentable {
    let coordinator: PictureInPictureCoordinator

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.addSublayer(coordinator.displayLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        coordinator.displayLayer.frame = uiView.bounds
    }
}
