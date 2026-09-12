import Foundation
import MediaPlayer
import AVFoundation

/// Owns Control Center / lock-screen "Now Playing" integration and the
/// audio-session lifecycle events that affect playback (interruptions,
/// route changes). Equivalent responsibility to mpv-android's
/// `initMediaSession()` (PlayerActivity.kt), which sets up a
/// `MediaSessionCompat` + `PlaybackStateCompat` and registers an
/// `AudioManager.OnAudioFocusChangeListener` — the iOS analogues are
/// `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` for the session, and
/// `AVAudioSession` notifications for focus/interruption handling.
///
/// Deliberately a separate type from `PlayerViewModel` (mirroring
/// mpv-android keeping media-session setup as its own method rather than
/// folding it into transport-control logic) — this only translates
/// between "the system wants X" and "tell the view model to do X", and
/// separately mirrors view-model state back out to the system. It knows
/// nothing about mpv itself.
@MainActor
public final class MediaSessionManager {
    public struct Metadata {
        public var title: String
        public var artworkImage: UIImage?

        public init(title: String, artworkImage: UIImage? = nil) {
            self.title = title
            self.artworkImage = artworkImage
        }
    }

    /// Actions the manager asks its owner to perform in response to a
    /// remote command or an audio-session event it cannot itself carry
    /// out (this type has no reference to MPVCore/PlayerViewModel by
    /// design, so it can't call playback methods directly — matching
    /// mpv-android's own AudioManager focus-change listener, which also
    /// only signals PlayerActivity rather than touching MPVLib itself).
    public enum Action {
        case play
        case pause
        case togglePlayPause
        case seek(to: Double)
        case skip(bySeconds: Double)
        case nextTrack
        case previousTrack
    }

    public var onAction: ((Action) -> Void)?

    private var isRegistered = false
    private var currentDuration: Double = 0
    /// Tokens from the block-based NotificationCenter API, needed to
    /// remove these specific observers in `stop()`. Using
    /// `addObserver(forName:object:queue:using:)` here (not
    /// `addObserver(_:selector:name:object:)`) deliberately: the
    /// selector-based API requires `@objc`-exposed methods, which in
    /// turn requires this type to inherit from NSObject — this class
    /// intentionally does not (matching `PictureInPictureCoordinator`
    /// and every other plain-Swift coordinator type in this codebase),
    /// so the block-based API is the one that actually compiles here.
    private var interruptionObserverToken: NSObjectProtocol?
    private var routeChangeObserverToken: NSObjectProtocol?

    public init() {}

    deinit {
        // MPRemoteCommandCenter targets and NotificationCenter observers
        // are process-wide state, not owned per-instance the way
        // mpv-android's per-Activity MediaSessionCompat is — if this
        // manager is ever deallocated without an explicit `stop()` first
        // (e.g. an early-return during setup), leaving stale targets
        // registered would let a *different*, unrelated player instance
        // keep receiving this one's lock-screen commands. `stop()` isn't
        // called automatically here because it hops onto the main actor,
        // and `deinit` cannot `await` — callers are expected to call
        // `stop()` themselves before releasing this object (PlayerViewModel
        // does so from its own `stop()`), same as mpv-android's
        // onDestroy() explicitly abandoning its audio focus request
        // rather than relying on GC.
    }

    // MARK: - Lifecycle

