import Foundation
import Combine
import MPVKit
import AVFoundation
import UIKit

/// Playback state exposed to the UI. Mirrors the assorted boolean/enum
/// fields mpv-android's PlayerActivity.kt tracks (paused, sliding, track
/// lists, buffering, etc.), consolidated into one observable object.
@MainActor
public final class PlayerViewModel: ObservableObject {
    public let core = MPVCore()

    @Published public private(set) var isPaused: Bool = true
    @Published public private(set) var position: Double = 0
    @Published public private(set) var duration: Double = 0
    @Published public private(set) var isSeeking: Bool = false
    @Published public private(set) var isBuffering: Bool = false
    @Published public private(set) var volume: Double = 100
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var speed: Double = 1.0
    @Published public private(set) var tracks: [MPVTrack] = []
    @Published public private(set) var playlist: [MPVPlaylistItem] = []
    @Published public private(set) var mediaTitle: String = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isFileLoaded: Bool = false
    @Published public private(set) var isIdle: Bool = true
    @Published public private(set) var currentDecoder: String = "no"
    private var lastVideoWidth: Int64?
    private var lastVideoHeight: Int64?

    /// User-driven scrub position, separate from `position`, so the seek
    /// bar doesn't fight the user's finger while dragging (equivalent to
    /// mpv-android's PlayerActivity `userIsOperatingSeekbar` guard).
    @Published public var scrubPosition: Double = 0

    private var isInitialized = false

    /// Owns Control Center / lock-screen integration. See
    /// MediaSessionManager.swift for why this is a separate type rather
    /// than folded into this view model directly.
    private let mediaSession = MediaSessionManager()

    /// Owns Picture in Picture. Public (unlike `mediaSession`) because
    /// `MPVPlayerView` needs direct access to `pipCoordinator.displayLayer`
    /// to host it in the view hierarchy, and to call
    /// `configure(with:)`/`stopProducingFrames(for:)` at the right points
    /// in the video view's own lifecycle — see PictureInPictureCoordinator.swift.
    public let pipCoordinator = PictureInPictureCoordinator()

    /// Tracks whether playback was paused by an audio interruption
    /// (phone call, Siri, another app's audio) that this view model
    /// should undo when the interruption ends — as opposed to a pause
    /// the user made deliberately, which an interruption ending should
    /// NOT override. Mirrors mpv-android's own distinction between a
    /// focus-loss-triggered pause and a user-initiated pause (its
    /// `AudioFocusChangeListener` only resumes on `AUDIOFOCUS_GAIN` if
    /// it was the one that paused for `AUDIOFOCUS_LOSS_TRANSIENT` in the
    /// first place).
    private var pausedByInterruption = false

    public init() {}

    // MARK: - Lifecycle

    /// Equivalent to mpv-android's PlayerActivity.onCreate() mpv setup
    /// block: create, configure, initialize, then observe the properties
    /// the UI cares about.
    public func start(configuration: MPVConfiguration = .init()) {
        guard !isInitialized else { return }
        isInitialized = true

        do {
            try configureAudioSession()

            try core.create()
            configuration.apply(to: core)
            core.delegate = self
            try core.initialize()

            observeCoreProperties()
            configureMediaSession()
            observeAppLifecycleForWatchLater()
        } catch {
            errorMessage = "Failed to start playback engine: \(error)"
        }
    }

    /// Equivalent to mpv-android's PlayerActivity.onDestroy() mpv teardown.
    /// The video view's dismantleUIView calls MPVGLView.teardown()
    /// separately and must happen before this, per render.h's
    /// ordering requirement (render context freed before core destroy).
    public func stop() {
        saveWatchLaterPosition()
        if let token = willResignActiveObserverToken {
            NotificationCenter.default.removeObserver(token)
            willResignActiveObserverToken = nil
        }
        mediaSession.stop()
        core.destroy()
        isInitialized = false
    }

    // MARK: - Playback position persistence ("watch later")

    /// Writes mpv's own resume file for the current file, unless it's
    /// already finished playing — see `MPVCore.writeWatchLaterConfig()`'s
    /// doc comment for why EOF is excluded.
    public func saveWatchLaterPosition() {
        core.writeWatchLaterConfig()
    }

