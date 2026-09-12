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
    /// The codec name (e.g. "h264", "aac"), from `track-list/N/codec`.
    /// Added specifically for the stats overlay (see
    /// MPVPlayer.swift's "Playback statistics" section) — mpv-android's
    /// own updateStats() only surfaces FPS, but a fuller "stats for
    /// nerds" view (matching what mpv's own stats.lua script shows)
    /// needs per-track codec info, which only `track-list` (not any
    /// top-level "video-codec"/"audio-codec" property — no such
    /// properties exist in mpv; checked directly against input.rst
    /// rather than assumed from the name mpv-android's own dialogs use)
    /// exposes.
    public let codec: String?

    public enum TrackType: String {
        case video, audio, sub
    }
}

public enum MPVLoadMode: String {
    case replace
    case append
    /// Space is intentional, not a typo: `input.rst` documents flags to
    /// `loadfile` as combinable with `+` between them in the flags
    /// argument itself (e.g. the manual's own `append+play` example),
    /// not as separate command arguments — `command()` takes each array
    /// element as one argument, so this whole string is the single
    /// "second argument" `loadfile` expects.
    case appendAndPlay = "append+play"
    case insertNext = "insert-next"
    case insertNextAndPlay = "insert-next+play"
    /// Deprecated by mpv since 0.42 in favor of `append+play` (see
    /// `input.rst`'s own deprecation note), kept only for reference/in
    /// case a future consumer needs to target an older mpv build — this
    /// project's own buildscripts pin mpv's master branch
    /// (`v_ci_mpv=master`), so `.appendAndPlay` above is the form this
    /// codebase actually relies on.
    case appendPlay = "append-play"
}

public struct MPVPlaylistItem: Identifiable, Equatable {
    /// This entry's position in the playlist at the time it was
    /// fetched — NOT a stable identifier across playlist mutations.
    /// mpv issue #10082 (still open as of this writing) documents
    /// that mpv's IPC/property API exposes playlist entries by
    /// position for commands (playlist-remove/-move take an index)
    /// but by a separate playlist_entry_id for some events, with no
    /// unified stable-identity story across the two. Since this
    /// value is always freshly re-fetched after any mutation (see
    /// `playlistItems()`'s call sites in PlayerViewModel) rather than
    /// cached and diffed, using the position as `id` is fine for
    /// SwiftUI List identity here, but callers should re-fetch (not
    /// reuse an old array) after any playlist-changing command,
    /// exactly like this codebase already does for `track-list` after
    /// tracks change.
    public let id: Int
    public let filename: String
    public let title: String?
    public let isCurrent: Bool
    public let isPlaying: Bool
}

/// High-level playback convenience methods built on top of MPVCore's raw
/// command/property API. Equivalent in role to the playback control methods
/// mpv-android exposes on its PlayerActivity / MPVView.kt (play, pause,
/// cyclePause, seek helpers, track switching, volume, etc.), just expressed
/// as a clean Swift API here instead of being scattered across an Activity.
public extension MPVCore {

    // MARK: - Loading
    //
    // loadFile itself now lives in the "Playlist" section further down
    // this file (it's mpv's own `loadfile` command, which is also how
    // playlist entries get added/replace/inserted — see that section's
    // doc comment for why `append+play` is used over the deprecated
    // `append-play`). Kept as one definition, not two: an earlier version
    // of this file had loadFile declared here AND in the Playlist
    // section (byte-identical signature and body, added when playlist
    // support was ported from mpv-android's PlaylistDialog), which is an
    // "invalid redeclaration" compile error - Swift does not allow two
    // methods with the same signature on the same extended type, even
    // when the bodies are identical. Found via the actual CI failure
    // log, not by inspection alone.

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

    // MARK: - Subtitle delay & style
    //
    // Equivalent to mpv-android's SubDelayDialog/SubTrackDialog-driven
    // settings, all backed by mpv properties this codebase's existing
    // getPropertyDouble/String/setPropertyDouble/String getters/setters
    // already handle without needing any new format support.

