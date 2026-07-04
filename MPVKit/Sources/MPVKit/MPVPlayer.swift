import Foundation

/// A track (audio/video/subtitle) as reported by mpv's track-list property.
/// Mirrors the Track data class typically used in mpv-android's
/// PlayerActivity/TrackData for populating track-selection menus.
public struct MPVTrack: Identifiable, Equatable {
    public let id: Int64          // mpv's track "id" field (used in aid/sid/vid)
    public let type: TrackType
    public let title: String?
    public let lang: String?
    public let isSelected: Bool
    public let isDefault: Bool

    public enum TrackType: String {
        case video, audio, sub
    }
}

public enum MPVLoadMode: String {
    case replace
    case append
    case appendPlay = "append-play"
}

/// High-level playback convenience methods built on top of MPVCore's raw
/// command/property API. Equivalent in role to the playback control methods
/// mpv-android exposes on its PlayerActivity / MPVView.kt (play, pause,
/// cyclePause, seek helpers, track switching, volume, etc.), just expressed
/// as a clean Swift API here instead of being scattered across an Activity.
public extension MPVCore {

    // MARK: - Loading

    /// Loads a local file path or a network URL for playback.
    /// Equivalent to MPVView.kt's playFile() -> MPVLib.command(["loadfile", path]).
    func loadFile(_ path: String, mode: MPVLoadMode = .replace) {
        command(["loadfile", path, mode.rawValue])
    }

    // MARK: - Transport controls

    /// Equivalent to MPVView.kt's `paused` setter -> setPropertyBoolean("pause", ...).
    var isPaused: Bool {
        get { getPropertyBool("pause") ?? true }
        set { setPropertyBool("pause", newValue) }
    }

    /// Equivalent to a "toggle play/pause" button handler calling
    /// `cyclePause()` in mpv-android (implemented there via
    /// MPVLib.command(["cycle", "pause"])).
    func cyclePause() {
        command(["cycle", "pause"])
    }

    func play() { isPaused = false }
    func pause() { isPaused = true }

    /// Stops playback entirely (unloads the current file).
    func stop() {
        command(["stop"])
    }

    // MARK: - Seeking

    /// Absolute seek in seconds, equivalent to MPVView.kt's seek-to-position
    /// handling via setPropertyDouble("time-pos", seconds) or the
    /// `seek <target> absolute` command. Using the command form (rather than
    /// setting time-pos directly) matches mpv-android's approach and handles
    /// edge cases (seeking past EOF, seeking during buffering) more robustly
    /// than a raw property set.
    func seek(to seconds: Double) {
        command(["seek", String(seconds), "absolute"])
    }

    /// Relative seek, e.g. skip forward/back buttons.
    func seek(by deltaSeconds: Double) {
        command(["seek", String(deltaSeconds), "relative"])
    }

    /// Current playback position in seconds, nil if not yet available
    /// (matches mpv's own semantics: time-pos is unavailable before the
    /// first frame is decoded).
    var timePosition: Double? {
        getPropertyDouble("time-pos")
    }

    /// Total duration in seconds, nil if unknown (e.g. live streams).
    var duration: Double? {
        getPropertyDouble("duration")
    }

    // MARK: - Volume

    /// 0-100 scale, matching mpv's own `volume` property range and
    /// mpv-android's volume slider convention.
    var volume: Double {
        get { getPropertyDouble("volume") ?? 100 }
        set { setPropertyDouble("volume", newValue.clamped(to: 0...100)) }
    }

    var isMuted: Bool {
        get { getPropertyBool("mute") ?? false }
        set { setPropertyBool("mute", newValue) }
    }

    // MARK: - Playback speed

    var playbackSpeed: Double {
        get { getPropertyDouble("speed") ?? 1.0 }
        set { setPropertyDouble("speed", max(0.01, newValue)) }
    }

    // MARK: - Track selection

    /// Selects an audio track by mpv track id, or pass nil to disable audio.
    /// Equivalent to mpv-android's track-selection dialog calling
    /// setPropertyString("aid", id) / ("no").
    func selectAudioTrack(_ id: Int64?) {
        setPropertyString("aid", id.map(String.init) ?? "no")
    }

    /// Selects a subtitle track by mpv track id, or pass nil to disable subs.
    func selectSubtitleTrack(_ id: Int64?) {
        setPropertyString("sid", id.map(String.init) ?? "no")
    }

    /// Selects a video track by mpv track id, or pass nil to disable video
    /// (audio-only playback).
    func selectVideoTrack(_ id: Int64?) {
        setPropertyString("vid", id.map(String.init) ?? "no")
    }

    /// Adds an external subtitle file, equivalent to mpv-android's "add
    /// external subtitle" file-picker flow calling
    /// command(["sub-add", path, "select"]).
    func addSubtitleFile(_ path: String, select: Bool = true) {
        command(["sub-add", path, select ? "select" : "auto"])
    }

    /// Adds an external audio track file.
    func addAudioFile(_ path: String, select: Bool = true) {
        command(["audio-add", path, select ? "select" : "auto"])
    }

    // MARK: - Track listing

    /// Parses mpv's `track-list` property (returned as an mpv node / JSON
    /// string via the string-format getter) into MPVTrack values.
    /// mpv-android does the equivalent parsing inside
    /// PlayerActivity.kt's track-list handling, reading MPV_FORMAT_NODE
    /// directly; here we take the simpler route of requesting the
    /// track-list as JSON text via `get_property_string` on
    /// "track-list", since MPVCore's typed getters intentionally don't
    /// expose the raw MPV_FORMAT_NODE variant (arbitrary nested
    /// array/map data) to keep the public API small — call
    /// `getPropertyString("track-list")` directly and decode with
    /// `JSONDecoder` if you need this instead of relying on this helper's
    /// simplified field mapping.
    func trackList() -> [MPVTrack] {
        guard let json = getPropertyString("track-list"),
              let data = json.data(using: .utf8) else { return [] }

        struct RawTrack: Decodable {
            let id: Int64
            let type: String
            let title: String?
            let lang: String?
            let selected: Bool?
            let isDefault: Bool?

            enum CodingKeys: String, CodingKey {
                case id, type, title, lang, selected
                case isDefault = "default"
            }
        }

        guard let raw = try? JSONDecoder().decode([RawTrack].self, from: data) else { return [] }

        return raw.compactMap { r in
            guard let type = MPVTrack.TrackType(rawValue: r.type) else { return nil }
            return MPVTrack(
                id: r.id,
                type: type,
                title: r.title,
                lang: r.lang,
                isSelected: r.selected ?? false,
                isDefault: r.isDefault ?? false
            )
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
