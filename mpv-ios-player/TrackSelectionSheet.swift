import SwiftUI
import MPVKit

/// Audio/subtitle/video track picker, equivalent to the track-selection
/// AlertDialogs mpv-android's PlayerActivity.kt builds from MPVLib's
/// track-list property (there via `trackSwitchNotification` +
/// `MPVLib.getPropertyString("track-list")` parsing).
struct TrackSelectionSheet: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showSubtitleStyleSheet = false

    var body: some View {
        NavigationStack {
            List {
                trackSection(title: "Audio", type: .audio) { id in
                    viewModel.selectAudioTrack(id)
                }
                trackSection(title: "Subtitles", type: .sub) { id in
                    viewModel.selectSubtitleTrack(id)
                }
                // Only meaningful with a subtitle track actually
                // selected — matches mpv-android's own subtitle-style
                // controls only being reachable while a sub track is
                // active.
                if viewModel.tracks.contains(where: { $0.type == .sub && $0.isSelected }) {
                    Section {
                        Button {
                            showSubtitleStyleSheet = true
                        } label: {
                            Label("Subtitle Delay & Style", systemImage: "captions.bubble")
                        }
                    }
                }
                decoderSection
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSubtitleStyleSheet) {
                SubtitleStyleSheet(viewModel: viewModel)
            }
        }
    }

    /// Equivalent to mpv-android's `pickDecoder()` dialog — but shown as
    /// a persistent section here rather than dismissing on selection
    /// (unlike the track sections above, which represent a one-off
    /// choice per track type): decoder can reasonably be changed more
    /// than once while comparing hardware vs. software playback quality
    /// on a given file.
    private var decoderSection: some View {
        Section {
            ForEach(MPVCore.DecoderOption.allCases, id: \.rawValue) { option in
                Button {
                    viewModel.setDecoder(option)
                    lastRequestedDecoderRawValue = option.rawValue
                } label: {
                    HStack {
                        Text(option.displayName)
                        Spacer()
                        // Compares against the *requested* option, not
                        // `viewModel.currentDecoder` (the actually-active
                        // decoder) — mpv can silently fall back from
                        // hardware to software for an unsupported codec
                        // (see MPVCore.currentDecoder's doc comment), and
                        // showing that fallback as if the user had picked
                        // "Software" themselves would misrepresent their
                        // actual selection. The separate caption below
                        // surfaces the actually-active decoder instead,
                        // so a silent fallback is visible without
                        // corrupting which option shows as checked.
                        if option.rawValue == lastRequestedDecoderRawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text("Decoder")
        } footer: {
            Text("Active: \(viewModel.currentDecoder)")
        }
    }

    /// Tracks the user's most recent explicit decoder selection,
    /// defaulting to "videotoolbox" (MPVConfiguration's own default) so
    /// the checkmark is correct before the user has ever opened this
    /// sheet. Deliberately separate from `viewModel.currentDecoder`
    /// (mpv's actually-active decoder) — see `decoderSection`'s comment
    /// on why these two must not be conflated for the checkmark.
    @State private var lastRequestedDecoderRawValue: String = MPVCore.DecoderOption.hardware.rawValue

    @ViewBuilder
    private func trackSection(
        title: String,
        type: MPVTrack.TrackType,
        onSelect: @escaping (Int64?) -> Void
    ) -> some View {
        let tracksOfType = viewModel.tracks.filter { $0.type == type }

        Section(title) {
            Button {
                onSelect(nil)
                dismiss()
            } label: {
                HStack {
                    Text("Off")
                    Spacer()
                    if !tracksOfType.contains(where: { $0.isSelected }) {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .foregroundStyle(.primary)

            ForEach(tracksOfType) { track in
                Button {
                    onSelect(track.id)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(track.title ?? track.lang ?? "Track \(track.id)")
                            if let lang = track.lang, track.title != nil {
                                Text(lang)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if track.isSelected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }
}