    /// Subtitle delay in seconds; negative values make subtitles appear
    /// earlier. Matches mpv-android's SubDelayDialog range
    /// (-600.0...600.0, i.e. +/-10 minutes — see that dialog's call site
    /// in MPVActivity.kt for this exact range) as the recommended
    /// clamping range for any UI slider/stepper built on top of this,
    /// though mpv itself doesn't enforce a hard range on `sub-delay`.
    var subtitleDelay: Double {
        get { getPropertyDouble("sub-delay") ?? 0 }
        set { setPropertyDouble("sub-delay", newValue) }
    }

    /// Subtitle font-size multiplier (mpv default: 1.0 = 100%).
    ///
    /// IMPORTANT: despite `options.rst` documenting this option's syntax
    /// placeholder as `--sub-scale=<0-100>`, that is not the actual
    /// usable range — the same page states this option's default is 1
    /// (not 50, which is what a genuine 0-100 range's midpoint default
    /// would look like), and mpv's own default `input.conf` (etc/input.conf)
    /// binds `add sub-scale 0.1` / `add sub-scale -0.1` to the font-size
    /// increase/decrease keys — "add 0.1" against a 0-100 range would be
    /// an imperceptible 0.1% nudge, whereas against a ~1.0 default it's
    /// the documented-elsewhere "adjust font size by +/-10%" step size.
    /// The `<0-100>` in the option's own syntax line appears to be
    /// leftover/incorrect placeholder text, not the real constraint —
    /// verified against the option's own stated default and mpv's own
    /// shipped keybindings rather than taken at face value from the
    /// syntax placeholder alone. Callers building a UI slider should
    /// range this roughly 0.1...3.0, not 0...100.
    var subtitleScale: Double {
        get { getPropertyDouble("sub-scale") ?? 1.0 }
        set { setPropertyDouble("sub-scale", newValue) }
    }

    /// Vertical subtitle position, as a percentage of screen height
    /// (100 = mpv's default position, NOT the absolute bottom of the
    /// screen — `options.rst` notes there's normally some margin below
    /// 100's position already). Unlike `subtitleScale` above, this
    /// option's documented 0-150 range is consistent with its stated
    /// default (100 sits inside 0-150, unlike sub-scale's mismatched
    /// 0-100/default-1 pairing), so no correction was needed here.
    var subtitlePosition: Double {
        get { getPropertyDouble("sub-pos") ?? 100 }
        set { setPropertyDouble("sub-pos", newValue) }
    }

    /// Subtitle text color. mpv's hex format for `--sub-color` is
    /// `#RRGGBB` (opaque) or, with alpha, `#AARRGGBB` — alpha comes
    /// FIRST, confirmed directly against `options.rst`'s own worked
    /// example (`--sub-color='#C0808080'` for 50% gray at 75% alpha,
    /// where `C0` is the alpha byte in the leading position). This is
    /// the opposite byte order from the `#RRGGBBAA` (alpha last)
    /// convention several common iOS `UIColor`-hex-string conversion
    /// snippets use — code converting between `UIColor`/`Color` and this
    /// property must build/parse `#AARRGGBB` specifically, not reuse an
    /// off-the-shelf `#RRGGBBAA` hex extension unmodified, or every
    /// color with non-1.0 alpha will come out with red and alpha
    /// swapped.
    var subtitleColorHex: String {
        get { getPropertyString("sub-color") ?? "#FFFFFF" }
        set { setPropertyString("sub-color", newValue) }
    }

    /// Subtitle background color, same `#RRGGBB` / `#AARRGGBB`
    /// (alpha-first) format as `subtitleColorHex` above — see that
    /// property's doc comment for the byte-order warning. mpv's default
    /// is fully transparent (`#00000000`) — set an opaque or
    /// semi-transparent value here to render subtitles with a solid or
    /// "boxed" background instead of libass's usual outline-only style.
    var subtitleBackgroundColorHex: String {
        get { getPropertyString("sub-back-color") ?? "#00000000" }
        set { setPropertyString("sub-back-color", newValue) }
    }