    private var willResignActiveObserverToken: NSObjectProtocol?

    /// Observed from both explicit teardown (`stop()`, above) and from
    /// the app being backgrounded, since neither alone is guaranteed to
    /// fire in every path a user can leave this screen: swiping the app
    /// away or the system suspending it while this view is still on
    /// screen would background the app without necessarily tearing down
    /// this SwiftUI view (and therefore without calling `stop()`) first.
    /// `willResignActiveNotification` (fires slightly earlier than
    /// `didEnterBackgroundNotification`) is used specifically to
    /// maximize the time available before iOS may suspend the app —
    /// mpv's `write-watch-later-config` is a synchronous local file
    /// write (not a network call), so it doesn't need the
    /// `beginBackgroundTask` machinery a longer-running save might
    /// require, but starting it as early as possible in the
    /// backgrounding sequence is still safer than waiting.
    ///
    /// Uses the block-based `addObserver(forName:object:queue:using:)`
    /// API, not `addObserver(_:selector:name:object:)`: the
    /// selector-based form requires `@objc`-exposed methods, which in
    /// turn requires this class to inherit from NSObject —
    /// `PlayerViewModel` (an `ObservableObject`, not an `NSObject`
    /// subclass) intentionally does not, matching every other
    /// coordinator type in this codebase (see `MediaSessionManager`'s
    /// matching note, which hit and fixed this same issue first).
    private func observeAppLifecycleForWatchLater() {
        willResignActiveObserverToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // MainActor.assumeIsolated: queue: .main guarantees this
            // runs on the main thread at runtime, but the closure's
            // static isolation is still nonisolated to the type system —
            // same reasoning as MediaSessionManager's matching
            // NotificationCenter observers.
            MainActor.assumeIsolated {
                self?.saveWatchLaterPosition()
            }
        }
    }

    /// Wires MediaSessionManager's action/interruption callbacks to this
    /// view model's own transport methods, then starts it. Kept as its
    /// own method (rather than inlined into `start()`) so the mapping
    /// from MediaSessionManager.Action to PlayerViewModel methods is easy
    /// to scan as its own unit — mirrors mpv-android keeping
    /// `initMediaSession()` as a distinct method from the rest of
    /// `onCreate()`.
    private func configureMediaSession() {
        mediaSession.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .play: self.core.isPaused = false
            case .pause: self.core.isPaused = true
            case .togglePlayPause: self.togglePause()
            case .seek(let position): self.seek(to: position)
            case .skip(let seconds): self.seek(to: self.position + seconds)
            case .nextTrack: self.playlistNext()
            case .previousTrack: self.playlistPrev()
            }
        }
        mediaSession.onInterruptionBegan = { [weak self] in
            guard let self, !self.isPaused else { return }
            self.pausedByInterruption = true
            self.core.isPaused = true
        }
        mediaSession.onInterruptionEnded = { [weak self] shouldResume in
            guard let self, self.pausedByInterruption else { return }
            self.pausedByInterruption = false
            if shouldResume {
                self.core.isPaused = false
            }
        }
        mediaSession.onOutputDeviceUnavailable = { [weak self] in
            self?.core.isPaused = true
        }
        mediaSession.start()

        pipCoordinator.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .setPlaying(let playing): self.core.isPaused = !playing
            case .skip(let seconds): self.seek(to: self.position + seconds)
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [])
        try session.setActive(true)
    }

    private func observeCoreProperties() {
        core.observeProperty("pause", format: .flag)
        core.observeProperty("time-pos", format: .double)
        core.observeProperty("duration", format: .double)
        core.observeProperty("volume", format: .double)
        core.observeProperty("mute", format: .flag)
        core.observeProperty("speed", format: .double)
        core.observeProperty("media-title", format: .string)
        core.observeProperty("core-idle", format: .flag)
        core.observeProperty("paused-for-cache", format: .flag)
        core.observeProperty("track-list", format: .string)
        // Both observed, not just one: mpv issue #3267 documents that
        // "playlist-count" property-change notifications were
        // historically unreliable on append/remove (fixed upstream since,
        // per that issue's own follow-up, but this project tracks mpv's
        // master branch rather than a version where that's guaranteed),
        // while "playlist-pos" reliably notifies on most playlist
        // mutations per the same report. Observing both, and refreshing
        // the full list on either firing (see applyProperty's
        // "playlist-count"/"playlist-pos" cases), is cheap insurance
        // against relying on the one property with a documented history
        // of dropped notifications.
        //
        // This still isn't complete on its own: mpv issue #7339
        // (unresolved as of this writing) documents that
        // `playlist-move` specifically fires no MPV_EVENT_PROPERTY_CHANGE
        // for *either* property. `playlistMove(from:to:)`'s call site in
        // this file therefore triggers an explicit `refreshPlaylist()`
        // itself immediately after the command, rather than trusting the
        // observer to catch it — the same "don't rely solely on the
        // event, also refresh explicitly after a mutating command"
        // pattern already used for gesture-driven seeks elsewhere in
        // this file.
        core.observeProperty("playlist-count", format: .int64)
        core.observeProperty("playlist-pos", format: .int64)
        // Mirrors mpv-android's own reason for observing this
        // ("hwdec-current" -> updateDecoderButton() in MPVActivity.kt):
        // the actually-active decoder can differ from whatever was last
        // requested via setDecoder (e.g. silent software fallback for an
        // unsupported codec — see MPVCore.currentDecoder's doc comment),
        // so the UI needs to reflect what mpv is actually doing, not
        // just echo back the last user selection.
        core.observeProperty("hwdec-current", format: .string)
        // video-params/w and /h (NOT the parent video-params node — see
        // MPVCore.currentStats()'s doc comment on why the parent NODE
        // property can't be observed directly in this codebase) drive
        // OrientationLockController's auto-rotation-by-aspect-ratio
        // mode, mirroring mpv-android's updateOrientation() being called
        // from its own video-reconfig handling whenever these dimensions
        // change.
        core.observeProperty("video-params/w", format: .int64)
        core.observeProperty("video-params/h", format: .int64)
    }

    // MARK: - Playback controls (thin forwards to MPVCore, kept here so
    // the SwiftUI view layer never touches MPVCore directly — same
    // separation mpv-android keeps between PlayerActivity and MPVView)

    public func loadFile(_ path: String) {
        errorMessage = nil
        core.loadFile(path)
        // A fresh loadFile (replace mode, the default) resets the
        // playlist to a single entry — refreshed explicitly here rather
        // than waiting on the property observer, since the observer's
        // first firing for a brand new file can lag slightly behind this
        // call returning (same reasoning as the explicit refresh after
        // `playlistMove`, below).
        refreshPlaylist()
    }

    // MARK: - Playlist
    //
    // Thin forwards to MPVCore's playlist API, kept here for the same
    // reason as the transport controls above — the view layer only ever
    // talks to PlayerViewModel, never MPVCore directly.

    /// Appends a file to the playlist without interrupting current
    /// playback. Equivalent to mpv-android's PlaylistDialog "add" action.
    public func addToPlaylist(_ path: String) {
        core.loadFile(path, mode: .append)
        refreshPlaylist()
    }

    public func playlistNext() {
        core.playlistNext()
    }

    public func playlistPrev() {
        core.playlistPrev()
    }

    public func playPlaylistItem(at index: Int) {
        core.playlistPlay(index: index)
    }

    public func removeFromPlaylist(at index: Int) {
        core.playlistRemove(at: index)
        refreshPlaylist()
    }

    /// See MPVCore.playlistMove's own doc comment for the exact index
    /// semantics before wiring this to a drag-to-reorder gesture.
    public func movePlaylistItem(from fromIndex: Int, to toIndex: Int) {
        core.playlistMove(from: fromIndex, to: toIndex)
        // Explicit refresh: mpv issue #7339 (open as of this writing)
        // documents that playlist-move fires no property-change
        // notification for playlist-count OR playlist-pos, unlike every
        // other playlist-mutating command this view model wraps — so
        // this is the one call site where skipping the explicit refresh
        // would leave `playlist` silently stale.
        refreshPlaylist()
    }

    public func clearPlaylist() {
        core.playlistClear()
        refreshPlaylist()
    }

    public func shufflePlaylist() {
        core.playlistShuffle()
        refreshPlaylist()
    }

    // MARK: - Subtitle style
    //
    // Deliberately NOT plain computed properties forwarding straight to
    // `core` with no SwiftUI change notification: a Slider/ColorPicker
    // bound to a plain `get { core.x } set { core.x = $0 }` computed var
    // has no way to tell SwiftUI a redraw is needed on write, since
    // `PlayerViewModel` itself doesn't change identity when only
    // `core`'s underlying mpv property changes — @Published only
    // triggers on assignment to the wrapped property itself, and mpv's
    // own property-change events for these specific properties are
    // never observed elsewhere in this file (unlike time-pos/duration/
    // etc.), so nothing else would trigger a re-render either. Each
    // setter here explicitly calls `objectWillChange.send()` before
    // writing through to `core`, matching Combine's documented
    // "call send() before the change" contract for cases exactly like
    // this one — a property whose true storage lives outside any
    // @Published wrapper this object owns.
    public var subtitleDelay: Double {
        get { core.subtitleDelay }
        set {
            objectWillChange.send()
            core.subtitleDelay = newValue
        }
    }

    public var subtitleScale: Double {
        get { core.subtitleScale }
        set {
            objectWillChange.send()
            core.subtitleScale = newValue
        }
    }

    public var subtitlePosition: Double {
        get { core.subtitlePosition }
        set {
            objectWillChange.send()
            core.subtitlePosition = newValue
        }
    }

    public var subtitleColorHex: String {
        get { core.subtitleColorHex }
        set {
            objectWillChange.send()
            core.subtitleColorHex = newValue
        }
    }

    public var subtitleBackgroundColorHex: String {
        get { core.subtitleBackgroundColorHex }
        set {
            objectWillChange.send()
            core.subtitleBackgroundColorHex = newValue
        }
    }

    // MARK: - Video scale & interpolation
    //
    // Same "manual objectWillChange" pattern as the subtitle-style
    // properties above, for the same reason: these forward straight to
    // MPVCore with no corresponding property-change observer.

    public var videoScale: String {
        get { core.videoScale }
        set { objectWillChange.send(); core.videoScale = newValue }
    }

    public var chromaScale: String {
        get { core.chromaScale }
        set { objectWillChange.send(); core.chromaScale = newValue }
    }

    public var downscale: String {
        get { core.downscale }
        set { objectWillChange.send(); core.downscale = newValue }
    }

    public var temporalScale: String {
        get { core.temporalScale }
        set { objectWillChange.send(); core.temporalScale = newValue }
    }

    public var scaleParam1: String {
        get { core.scaleParam1 }
        set { objectWillChange.send(); core.scaleParam1 = newValue }
    }

    public var scaleParam2: String {
        get { core.scaleParam2 }
        set { objectWillChange.send(); core.scaleParam2 = newValue }
    }

    @Published public private(set) var isInterpolationEnabled: Bool = false

    /// See `MPVCore.setInterpolationEnabled(_:)`'s doc comment for why
    /// this also touches `video-sync` — this isn't a simple passthrough.
    public func setInterpolationEnabled(_ enabled: Bool) {
        core.setInterpolationEnabled(enabled)
        isInterpolationEnabled = core.isInterpolationEnabled
    }

    public func setAspectMode(_ mode: MPVCore.AspectMode) {
        core.setAspectMode(mode)
    }

    public var videoZoom: Double {
        get { core.videoZoom }
        set { objectWillChange.send(); core.videoZoom = newValue }
    }

    public var videoRotation: Int? {
        get { core.videoRotation }
        set { objectWillChange.send(); core.videoRotation = newValue }
    }

    public var panscan: Double {
        get { core.panscan }
        set { objectWillChange.send(); core.panscan = newValue }
    }

    public var videoUnscaled: MPVCore.UnscaledMode {
        get { core.videoUnscaled }
        set { objectWillChange.send(); core.videoUnscaled = newValue }
    }

    // MARK: - Playback statistics

    /// Snapshot, not observed continuously — see MPVCore.currentStats()'s
    /// doc comment on why polling on demand (matching mpv-android's own
    /// updateStats() being called only from specific UI-refresh points,
    /// not from a standing property observer) is the right model here.
    public func currentStats() -> MPVCore.PlaybackStats {
        core.currentStats()
    }

    // MARK: - Decoder selection

    public func setDecoder(_ option: MPVCore.DecoderOption) {
        core.setDecoder(option)
    }

    private func refreshPlaylist() {
        playlist = core.playlistItems()
        mediaSession.setPlaylistNavigationEnabled(playlist.count > 1)
    }

    public func togglePause() {
        core.cyclePause()
    }

    public func seek(to seconds: Double) {
        core.seek(to: seconds)
        // Explicit update here (rather than relying on the next time-pos
        // tick) so the lock-screen scrubber jumps immediately to the new
        // position instead of visibly catching up over the next second —
        // matches mpv-android's PlaybackStateCompat update happening
        // synchronously with its own seek handling, not on the next
        // periodic position poll.
        mediaSession.updatePlaybackState(position: seconds, duration: duration, isPaused: isPaused)
    }

    public func beginScrub() {
        isSeeking = true
        scrubPosition = position
    }

    public func endScrub() {
        core.seek(to: scrubPosition)
        mediaSession.updatePlaybackState(position: scrubPosition, duration: duration, isPaused: isPaused)
        isSeeking = false
    }

    public func setVolume(_ value: Double) {
        core.volume = value
    }

    public func toggleMute() {
        core.isMuted.toggle()
    }

    public func setSpeed(_ value: Double) {
        core.playbackSpeed = value
    }

    public func selectAudioTrack(_ id: Int64?) {
        core.selectAudioTrack(id)
    }

    public func selectSubtitleTrack(_ id: Int64?) {
        core.selectSubtitleTrack(id)
    }

    public func addSubtitleFile(_ url: URL) {
        core.addSubtitleFile(url.path)
    }

    // MARK: - Touch gestures (mirrors MPVActivity.kt's onPropertyChange)

    /// Text to show in a transient gesture-feedback label (equivalent to
    /// mpv-android's `gestureTextView`), e.g. "12:34 (+00:10)" while
    /// seeking, or "Volume: 80%" while adjusting volume. Empty/nil means
    /// nothing should be shown.
    @Published public private(set) var gestureFeedbackText: String?

    private var gestureInitialSeek: Double = 0
    private var gestureInitialVolume: Double = 0
    private var gestureInitialBrightness: Float = 0
    /// 0 = wasn't paused for seek, 1 = paused for seek and should resume on
    /// finalize, 2 = was already paused before the seek gesture started.
    /// Mirrors mpv-android's `pausedForSeek` tri-state exactly.
    private var pausedForSeek = 0

    /// Whether a seek gesture should move smoothly (exact seek, more CPU)
    /// or in coarse keyframe jumps (faster, less precise) — mirrors
    /// mpv-android's `seek_gesture_smooth` preference. Exposed as a plain
    /// var here since iOS has no SharedPreferences equivalent baked into
    /// MPVKit; the app layer is expected to set this from its own
    /// settings storage, same as it owns every other preference.
    public var smoothSeekGesture: Bool = true

    public lazy var touchGestures = MPVTouchGestures(observer: self)

    /// Mirrors mpv-android's `mightWantToToggleControls = false` inside
    /// `onPropertyChange`'s `Init` case: turns true exactly when a real
    /// Control gesture (seek/volume/bright) actually starts, telling the
    /// view layer this touch sequence is no longer a candidate for the
    /// tap-to-toggle-controls fallback. The view is expected to read this
    /// once per touch-down/up cycle; it resets to false on every new
    /// `.gestureInit`.
    @Published public private(set) var gestureDidCancelTapToggle: Bool = false

    public func onGestureSurfaceResized(width: CGFloat, height: CGFloat) {
        touchGestures.setMetrics(width: width, height: height)
    }

    /// Call at the start of every touch sequence (touch-down), before
    /// `touchGestures.touchDown` — resets the cancel flag so a previous
    /// gesture's state doesn't leak into the next one, matching
    /// `mightWantToToggleControls = true` being reset unconditionally on
    /// every ACTION_DOWN in mpv-android's dispatchTouchEvent.
    public func resetGestureCancelFlag() {
        gestureDidCancelTapToggle = false
    }
}

