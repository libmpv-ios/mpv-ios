import SwiftUI
import MPVKit

/// Full player screen: video surface + overlay controls. Equivalent to
/// mpv-android's PlayerActivity (activity_player.xml layout + the
/// touch/gesture/control-visibility logic in PlayerActivity.kt), expressed
/// as a SwiftUI view instead of an Activity + XML layout.
public struct MPVPlayerView: View {
    @StateObject private var viewModel = PlayerViewModel()

    private let url: URL
    private let onDismiss: (() -> Void)?

    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showTrackSheet = false

    public init(url: URL, onDismiss: (() -> Void)? = nil) {
        self.url = url
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MPVVideoView(core: viewModel.core)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible.toggle()
                    }
                    scheduleAutoHide()
                }

            if viewModel.isBuffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            if controlsVisible {
                controlsOverlay
                    .transition(.opacity)
            }

            if let errorMessage = viewModel.errorMessage {
                errorBanner(errorMessage)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.start()
            viewModel.loadFile(url.isFileURL ? url.path : url.absoluteString)
            scheduleAutoHide()
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(isPresented: $showTrackSheet) {
            TrackSelectionSheet(viewModel: viewModel)
        }
    }

    // MARK: - Controls overlay

    private var controlsOverlay: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var topBar: some View {
        HStack {
            Button {
                onDismiss?()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            Text(viewModel.mediaTitle.isEmpty ? url.lastPathComponent : viewModel.mediaTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Button {
                showTrackSheet = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            Button {
                viewModel.toggleMute()
            } label: {
                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .padding()
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text(formatTime(viewModel.isSeeking ? viewModel.scrubPosition : viewModel.position))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)

                Slider(
                    value: Binding(
                        get: { viewModel.isSeeking ? viewModel.scrubPosition : viewModel.position },
                        set: { viewModel.scrubPosition = $0 }
                    ),
                    in: 0...max(viewModel.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            viewModel.beginScrub()
                        } else {
                            viewModel.endScrub()
                        }
                        scheduleAutoHide()
                    }
                )
                .tint(.white)

                Text(formatTime(viewModel.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }

            HStack(spacing: 40) {
                Button {
                    viewModel.seek(to: max(0, viewModel.position - 10))
                    scheduleAutoHide()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                        .foregroundStyle(.white)
                }

                Button {
                    viewModel.togglePause()
                    scheduleAutoHide()
                } label: {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }

                Button {
                    viewModel.seek(to: viewModel.position + 10)
                    scheduleAutoHide()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .padding(.bottom, 8)
        }
        .padding()
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .padding()
                .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                .padding()
        }
    }

    // MARK: - Helpers

    private func scheduleAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsVisible = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