    // MARK: - Video scale & interpolation
    //
    // Equivalent to mpv-android's ScalerDialogPreference (scale/cscale/
    // dscale + their params) and InterpolationDialogPreference
    // (interpolation toggle + tscale + video-sync), including that
    // second dialog's specific consistency logic — see
    // `setInterpolationEnabled(_:)`'s doc comment below for why that
    // logic exists and isn't optional polish.

    /// Video (upscaling) filter. `nil`/`"help"` are not valid values to
    /// set — pass one of the named filters `options.rst` documents
    /// (bilinear/lanczos/ewa_lanczos/ewa_lanczossharp/
    /// ewa_lanczos4sharpest/mitchell/hermite/catmull_rom/oversample/...)
    /// or any other name `mpv --scale=help` lists on a real device (this
    /// environment has no way to run that command to get the fully
    /// authoritative list, since it can't build/run this project).
    var videoScale: String {
        get { getPropertyString("scale") ?? "lanczos" }
        set { setPropertyString("scale", newValue) }
    }

    /// Chroma-interpolation filter. Distinct filter *namespace* from
    /// `videoScale` in name only — same underlying filter list, per
    /// `options.rst`'s own "As --scale, but for interpolating chroma
    /// information" description of this option — so `videoScale`'s
    /// filter names are valid here too.
    var chromaScale: String {
        get { getPropertyString("cscale") ?? "lanczos" }
        set { setPropertyString("cscale", newValue) }
    }

    /// Downscaling filter. Same filter list as `videoScale`/`chromaScale`
    /// (`options.rst`: "Like --scale, but apply these filters on
    /// downscaling instead") — default differs (`hermite`, not
    /// `lanczos`), matching mpv's own stated default for this option
    /// specifically.
    var downscale: String {
        get { getPropertyString("dscale") ?? "hermite" }
        set { setPropertyString("dscale", newValue) }
    }

    /// Temporal (frame-interpolation) filter — used only while
    /// `interpolation` is enabled. IMPORTANT: this is a smaller, distinct
    /// filter namespace from `videoScale`/`chromaScale`/`downscale`
    /// above — `options.rst` states outright that "the only valid
    /// choices for --tscale are separable convolution filters," which is
    /// NOT the full `--scale=help` list. A UI filter picker for this
    /// property must use its own separate option list (`oversample` and
    /// `linear` are both explicitly named as `--tscale`-valid filters
    /// elsewhere in `options.rst`; a full list requires `mpv
    /// --tscale=help` on a real device), not reuse `videoScale`'s list.
    var temporalScale: String {
        get { getPropertyString("tscale") ?? "oversample" }
        set { setPropertyString("tscale", newValue) }
    }

    /// First tunable parameter for filters that take one (e.g.
    /// `mitchell`'s `B` in the B/C spline family) — `options.rst`
    /// documents `--scale-param1`/`--scale-param2` as applying to
    /// whichever of `scale`/`cscale`/`dscale` supports a tunable
    /// parameter; mpv silently ignores this for filters that don't use
    /// it, so this can be set unconditionally without checking which
    /// filter is currently active first.
    var scaleParam1: String {
        get { getPropertyString("scale-param1") ?? "" }
        set { setPropertyString("scale-param1", newValue) }
    }

    var scaleParam2: String {
        get { getPropertyString("scale-param2") ?? "" }
        set { setPropertyString("scale-param2", newValue) }
    }

