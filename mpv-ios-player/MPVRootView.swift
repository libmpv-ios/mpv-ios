import SwiftUI
import UniformTypeIdentifiers

/// App entry screen: pick a local file or paste a URL to play. Equivalent
/// to mpv-android's MainActivity, which shows a file browser (backed by
/// its own FileNavigator) plus an "open URL" option; iOS's sandboxed
/// storage model means the natural counterpart is UIDocumentPickerViewController
/// for local files (Files app / iCloud Drive / other document providers)
/// rather than a raw filesystem browser.
public struct MPVRootView: View {
    @State private var showDocumentPicker = false
    @State private var showURLInput = false
    @State private var urlText = ""
    @State private var selectedURL: URL?
    @State private var additionalPlaylistURLs: [URL] = []

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("mpv-ios")
                    .font(.largeTitle.bold())

                VStack(spacing: 12) {
                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("Open File", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showURLInput = true
                    } label: {
                        Label("Open URL", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 40)
            }
            .padding()
            .fileImporter(
                isPresented: $showDocumentPicker,
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .audio, .mp3, .item],
                allowsMultipleSelection: true,
                onCompletion: { result in
                    if case .success(let urls) = result, !urls.isEmpty {
                        // Start accessing a security-scoped resource for
                        // every selected file, matching the access
                        // pattern required for files outside the app
                        // sandbox (iCloud Drive, Files providers, etc.) —
                        // not just the first one, since every URL here
                        // (not only the one MPVPlayerView opens directly)
                        // is read by mpv, either now (the first file) or
                        // later when the playlist advances to it.
                        for url in urls {
                            _ = url.startAccessingSecurityScopedResource()
                        }
                        selectedURL = urls[0]
                        // Remaining files (if any) become additional
                        // playlist entries once MPVPlayerView has loaded
                        // the first one — see MPVPlayerView's own use of
                        // this array in its .onAppear.
                        additionalPlaylistURLs = Array(urls.dropFirst())
                    }
                }
            )
            .alert("Open URL", isPresented: $showURLInput) {
                TextField("https://example.com/video.mp4", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Play") {
                    if let url = URL(string: urlText), url.scheme != nil {
                        selectedURL = url
                    }
                }
            }
            .fullScreenCover(item: $selectedURL) { url in
                MPVPlayerView(url: url, additionalPlaylistURLs: additionalPlaylistURLs) {
                    if url.isFileURL {
                        url.stopAccessingSecurityScopedResource()
                    }
                    for extra in additionalPlaylistURLs where extra.isFileURL {
                        extra.stopAccessingSecurityScopedResource()
                    }
                    additionalPlaylistURLs = []
                    selectedURL = nil
                }
            }
        }
    }
}

// URL needs to be Identifiable for use with .fullScreenCover(item:).
extension URL: Identifiable {
    public var id: String { absoluteString }
}