// MARK: - MPVGestureObserver

extension PlayerViewModel: MPVGestureObserver {
    public nonisolated func onGesturePropertyChange(_ property: MPVPropertyChange, diff: Float) {
        Task { @MainActor in
            self.applyGesturePropertyChange(property, diff: diff)
        }
    }

    @MainActor
    private func applyGesturePropertyChange(_ property: MPVPropertyChange, diff: Float) {
        switch property {
        case .gestureInit:
            gestureInitialSeek = position
            gestureDidCancelTapToggle = true
            gestureInitialBrightness = UIScreen.main.brightness.isFinite
                ? Float(UIScreen.main.brightness)
                : 0.5
            // mpv-android's volume gesture adjusts the system audio stream
            // directly via AudioManager.setStreamVolume(). iOS has no
            // equivalent: apps cannot set the system volume
            // programmatically at all — AVAudioSession.outputVolume is
            // read-only, and the only way to change system volume from
            // code is indirectly, by driving the hidden slider inside an
            // MPVolumeView, which still requires that view to exist in
            // the view hierarchy and is a workaround, not a supported
            // direct-set API. outputVolume is also documented as
            // unreliable for *reading* the current volume in several iOS
            // versions (stale after backgrounding, reports 0 right after
            // session activation on iOS 18 - filed as Apple bugs, no
            // official fix as of this writing). Given that, this gesture
            // adjusts mpv's own in-app `volume` property (0-100) instead
            // of system volume - a deliberate, permanent platform
            // difference from mpv-android, not a temporary stand-in.
            gestureInitialVolume = volume
            pausedForSeek = 0
            gestureFeedbackText = ""

        case .seek:
            guard duration > 0, gestureInitialSeek >= 0 else { return }
            if smoothSeekGesture && pausedForSeek == 0 {
                pausedForSeek = isPaused ? 2 : 1
                if pausedForSeek == 1 {
                    core.isPaused = true
                }
            }

            let newPosExact = min(max(gestureInitialSeek + Double(diff), 0), duration)
            let newPos = Int(newPosExact.rounded())
            let newDiff = Int((newPosExact - gestureInitialSeek).rounded())
            if smoothSeekGesture {
                core.seek(to: newPosExact)
            } else {
                // faster than an exact seek but less precise — matches
                // mpv-android's "seek absolute+keyframes" fast path
                core.command(["seek", "\(newPosExact)", "absolute+keyframes"])
            }

            gestureFeedbackText = "\(Self.formatTime(newPos)) (\(Self.formatTime(newDiff, forceSign: true)))"

        case .volume:
            let newVolume = min(max(gestureInitialVolume + Double(diff) * 100, 0), 100)
            core.volume = newVolume
            gestureFeedbackText = "Volume: \(Int(newVolume))%"

        case .bright:
            let newBrightPercent = min(max(gestureInitialBrightness + diff, 0), 1) * 100
            // UIScreen.main.brightness is still the current, non-deprecated
            // API for app-driven brightness as of this writing. Worth
            // knowing: a brightness set this way persists only until the
            // device locks — iOS restores the user's actual system
            // brightness setting on next unlock, regardless of what an
            // app set it to. This differs from mpv-android's
            // WindowManager.LayoutParams.screenBrightness, which persists
            // for the Activity's lifetime; no fix needed here, just a
            // real platform behavior difference worth knowing about if
            // brightness seems to "reset" during testing.
            UIScreen.main.brightness = CGFloat(newBrightPercent / 100)
            gestureFeedbackText = "Brightness: \(Int(newBrightPercent))%"

        case .finalize:
            if pausedForSeek == 1 {
                core.isPaused = false
            }
            gestureFeedbackText = nil

        case .seekFixed:
            let seekTime = diff * 10 // fixed 10-second jumps, matches mpv-android
            let newPos = Int(position) + Int(seekTime)
            core.command(["seek", "\(seekTime)", "relative"])
            gestureFeedbackText = "\(Self.formatTime(newPos)) (\(Self.formatTime(Int(seekTime), forceSign: true)))"
            scheduleGestureFeedbackFade()

        case .playPause:
            core.cyclePause()

        case .custom:
            // Reserved for mapping to arbitrary mpv keypresses, matching
            // mpv-android's `PropertyChange.Custom` (keycode 0x10002 + diff)
            // — not wired to a concrete action on iOS yet since there's no
            // equivalent settings UI for custom gesture bindings here.
            break
        }
    }