    /// Toggles frame interpolation, and — critically — keeps
    /// `video-sync` consistent with it, mirroring mpv-android's
    /// `InterpolationDialogPreference.ensureSyncMode`/
    /// `ensureInterpolationToggled` pair exactly.
    ///
    /// This isn't optional belt-and-suspenders: `options.rst`'s own
    /// `--interpolation` entry contains an explicit warning that setting
    /// `interpolation=yes` while `video-sync` is NOT one of the
    /// `display-*` modes results in interpolation being "silently
    /// disabled" — no error, no property-change refusal, it just quietly
    /// does nothing. Without this consistency check, a user could enable
    /// the interpolation toggle in this app's UI and see zero visible
    /// effect with no indication why. Setting `video-sync` to
    /// `display-resample` here whenever interpolation is turned on
    /// (mirroring mpv-android's own choice of "the first entry starting
    /// with display-" from its own mode list) closes that gap the same
    /// way mpv-android's preference dialog does.
    ///
    /// One iOS-specific caveat this codebase cannot fully verify without
    /// a real device: `options.rst` also states the `display-*` modes
    /// "require a vsync blocked presentation mode" (`--opengl-swapinterval=1`
    /// for the GL backend this project uses). This project's render loop
    /// (`MPVGLView`'s render-update-callback-driven `drawIfNeeded()`) has
    /// no explicit swap-interval configuration and no `CADisplayLink` —
    /// EAGLContext's `presentRenderbuffer` is vsync-locked by the system
    /// on iOS regardless, which should satisfy this requirement, but
    /// this hasn't been confirmed by observing actual interpolation
    /// behavior on-device, since this environment can't build or run the
    /// project.
    func setInterpolationEnabled(_ enabled: Bool) {
        setPropertyString("interpolation", enabled ? "yes" : "no")
        guard enabled else { return }
        let current = getPropertyString("video-sync") ?? "audio"
        if !current.hasPrefix("display-") {
            setPropertyString("video-sync", "display-resample")
        }
    }

    var isInterpolationEnabled: Bool {
        getPropertyBool("interpolation") ?? false
    }

    // MARK: - Video aspect / zoom / rotation / crop

    /// Aspect-ratio handling mode, matching `--video-aspect-override`'s
    /// documented special values.
    enum AspectMode {
        /// Use the container/bitstream aspect ratio (mpv default).
        case automatic
        /// Force a specific ratio, e.g. "16:9", "4:3", "1.7777".
        case forced(String)
        /// Ignore aspect ratio entirely, treat pixels as square —
        /// `options.rst`'s recommended modern equivalent of the
        /// deprecated `--video-aspect-override=0`.
        case ignore
    }

    func setAspectMode(_ mode: AspectMode) {
        switch mode {
        case .automatic:
            setPropertyString("video-aspect-override", "no")
            setPropertyString("video-aspect-method", "container")
        case .forced(let ratio):
            setPropertyString("video-aspect-override", ratio)
        case .ignore:
            setPropertyString("video-aspect-override", "no")
            setPropertyString("video-aspect-method", "ignore")
        }
    }

    /// Display zoom as a LOG2 factor, per `options.rst`'s own definition
    /// of `--video-zoom`: 0 = unscaled/normal size, 1 = double size, -1 =
    /// half size, -2 = one fourth size, and so on. NOT a linear
    /// percentage or multiplier — a UI slider bound to this should be
    /// labeled accordingly (e.g. show "2x" / "0.5x" computed as
    /// `pow(2, value)` for a human-readable readout, rather than showing
    /// the raw log2 value or treating it as a percentage).
    var videoZoom: Double {
        get { getPropertyDouble("video-zoom") ?? 0 }
        set { setPropertyDouble("video-zoom", newValue) }
    }

    /// Video rotation in degrees clockwise (0-359), or `nil` to use the
    /// file's own rotation metadata unmodified.
    ///
    /// options.rst's own caveat: "When using hardware decoding without
    /// copy-back, only 90-degree steps work" — this project's default
    /// decoder (`videotoolbox`, a non-copy hw path — see
    /// `MPVCore.DecoderOption.hardware`'s doc comment) is exactly that
    /// case, so arbitrary rotation values will silently only take visible
    /// effect at 0/90/180/270 while hardware decoding without copy is
    /// active; switching to `.software` or `.hardwareCopy` (see
    /// `setDecoder`) is required for intermediate angles to actually
    /// render as requested.
    var videoRotation: Int? {
        get {
            guard let raw = getPropertyString("video-rotate"), raw != "no" else { return nil }
            return Int(raw)
        }
        set {
            if let newValue {
                setPropertyString("video-rotate", String(newValue))
            } else {
                setPropertyString("video-rotate", "no")
            }
        }
    }

