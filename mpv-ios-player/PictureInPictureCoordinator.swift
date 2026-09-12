import Foundation
import AVKit
import AVFoundation
import MPVKit

/// Owns the `AVSampleBufferDisplayLayer` / `AVPictureInPictureController`
/// pair that lets this custom-rendered (non-`AVPlayer`) player use system
/// Picture in Picture. Equivalent responsibility to mpv-android's PiP
/// handling (`enterPictureInPictureMode` + a `PictureInPictureParams`
/// builder in `MPVActivity.kt`), adapted to iOS's very different model:
/// Android's PiP is "shrink the existing Activity window," iOS's
/// non-`AVPlayer` PiP is "hand the system a live video frame feed and a
/// playback-control delegate."
///
/// Deliberately a separate type from `PlayerViewModel`, mirroring
/// `MediaSessionManager`'s own separation rationale — this only
/// translates between "the system's PiP UI wants X" and "tell the view
/// model to do X", and separately forwards frames from `MPVGLView`. It
/// has no direct mpv dependency beyond the frame callback wiring done in
/// `configure(with:)`.
@MainActor
public final class PictureInPictureCoordinator: NSObject {
    public let displayLayer = AVSampleBufferDisplayLayer()

    private var pipController: AVPictureInPictureController?

    /// Actions the coordinator asks its owner to perform in response to
    /// PiP's own on-screen transport controls. No direct reference to
    /// MPVCore/PlayerViewModel here, same reasoning as
    /// MediaSessionManager.Action.
    public enum Action {
        case setPlaying(Bool)
        case skip(bySeconds: Double)
    }

    public var onAction: ((Action) -> Void)?

    /// Called when the user taps the PiP button or the system starts PiP
    /// automatically (see `canStartPictureInPictureAutomaticallyFromInline`
    /// below). The owner is expected to hide its own video surface (or
    /// leave it — see the SwiftUI wiring note in `MPVPlayerView`) while
    /// this is true.
    public var onActiveChange: ((Bool) -> Void)?

    /// Current playback snapshot the PiP UI queries on demand
    /// (`pictureInPictureControllerIsPlaybackPaused` etc.) — the
    /// coordinator has no other way to know this, since it isn't the
    /// source of truth for playback state (PlayerViewModel is).
    /// Set this from PlayerViewModel whenever `isPaused`/`duration`
    /// change, mirroring how MediaSessionManager.updatePlaybackState is
    /// driven from the same property-change hooks.
    public var isPaused: Bool = true
    public var duration: Double = 0

    public override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
    }

    /// Wires this coordinator to a live `MPVGLView`, and starts that
    /// view producing PiP frames. Call once the video surface exists
    /// (mirrors `MPVVideoView.makeUIView`'s `attachRenderContext()` call
    /// timing — PiP frames can only start once there's a render context
    /// to blit from).
    public func configure(with videoView: MPVGLView) {
        videoView.onPictureInPictureFrame = { [weak self] sampleBuffer in
            guard let self else { return }
            // AVSampleBufferDisplayLayer.enqueue(_:) is documented-safe
            // to call from a background thread going back to WWDC 2014's
            // guidance on this API (the `requestMediaDataWhenReadyOnQueue`
            // pattern runs enqueue calls on a caller-provided background
            // queue) — no main-thread hop needed here, and adding one
            // would cost an extra thread transition on every single video
            // frame for no correctness benefit. This closure itself runs
            // on MPVGLView's own render queue (see that type's
            // `onPictureInPictureFrame` doc comment), not the main actor,
            // despite `PictureInPictureCoordinator` itself being
            // `@MainActor` — `displayLayer` is safe to touch this way per
            // the above, and `pipController`/`onAction`/`onActiveChange`
            // are never touched from this closure.
            self.displayLayer.enqueue(sampleBuffer)
        }
        videoView.enablePictureInPicture()
    }

    /// Stops PiP frame production. Call from the same place the owner
    /// tears down its video view (mirrors `MPVGLView.teardown()`'s own
    /// call site in `MPVVideoView.dismantleUIView`).
    public func stopProducingFrames(for videoView: MPVGLView) {
        videoView.onPictureInPictureFrame = nil
        videoView.disablePictureInPicture()
    }

    /// Creates the actual `AVPictureInPictureController`. Must be called
    /// after `displayLayer` has a non-zero frame (mirrors
    /// `AVPlayerLayer.isReadyForDisplay` being required for the
    /// player-layer PiP path) — in practice, called once the first PiP
    /// frame has been enqueued, since that's this player's own signal
    /// that there's real content to show.
    public func setUpControllerIfNeeded() {
        guard pipController == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        // Lets the system start PiP automatically when the app is
        // backgrounded while this player is on screen, matching
        // mpv-android's own "auto-enter PiP on home/recents" behavior
        // rather than requiring an explicit PiP button tap every time.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        // false (not true): true is documented for content where
        // scrubbing/seeking doesn't make sense (e.g. a live camera feed —
        // see Apple's own PiP camera-feed sample, which sets this true
        // specifically to hide transport controls that would be
        // meaningless there). This is a general-purpose video file
        // player with real seek/skip support, so PiP should keep its
        // normal transport controls.
        controller.requiresLinearPlayback = false
        pipController = controller
    }

    public func startPictureInPicture() {
        pipController?.startPictureInPicture()
    }

    public func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }

    public var isPictureInPictureActive: Bool {
        pipController?.isPictureInPictureActive ?? false
    }
}