    private func scheduleGestureFeedbackFade() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.gestureFeedbackText = nil
            }
        }
    }

    private static func formatTime(_ totalSeconds: Int, forceSign: Bool = false) -> String {
        let sign = forceSign ? (totalSeconds < 0 ? "-" : "+") : ""
        let s = abs(totalSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        let body = h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
        return sign + body
    }
}

// MARK: - MPVCoreDelegate

extension PlayerViewModel: MPVCoreDelegate {
    public nonisolated func mpv(_ core: MPVCore, event: MPVEvent) {
        Task { @MainActor in
            self.handle(event)
        }
    }

    @MainActor
    private func handle(_ event: MPVEvent) {
        switch event {
        case .propertyChanged(let name, _, let data):
            applyProperty(name: name, data: data)

        case .fileLoaded:
            isFileLoaded = true
            errorMessage = nil

        case .endFile(let reason):
            isFileLoaded = false
            // reason: 0=eof, 2=error, 3=redirect, 4=stop — mirrors
            // MPV_END_FILE_REASON_* constants mpv-android's PlayerActivity
            // switches on in its endFile event handling.
            if reason == 2 {
                errorMessage = core.getPropertyString("error") ?? "Playback error"
            }

        case .idle:
            isIdle = true

        case .shutdown:
            isInitialized = false

        case .logMessage(let prefix, let level, let text):
            // level <= 3 corresponds to mpv's MSGL_FATAL/MSGL_ERROR range;
            // surfacing only serious log lines avoids flooding errorMessage
            // with the verbose "all=v" logging MPVCore.create() requests
            // (matching mpv-android's own ALOGV-vs-user-facing-error split).
            if level <= 3 {
                errorMessage = "[\(prefix)] \(text)"
            }

        case .seek, .playbackRestart, .other:
            break
        }
    }

