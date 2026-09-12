import SwiftUI
import MPVKit

/// Playlist viewer/editor, equivalent to mpv-android's `PlaylistDialog`
/// (a RecyclerView-backed dialog listing `Playlist.PlaylistItem`s with
/// tap-to-play, remove, and reorder).
struct PlaylistSheet: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.playlist.isEmpty {
                    // Not ContentUnavailableView: iOS 17.0+ only, this
                    // app target's deployment target is 16.0 (project.yml)
                    // — the same category of mismatch entry 26/entry 27
                    // in RESEARCH.md already had to catch and fix
                    // elsewhere for onChange(of:), so a plain VStack is
                    // used here instead of reintroducing it.
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Playlist is empty")
                            .font(.headline)
                        Text("Files you add to the playlist will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.playlist) { item in
                            row(for: item)
                        }
                        .onDelete { offsets in
                            // Reversed: removing by index shifts every
                            // later index down by one, so removing
                            // front-to-back (ascending offsets, the
                            // default IndexSet iteration order) against
                            // stale indices would delete the wrong
                            // entries after the first removal. Deleting
                            // back-to-front against this same
                            // pre-mutation snapshot keeps every
                            // not-yet-processed index valid.
                            for index in offsets.sorted(by: >) {
                                viewModel.removeFromPlaylist(at: index)
                            }
                        }
                        .onMove { source, destination in
                            // SwiftUI's onMove destination is expressed
                            // in "array insertion point" terms (0...count),
                            // not directly as mpv's playlist-move target
                            // index — see MPVCore.playlistMove's own doc
                            // comment on that command's specific index
                            // semantics. This project only supports
                            // single-item drags (source.count == 1) since
                            // mpv's playlist-move itself only moves one
                            // entry per call; multi-item drag reordering
                            // would need one playlist-move call per
                            // dragged item, sequenced carefully against
                            // shifting indices, which isn't implemented
                            // here.
                            guard let from = source.first else { return }
                            let to = destination > from ? destination - 1 : destination
                            viewModel.movePlaylistItem(from: from, to: to)
                        }
                    }
                }
            }
            .navigationTitle("Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.playlist.isEmpty {
                        Menu {
                            Button {
                                viewModel.shufflePlaylist()
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            Button(role: .destructive) {
                                viewModel.clearPlaylist()
                            } label: {
                                Label("Clear Playlist", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                if !viewModel.playlist.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
        }
    }

    private func row(for item: MPVPlaylistItem) -> some View {
        Button {
            viewModel.playPlaylistItem(at: item.id)
        } label: {
            HStack {
                Image(systemName: item.isPlaying ? "play.fill" : "doc")
                    .foregroundStyle(item.isPlaying ? Color.accentColor : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading) {
                    Text(item.title?.isEmpty == false ? item.title! : displayName(for: item.filename))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if item.title?.isEmpty == false {
                        Text(displayName(for: item.filename))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
        }
    }

    /// mpv's `playlist/N/filename` is a full path or URL (see input.rst's
    /// own description of that sub-property) — shown here as just the
    /// last path component for readability, matching how
    /// `MPVPlayerView`'s top bar already falls back to
    /// `url.lastPathComponent` rather than a full path/URL when no
    /// media-title metadata is available.
    private func displayName(for filename: String) -> String {
        URL(string: filename)?.lastPathComponent ?? filename
    }
}