// MARK: - AVPictureInPictureControllerDelegate
//
// Unlike MediaSessionManager's addTarget/NotificationCenter closures
// (which needed explicit MainActor.assumeIsolated wrapping — see that
// file's own notes), these delegate methods reference `self` directly
// with no such wrapper. This relies on Apple's AVKit delegate protocols
// being annotated (e.g. @preconcurrency, or MainActor-safe by their own
// declaration) such that a @MainActor-isolated conforming type's
// synchronous protocol witnesses are accepted without extra ceremony —
// consistent with how @MainActor classes conforming to same-module
// protocols infer MainActor conformance automatically, extended here to
// system-framework protocols that predate Swift concurrency. This
// couldn't be confirmed by actually compiling this project (no
// Mac/Xcode toolchain available in this environment) — if a real build
// reports an actor-isolation error on any method in this extension or
// the next one, wrapping the body in `MainActor.assumeIsolated { }`
// (the same fix already applied in MediaSessionManager) is the
// straightforward resolution.
extension PictureInPictureCoordinator: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        onActiveChange?(true)
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        onActiveChange?(false)
    }

    public func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        // No user-facing error surface here by design — matches
        // MediaSessionManager's own "best-effort, not load-bearing"
        // treatment of most system-integration failures. A failed PiP
        // start just means the button/gesture had no visible effect,
        // which is self-evident to the user without an extra alert.
        onActiveChange?(false)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PictureInPictureCoordinator: AVPictureInPictureSampleBufferPlaybackDelegate {
    public func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        onAction?(.setPlaying(playing))
    }

    public func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
        guard duration.isFinite, duration > 0 else {
            // Matches the "live content" case from Apple's own reference
            // pattern for this delegate method — an unknown/zero duration
            // (e.g. before the file has finished loading) is presented
            // to PiP as an unbounded range rather than a zero-length one,
            // so the PiP scrubber doesn't briefly show a collapsed
            // timeline during load.
            return CMTimeRange(start: .zero, duration: .positiveInfinity)
        }
        return CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    public func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        isPaused
    }

    public func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        // No action needed: MPVGLView's blit target size is driven by
        // its own screen drawable size (see PictureInPictureRenderer's
        // `ensurePool`), not by the PiP window's rendered size — the
        // system scales the enqueued frames to fit the PiP window itself.
    }

    public func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        onAction?(.skip(bySeconds: CMTimeGetSeconds(skipInterval)))
        completionHandler()
    }

    public func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ controller: AVPictureInPictureController
    ) -> Bool {
        // false: this player already supports background audio (see
        // Info.plist's UIBackgroundModes: audio, and
        // MediaSessionManager's interruption handling) independent of
        // PiP — PiP being active should not additionally silence
        // playback once PiP itself is dismissed/backgrounded further.
        false
    }
}