    @MainActor
    private func applyProperty(name: String, data: MPVPropertyData) {
        switch (name, data) {
        case ("pause", .flag(let v)):
            isPaused = v
            // Update on every pause/resume rather than on time-pos ticks:
            // MPNowPlayingInfoPropertyPlaybackRate + ElapsedPlaybackTime
            // together let the system interpolate the displayed position
            // between updates on its own, so this only needs to be told
            // "the rate changed" at the moment it actually changes, not
            // continuously (see MediaSessionManager.updatePlaybackState's
            // doc comment for the source on this).
            mediaSession.updatePlaybackState(position: position, duration: duration, isPaused: v)
            pipCoordinator.isPaused = v
        case ("time-pos", .double(let v)):
            if !isSeeking { position = v }
        case ("duration", .double(let v)):
            duration = v
            mediaSession.updatePlaybackState(position: position, duration: v, isPaused: isPaused)
            pipCoordinator.duration = v
        case ("volume", .double(let v)):
            volume = v
        case ("mute", .flag(let v)):
            isMuted = v
        case ("speed", .double(let v)):
            speed = v
        case ("media-title", .string(let v)):
            mediaTitle = v
            mediaSession.updateMetadata(.init(title: v))
        case ("core-idle", .flag(let v)):
            isIdle = v
        case ("paused-for-cache", .flag(let v)):
            isBuffering = v
        case ("track-list", _):
            tracks = core.trackList()
        case ("playlist-count", _), ("playlist-pos", _):
            refreshPlaylist()
        case ("hwdec-current", .string(let v)):
            currentDecoder = v
        case ("video-params/w", .int64(let v)):
            lastVideoWidth = v
            OrientationLockController.shared.updateVideoAspectRatio(width: lastVideoWidth, height: lastVideoHeight)
        case ("video-params/h", .int64(let v)):
            lastVideoHeight = v
            OrientationLockController.shared.updateVideoAspectRatio(width: lastVideoWidth, height: lastVideoHeight)
        default:
            break
        }
    }
}