    /// Pan-and-scan amount (crops video edges to fill a differently-
    /// shaped display without black bars). `options.rst`'s own
    /// documented range is 0.0-1.0, and it has no effect when
    /// `videoUnscaled` is enabled — both constraints are the option's
    /// own, not an app-specific limitation.
    var panscan: Double {
        get { getPropertyDouble("panscan") ?? 0 }
        set { setPropertyDouble("panscan", newValue.clamped(to: 0...1)) }
    }

    enum UnscaledMode: String {
        case no
        case yes
        case downscaleBig = "downscale-big"
    }

    var videoUnscaled: UnscaledMode {
        get { UnscaledMode(rawValue: getPropertyString("video-unscaled") ?? "no") ?? .no }
        set { setPropertyString("video-unscaled", newValue.rawValue) }
    }

    // MARK: - Playback position persistence ("watch later")
    //
    // Equivalent to mpv-android's savePosition()/readSettings() pair,
    // built on mpv's own built-in watch-later config file mechanism
    // (input.rst's write-watch-later-config / delete-watch-later-config
    // commands) rather than a custom position-tracking implementation —
    // matching mpv-android's own choice to lean on mpv's built-in
    // mechanism instead of reimplementing position persistence at the
    // app layer.

    /// Writes mpv's own "watch later" resume file for the currently
    /// playing file, so the next `loadFile` call for the same path (with
    /// `MPVConfiguration.resumePlaybackEnabled` on) resumes from this
    /// position automatically via mpv's own `resume-playback` handling —
    /// no manual seek-after-load needed on this codebase's side.
    ///
    /// Deliberately checks `eof-reached` first and skips writing if true,
    /// mirroring mpv-android's `savePosition()` doing the exact same
    /// check for the exact same reason: a file the user watched to
    /// completion should start over from the beginning next time, not
    /// resume at (or near) the very end it was already at.
    func writeWatchLaterConfig() {
        guard getPropertyBool("eof-reached") != true else { return }
        command(["write-watch-later-config"])
    }

    /// Deletes the resume file for the currently playing file (or for
    /// `path` if given), e.g. after the user explicitly chooses "start
    /// over" rather than resuming, or after a playlist item finishes
    /// normally and its resume point should not linger.
    func deleteWatchLaterConfig(path: String? = nil) {
        if let path {
            command(["delete-watch-later-config", path])
        } else {
            command(["delete-watch-later-config"])
        }
    }

    // MARK: - Playback statistics ("stats for nerds")
    //
    // Equivalent in spirit to mpv-android's updateStats() (which only
    // surfaces estimated-vf-fps) but closer in scope to mpv's own
    // stats.lua OSD script — this project has no OSD-overlay concept of
    // its own, so this is exposed as a plain Swift struct for a SwiftUI
    // view to render instead.

