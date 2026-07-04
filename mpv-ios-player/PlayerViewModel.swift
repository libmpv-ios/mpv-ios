import Foundation
import Combine
import MPVKit
import AVFoundation

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
    @Published public private(set) var mediaTitle: String = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isFileLoaded: Bool = false
    @Published public private(set) var isIdle: Bool = true

    /// User-driven scrub position, separate from `position`, so the seek
    /// bar doesn't fight the user's finger while dragging (equivalent to
    /// mpv-android's PlayerActivity `userIsOperatingSeekbar` guard).
    @Published public var scrubPosition: Double = 0

    private var isInitialized = false

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
        } catch {
            errorMessage = "Failed to start playback engine: \(error)"
        }
    }

    /// Equivalent to mpv-android's PlayerActivity.onDestroy() mpv teardown.
    /// The video view's dismantleUIView calls MPVGLView.teardown()
    /// separately and must happen before this, per render.h's
    /// ordering requirement (render context freed before core destroy).
    public func stop() {
        core.destroy()
        isInitialized = false
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
    }

    // MARK: - Playback controls (thin forwards to MPVCore, kept here so
    // the SwiftUI view layer never touches MPVCore directly — same
    // separation mpv-android keeps between PlayerActivity and MPVView)

    public func loadFile(_ path: String) {
        errorMessage = nil
        core.loadFile(path)
    }

    public func togglePause() {
        core.cyclePause()
    }

    public func seek(to seconds: Double) {
        core.seek(to: seconds)
    }

    public func beginScrub() {
        isSeeking = true
        scrubPosition = position
    }

    public func endScrub() {
        core.seek(to: scrubPosition)
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
        case ("time-pos", .double(let v)):
            if !isSeeking { position = v }
        case ("duration", .double(let v)):
            duration = v
        case ("volume", .double(let v)):
            volume = v
        case ("mute", .flag(let v)):
            isMuted = v
        case ("speed", .double(let v)):
            speed = v
        case ("media-title", .string(let v)):
            mediaTitle = v
        case ("core-idle", .flag(let v)):
            isIdle = v
        case ("paused-for-cache", .flag(let v)):
            isBuffering = v
        case ("track-list", _):
            tracks = core.trackList()
        default:
            break
        }
    }
}
