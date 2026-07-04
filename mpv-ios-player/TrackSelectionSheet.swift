import SwiftUI
import MPVKit

/// Audio/subtitle/video track picker, equivalent to the track-selection
/// AlertDialogs mpv-android's PlayerActivity.kt builds from MPVLib's
/// track-list property (there via `trackSwitchNotification` +
/// `MPVLib.getPropertyString("track-list")` parsing).
struct TrackSelectionSheet: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                trackSection(title: "Audio", type: .audio) { id in
                    viewModel.selectAudioTrack(id)
                }
                trackSection(title: "Subtitles", type: .sub) { id in
                    viewModel.selectSubtitleTrack(id)
                }
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

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