    public struct PlaybackStats {
        public let videoCodec: String?
        public let audioCodec: String?
        public let containerFps: Double?
        public let estimatedFps: Double?
        public let videoWidth: Int64?
        public let videoHeight: Int64?
        public let hwdecCurrent: String?
        public let videoBitrateKbps: Double?
        public let audioBitrateKbps: Double?
        public let avsync: Double?
        public let droppedFramesDecoder: Int64?
        public let droppedFramesVO: Int64?
        public let cacheBufferingPercent: Int64?
        public let cacheDurationSeconds: Double?
    }
    /// Snapshots current stats via direct `mpv_get_property` calls,
    /// exactly like `playlistItems()`/`trackList()` do for their own
    /// data — polled on demand rather than observed continuously, since
    /// a stats overlay is normally only shown while the user has it open
    /// (mpv-android's own stats overlay is likewise only updated from
    /// `updateStats()`'s call sites, not from a standing property
    /// observer).
    ///
    /// `video-codec`/`audio-codec` ARE real, valid mpv properties —
    /// double-checked directly against mpv's own `player/command.c`
    /// property table after an initial `input.rst`-only search
    /// incorrectly concluded they didn't exist (that search happened to
    /// miss where these are documented/registered). They're aliases
    /// (`video-codec` -> `current-tracks/video/codec-desc`, a
    /// human-readable description like "H.264"; `audio-codec` ->
    /// `current-tracks/audio/codec-desc`) rather than the raw
    /// `track-list`-derived approach this method used in an earlier
    /// draft — using the alias directly is simpler and doesn't require
    /// cross-referencing the currently-selected `vid`/`aid` against
    /// `trackList()`'s output by hand.
    public func currentStats() -> PlaybackStats {
        // video-params is an MPV_FORMAT_NODE like `playlist` and
        // `track-list` — read via its documented sub-properties
        // (video-params/w, /h, etc.) rather than the parent property
        // itself, same reasoning as playlistItems()'s doc comment on
        // why `playlist` itself can't be read directly in this codebase.
        let width = getPropertyInt("video-params/w")
        let height = getPropertyInt("video-params/h")

        return PlaybackStats(
            videoCodec: getPropertyString("video-codec"),
            audioCodec: getPropertyString("audio-codec"),
            // container-fps is internally a C `float` (CONF_TYPE_FLOAT,
            // per mpv's own player/command.c mp_property_fps), not a
            // `double` — but mpv's client API (the layer this Swift code
            // actually talks to) only defines MPV_FORMAT_INT64 and
            // MPV_FORMAT_DOUBLE for numeric properties, no
            // MPV_FORMAT_FLOAT, so internal floats are necessarily
            // promoted to double when crossing that API boundary.
            // getPropertyDouble is used on that basis rather than a
            // confirmed on-device read (this environment cannot compile/
            // run the project) — if this is ever wrong, mpv would refuse
            // the mismatched-format request and this would read nil,
            // which is safe (an absent stat) rather than a bad value.
            containerFps: getPropertyDouble("container-fps"),
            estimatedFps: getPropertyDouble("estimated-vf-fps"),
            videoWidth: width,
            videoHeight: height,
            hwdecCurrent: getPropertyString("hwdec-current"),
            // video-bitrate/audio-bitrate are INT64 properties (bits per
            // second), not DOUBLE — confirmed directly against mpv's own
            // source (player/command.c's mp_property_packet_bitrate
            // returns via m_property_int64_ro). getPropertyDouble on an
            // INT64-typed mpv property fails (mpv refuses a mismatched
            // format request rather than silently converting), which an
            // earlier draft of this method would have hit silently —
            // every bitrate reading would have come back nil with no
            // error surfaced anywhere. getPropertyInt is used here
            // instead, with the bits-per-second -> kilobits-per-second
            // conversion done in Double after the read.
            videoBitrateKbps: getPropertyInt("video-bitrate").map { Double($0) / 1000 },
            audioBitrateKbps: getPropertyInt("audio-bitrate").map { Double($0) / 1000 },
            avsync: getPropertyDouble("avsync"),
            droppedFramesDecoder: getPropertyInt("decoder-frame-drop-count"),
            droppedFramesVO: getPropertyInt("frame-drop-count"),
            cacheBufferingPercent: getPropertyInt("cache-buffering-state"),
            cacheDurationSeconds: getPropertyDouble("demuxer-cache-duration")
        )
    }

    // MARK: - Playlist

    /// Adds a file to the playlist (append) or replaces/inserts per
    /// `mode`. Equivalent to mpv-android's PlaylistDialog "add to
    /// playlist" action -> MPVLib.command(["loadfile", path, "append"]).
    ///
    /// Deliberately uses `append`/`append+play` (space-separated flags on
    /// a single MPVLoadMode case below), not the older `append-play`
    /// single-token form: `input.rst` documents `append-play` as
    /// deprecated since mpv 0.42 in favor of combinable flags
    /// (`append+play`), and this project builds against mpv's master
    /// branch (`v_ci_mpv=master` in buildscripts/include/depinfo.sh), so
    /// the current, non-deprecated syntax applies rather than needing to
    /// support an older mpv version.
    func loadFile(_ path: String, mode: MPVLoadMode = .replace) {
        command(["loadfile", path, mode.rawValue])
    }