    /// Registers remote-command handlers and starts observing
    /// interruption/route-change notifications. Call once playback
    /// begins (matches mpv-android calling `initMediaSession()` from
    /// `PlayerActivity.onCreate()`).
    public func start() {
        guard !isRegistered else { return }
        isRegistered = true

        configureRemoteCommands()

        interruptionObserverToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            // MainActor.assumeIsolated (not a bare call): `queue: .main`
            // guarantees this closure runs on the main thread at
            // runtime, but the closure's *static* isolation is still
            // nonisolated as far as the type system is concerned —
            // confirmed this produces a real Swift concurrency warning
            // even though it's provably safe at runtime (queue: .main
            // was specified), rather than assuming queue: .main alone
            // would satisfy the compiler. assumeIsolated documents
            // itself as exactly this escape hatch: asserting at runtime
            // what queue:.main already guarantees, without needing every
            // call site to become async.
            MainActor.assumeIsolated {
                self?.handleInterruption(notification)
            }
        }
        routeChangeObserverToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleRouteChange(notification)
            }
        }
    }

    /// Unregisters everything this manager registered. Must be called
    /// before the owning player is torn down — see the `deinit` note
    /// above for why this isn't automatic.
    public func stop() {
        guard isRegistered else { return }
        isRegistered = false

        removeRemoteCommandTargets()
        if let token = interruptionObserverToken {
            NotificationCenter.default.removeObserver(token)
            interruptionObserverToken = nil
        }
        if let token = routeChangeObserverToken {
            NotificationCenter.default.removeObserver(token)
            routeChangeObserverToken = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Now Playing info (mirrors mpv-android's PlaybackStateCompat updates)

    /// Call whenever the media identity changes (new file loaded).
    /// Equivalent to mpv-android setting `MediaMetadataCompat` on a new
    /// `MPVLib.mediaTitle`/track change.
    public func updateMetadata(_ metadata: Metadata) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = metadata.title
        // MPNowPlayingInfoPropertyMediaType (this key, paired with the
        // MPNowPlayingInfoMediaType enum) is deliberately used here, not
        // the similarly-named MPMediaItemPropertyMediaType (a different
        // key expecting the unrelated MPMediaType enum) — mixing the two
        // is a real, previously-shipped mistake (confirmed via IINA's own
        // GitHub issue tracker for this exact confusion), not just a
        // hypothetical typo risk.
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        if let image = metadata.artworkImage {
            // Known instability: Apple's own DTS engineers have
            // acknowledged (as of this writing, unresolved) crash
            // reports under Swift 6 strict concurrency specifically for
            // this exact shape — an MPMediaItemArtwork requestHandler
            // closure capturing and returning an external UIImage
            // value. This project currently builds with SWIFT_VERSION
            // 5.9 (see project.yml), so it isn't hit today, but if this
            // target is ever moved to Swift 6 language mode, re-check
            // Apple's developer forums for a resolution before assuming
            // this still works as written.
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            info[MPMediaItemPropertyArtwork] = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Call on every play/pause/seek and periodically (a few times a
    /// minute is plenty — see the elapsed-time note below) while
    /// playing. Equivalent to mpv-android refreshing
    /// `PlaybackStateCompat.Builder().setState(...)`.
    ///
    /// Deliberately does NOT need to be called on every single
    /// `time-pos` property tick: `MPNowPlayingInfoPropertyElapsedPlaybackTime`
    /// combined with `MPNowPlayingInfoPropertyPlaybackRate` lets the
    /// system interpolate the displayed position between updates on its
    /// own (confirmed current behavior per Apple's own developer forum
    /// guidance on this property) — calling this on every mpv time-pos
    /// tick would work but wastes battery for no visible benefit.
    public func updatePlaybackState(position: Double, duration: Double, isPaused: Bool) {
        currentDuration = duration
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPaused ? 0.0 : 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote commands (mirrors mpv-android's MediaSessionCompat.Callback)
    //
    // Every addTarget closure below wraps its body in
    // MainActor.assumeIsolated { }, for the same reason as the
    // NotificationCenter observers in `start()`: MPRemoteCommand's
    // addTarget(handler:) documents no `queue:` parameter and no
    // isolation guarantee of its own, but in practice (confirmed via a
    // matching Apple Developer Forums report of this exact "@MainActor
    // view-model + addTarget" combination failing to compile without
    // this) these callbacks fire on the main thread — Control
    // Center/lock-screen commands are UI-originated events, consistent
    // with every other AppKit/UIKit-adjacent callback being main-thread.
    // Without this wrapper, referencing `self` (a @MainActor-isolated
    // instance) from these nonisolated closures does not compile.
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onAction?(.play)
                return .success
            }
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onAction?(.pause)
                return .success
            }
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onAction?(.togglePlayPause)
                return .success
            }
        }

        // 10-second skip, matching mpv-ios-player's existing UI buttons
        // (MPVPlayerView's gobackward.10/goforward.10 controls) and
        // mpv-android's default seek-button interval, so lock-screen
        // skip behavior matches in-app skip behavior.
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onAction?(.skip(bySeconds: 10))
                return .success
            }
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onAction?(.skip(bySeconds: -10))
                return .success
            }
        }

        // Lets the user drag the scrubber in Control Center / on the
        // lock screen directly, equivalent to mpv-android's
        // `onSeekTo(pos)` MediaSessionCompat.Callback override.
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            MainActor.assumeIsolated {
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                self?.onAction?(.seek(to: event.positionTime))
                return .success
            }
        }

        // Disabled at setup time and toggled on/off by
        // `setPlaylistNavigationEnabled(_:)` as the playlist goes from
        // empty to non-empty and back — a single-file player with no
        // playlist has nothing meaningful for these to do, and leaving
        // them enabled-but-nonfunctional would show dead next/previous
        // buttons in Control Center (mpv-android faces the same choice:
        // PlaylistDialog-driven next/previous only get wired up once a
        // playlist exists).
        center.nextTrackCommand.isEnabled = false
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onAction?(.nextTrack)
                return .success
            }
        }
        center.previousTrackCommand.isEnabled = false
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onAction?(.previousTrack)
                return .success
            }
        }
    }

    /// Call whenever the playlist goes from empty to non-empty (or vice
    /// versa) — e.g. from PlayerViewModel's own playlist-changed
    /// handling — to show or hide Control Center's next/previous buttons
    /// accordingly.
    public func setPlaylistNavigationEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = enabled
        center.previousTrackCommand.isEnabled = enabled
    }

    private func removeRemoteCommandTargets() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
    }

    // MARK: - Interruptions & route changes (mirrors mpv-android's AudioManager focus listener)

    /// Reports transient state so the owner can pause/resume, matching
    /// mpv-android's `AUDIOFOCUS_LOSS_TRANSIENT` /
    /// `AUDIOFOCUS_GAIN` handling in its focus-change listener.
    public var onInterruptionBegan: (() -> Void)?
    public var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?
    /// Fired when the active output device disappears (e.g. headphones
    /// unplugged, Bluetooth speaker out of range). Per Apple's Human
    /// Interface Guidelines for audio route changes, apps should pause
    /// on this — continuing playback out loud on the built-in speaker
    /// after headphones are removed is treated as a privacy violation of
    /// the user's implicit expectation, not merely a UX nicety. Does NOT
    /// fire (and playback should NOT pause) for `.newDeviceAvailable`
    /// (headphones plugged in) — matching Apple's own documented
    /// `AVPlayer` behavior for the same route-change reason.
    public var onOutputDeviceUnavailable: (() -> Void)?

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            onInterruptionEnded?(options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        if reason == .oldDeviceUnavailable {
            onOutputDeviceUnavailable?()
        }
        // .newDeviceAvailable and all other reasons are intentionally
        // left as no-ops here (see onOutputDeviceUnavailable's doc
        // comment for why plugging in is not treated the same as
        // unplugging).
    }
}
