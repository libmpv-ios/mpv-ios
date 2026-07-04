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
                onCompletion: { result in
                    if case .success(let url) = result {
                        // Start accessing a security-scoped resource, matching
                        // the access pattern required for files outside the
                        // app sandbox (iCloud Drive, Files providers, etc.).
                        // The player itself re-derives the path from this URL.
                        _ = url.startAccessingSecurityScopedResource()
                        selectedURL = url
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
                MPVPlayerView(url: url) {
                    if url.isFileURL {
                        url.stopAccessingSecurityScopedResource()
                    }
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