    /// Advances to the next playlist entry. Equivalent to mpv-android's
    /// playlist-next button -> MPVLib.command(["playlist-next"]).
    /// `force: true` matches mpv-android's behavior of stopping playback
    /// entirely when there's no next entry, rather than doing nothing.
    func playlistNext(force: Bool = false) {
        command(["playlist-next"] + (force ? ["force"] : []))
    }

    /// Returns to the previous playlist entry.
    func playlistPrev(force: Bool = false) {
        command(["playlist-prev"] + (force ? ["force"] : []))
    }

    /// Jumps directly to a playlist entry by 0-based index and starts
    /// playing it, restarting playback even if that entry is already
    /// current — matches `playlist-play-index`'s documented behavior
    /// (distinct from writing `playlist-pos`, which the manual notes has
    /// no effect if you write the value it already holds).
    func playlistPlay(index: Int) {
        command(["playlist-play-index", String(index)])
    }

    /// Removes the entry at the given 0-based index.
    func playlistRemove(at index: Int) {
        command(["playlist-remove", String(index)])
    }

    /// Moves the entry at `fromIndex` to `toIndex`. Matches
    /// `playlist-move`'s own semantics: `toIndex` is where the item ends
    /// up positioned *before* the move's shift is applied, i.e. the
    /// manual's own example is "move 0 2" moving the first entry to
    /// *after* what was originally the third entry, not to index 2 —
    /// callers building drag-to-reorder UI should test against this
    /// exact semantic rather than assuming plain array-move indexing.
    func playlistMove(from fromIndex: Int, to toIndex: Int) {
        command(["playlist-move", String(fromIndex), String(toIndex)])
    }

    func playlistClear() {
        command(["playlist-clear"])
    }

    func playlistShuffle() {
        command(["playlist-shuffle"])
    }

    /// A single playlist entry. Mirrors mpv-android's `Playlist.PlaylistItem`
    /// used to populate `PlaylistDialog`'s list adapter. See
    /// `MPVPlaylistItem`'s own doc comment (declared above, outside this
    /// extension — matching where `MPVTrack` is declared for the same
    /// reason) for why `id` is the fetch-time index, not a stable
    /// identifier.

    /// Fetches the current playlist by querying `playlist-count` plus
    /// each entry's sub-properties individually (`playlist/N/filename`
    /// etc.), rather than observing or decoding the `playlist` property
    /// directly.
    ///
    /// This isn't a simplification for convenience — the raw `playlist`
    /// property is explicitly documented in `input.rst` as "currently,
    /// the raw property value is useless" (it's an MPV_FORMAT_NODE this
    /// codebase's property-event mapping doesn't decode; see
    /// MPVCore.swift's `mapEvent`, which maps any non-flag/int64/double/
    /// string format to `.none`). The sub-property approach mpv's own
    /// manual documents instead (`playlist/N/filename`, `/title`,
    /// `/current`, `/playing`) uses only formats this codebase already
    /// has working getters for.
    ///
    /// "playing" (not "current") is used for `isPlaying` /
    /// highlighting-the-active-item purposes: IINA's own scripting API
    /// documents `isCurrent` as deprecated in favor of `isPlaying`, and
    /// mpv's own manual describes `playlist-current-pos` as "only
    /// vaguely useful" with behavior that can differ from the actually-
    /// playing entry during mid-transition states — `playlist/N/playing`
    /// maps to `playlist-playing-pos`, which the manual ties directly to
    /// the actual start-file/end-file lifecycle instead.
    func playlistItems() -> [MPVPlaylistItem] {
        guard let count = getPropertyInt("playlist-count"), count > 0 else { return [] }

        return (0..<Int(count)).map { i in
            let filename = getPropertyString("playlist/\(i)/filename") ?? ""
            let title = getPropertyString("playlist/\(i)/title")
            let isCurrent = getPropertyBool("playlist/\(i)/current") ?? false
            let isPlaying = getPropertyBool("playlist/\(i)/playing") ?? false
            return MPVPlaylistItem(id: i, filename: filename, title: title, isCurrent: isCurrent, isPlaying: isPlaying)
        }
    }

