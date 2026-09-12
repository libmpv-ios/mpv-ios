import SwiftUI
import MPVKit

/// "Stats for nerds" overlay, equivalent to mpv-android's stats display
/// (`updateStats()` + `statsTextView`) — shown as an overlay panel on top
/// of the video rather than mpv-android's single-line FPS text, closer
/// in spirit to mpv's own `stats.lua` OSD script's fuller stat set.
///
/// Polls `PlayerViewModel.currentStats()` on a timer while visible,
/// matching mpv-android's own model of only computing stats while
/// something is actually displaying them, rather than mpv itself
/// observing these properties continuously in the background.
struct StatsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel

    @State private var stats: MPVCore.PlaybackStats?
    /// 1 Hz refresh: fast enough that dropped-frame counters and cache
    /// state feel live, slow enough not to noticeably add polling
    /// overhead — this isn't from any specific mpv-android/mpv source,
    /// just a reasonable middle ground since neither project's own stats
    /// display documents a specific recommended refresh interval.
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let stats {
                row("Video", videoSummary(stats))
                row("Audio", stats.audioCodec ?? "—")
                if let fps = stats.estimatedFps {
                    row("FPS", String(format: "%.2f (container: %@)", fps, containerFpsText(stats)))
                }
                row("HW Decode", stats.hwdecCurrent ?? "no")
                row("Bitrate", bitrateSummary(stats))
                if let avsync = stats.avsync {
                    row("A/V Sync", String(format: "%+.3fs", avsync))
                }
                row("Dropped", droppedSummary(stats))
                if let percent = stats.cacheBufferingPercent {
                    row("Cache", cacheSummary(percent: percent, duration: stats.cacheDurationSeconds))
                }
            } else {
                Text("Loading stats…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(10)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { startPolling() }
        .onDisappear { refreshTask?.cancel() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.white)
        }
    }

    private func videoSummary(_ stats: MPVCore.PlaybackStats) -> String {
        var parts: [String] = []
        if let codec = stats.videoCodec { parts.append(codec) }
        if let w = stats.videoWidth, let h = stats.videoHeight { parts.append("\(w)x\(h)") }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }

    private func containerFpsText(_ stats: MPVCore.PlaybackStats) -> String {
        guard let fps = stats.containerFps else { return "—" }
        return String(format: "%.2f", fps)
    }

    private func bitrateSummary(_ stats: MPVCore.PlaybackStats) -> String {
        var parts: [String] = []
        if let v = stats.videoBitrateKbps { parts.append(String(format: "V: %.0f kbps", v)) }
        if let a = stats.audioBitrateKbps { parts.append(String(format: "A: %.0f kbps", a)) }
        return parts.isEmpty ? "—" : parts.joined(separator: "  ")
    }

    private func droppedSummary(_ stats: MPVCore.PlaybackStats) -> String {
        let decoder = stats.droppedFramesDecoder ?? 0
        let vo = stats.droppedFramesVO ?? 0
        return "decoder: \(decoder), display: \(vo)"
    }

    private func cacheSummary(percent: Int64, duration: Double?) -> String {
        if let duration {
            return String(format: "%lld%% (%.1fs)", percent, duration)
        }
        return "\(percent)%"
    }

    private func startPolling() {
        stats = viewModel.currentStats()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                stats = viewModel.currentStats()
            }
        }
    }
}