    // MARK: - Decoder selection (hardware/software)

    /// Available decoder options for the picker UI, matching
    /// mpv-android's `pickDecoder()` item list — "HW+" for the
    /// zero-copy GPU path, "HW" for hw-decode-then-copy-to-RAM, "SW" for
    /// pure software decoding. Only `videotoolbox`/`videotoolbox-copy`/
    /// `no` are meaningful on iOS: every other hwdec API `input.rst`
    /// documents (`vaapi`, `nvdec`, `d3d11va`, `mediacodec`, etc.) is
    /// Linux/Windows/Android-specific and not compiled into this
    /// project's iOS mpv build at all (see buildscripts/scripts/mpv.sh's
    /// meson flags, which enable only `ios-gl`).
    public enum DecoderOption: String, CaseIterable {
        case hardware = "videotoolbox"
        case hardwareCopy = "videotoolbox-copy"
        case software = "no"

        public var displayName: String {
            switch self {
            case .hardware: return "Hardware (zero-copy)"
            case .hardwareCopy: return "Hardware (copy)"
            case .software: return "Software"
            }
        }
    }

    /// Sets `hwdec` directly at runtime, with no reload/restart of the
    /// current file.
    ///
    /// This was deliberately checked against known risk before being
    /// implemented this way: a 2016 mpv issue (#3788) reports a crash
    /// from cycling hwdec no -> auto-copy -> no -> auto-copy specifically
    /// under the vdpau backend (Linux/NVIDIA), and mpv's own
    /// `--hwdec-extra-frames` documentation separately notes that some
    /// runtime changes related to hw-decode buffer sizing are ignored
    /// once the renderer exists. Neither of those is this codebase's
    /// situation: mpv-android's own `pickDecoder()` sets `hwdec` via
    /// `MPVLib.setPropertyString` directly, with no reload/pause-and-
    /// restart dance beyond pausing the picker dialog itself, and has
    /// done so in production for VideoToolbox's Android equivalent
    /// (mediacodec) for years — so the direct-set approach mirrors an
    /// already-proven pattern for this specific hwdec backend family,
    /// rather than the vdpau-specific crash case above.
    ///
    /// If real devices turn up a VideoToolbox-specific instability from
    /// direct switching (this hasn't been verified on-device, since this
    /// environment has no way to run the build), the fallback is to
    /// reissue the current `loadfile` at the current position instead of
    /// setting the property directly, matching the pattern mpv's own
    /// `reload.lua` companion script uses for a different problem
    /// (stalled network streams) — that script's approach of "preserve
    /// position, reissue loadfile" would carry over directly if needed
    /// here.
    public func setDecoder(_ option: DecoderOption) {
        // setPropertyString (not setOptionString): this is a runtime
        // change to an already-initialized player, the same call
        // mpv-android's pickDecoder() makes via
        // MPVLib.setPropertyString("hwdec", ...) — matching that
        // codepath deliberately, rather than setOptionString (used
        // elsewhere in this codebase only for MPVConfiguration's
        // pre-initialize() setup, a different lifecycle stage with
        // different semantics for which mpv API this maps to
        // internally).
        setPropertyString("hwdec", option.rawValue)
    }

    /// The decoder mpv is actually using right now, which may differ
    /// from what was last requested via `setDecoder` (e.g. hardware
    /// decode can silently fail over to software for an unsupported
    /// codec — see input.rst's "hardware decoding is not enabled by
    /// default... [and] mpv will fall back on software decoding" note).
    /// Equivalent to mpv-android's `hwdecActive` reading `hwdec-current`
    /// rather than echoing back whatever `hwdec` was last set to.
    public func currentDecoder() -> String {
        getPropertyString("hwdec-current") ?? "no"
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
            let codec: String?

            enum CodingKeys: String, CodingKey {
                case id, type, title, lang, selected, codec
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
                isDefault: r.isDefault ?? false,
                codec: r.codec
            )
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
