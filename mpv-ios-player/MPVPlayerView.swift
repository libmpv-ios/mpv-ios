import SwiftUI
import MPVKit
import AVKit

/// Full player screen: video surface + overlay controls. Equivalent to
/// mpv-android's PlayerActivity (activity_player.xml layout + the
/// touch/gesture/control-visibility logic in PlayerActivity.kt), expressed
/// as a SwiftUI view instead of an Activity + XML layout.
public struct MPVPlayerView: View {
    @StateObject private var viewModel = PlayerViewModel()

    private let url: URL
    private let additionalPlaylistURLs: [URL]
    private let onDismiss: (() -> Void)?

    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showTrackSheet = false
    @State private var showPlaylistSheet = false
    @State private var showVideoSettingsSheet = false
    @State private var showStatsOverlay = false
    @ObservedObject private var orientationLock = OrientationLockController.shared
    @State private var dragInProgress = false
    @State private var mightWantToToggleControls = true

    public init(url: URL, additionalPlaylistURLs: [URL] = [], onDismiss: (() -> Void)? = nil) {
        self.url = url
        self.additionalPlaylistURLs = additionalPlaylistURLs
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                MPVVideoView(core: viewModel.core, pipCoordinator: viewModel.pipCoordinator)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onAppear {
                        viewModel.onGestureSurfaceResized(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                    }
                    .onChange(of: geometry.size) { newSize in
                        viewModel.onGestureSurfaceResized(
                            width: newSize.width,
                            height: newSize.height
                        )
                    }
                    .gesture(
                        // minimumDistance: 0 so this also fires on a plain
                        // tap-down/tap-up with no movement — MPVTouchGestures
                        // itself decides whether that sequence counts as a
                        // tap gesture (its own processTap logic), the same
                        // way mpv-android's dispatchTouchEvent feeds every
                        // touch phase through TouchGestures regardless of
                        // whether the user ends up moving their finger.
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                if !dragInProgress {
                                    dragInProgress = true
                                    viewModel.resetGestureCancelFlag()
                                    _ = viewModel.touchGestures.touchDown(at: value.startLocation)
                                    // Matches mpv-android's dispatchTouchEvent:
                                    // set true unconditionally on touch-down;
                                    // PlayerViewModel flips this false itself
                                    // once a real Control gesture starts
                                    // (mirroring onPropertyChange's Init case
                                    // setting mightWantToToggleControls = false
                                    // in the Kotlin original).
                                    mightWantToToggleControls = true
                                } else {
                                    if viewModel.touchGestures.touchMoved(to: value.location) {
                                        scheduleAutoHide()
                                    }
                                    if viewModel.gestureDidCancelTapToggle {
                                        mightWantToToggleControls = false
                                    }
                                }
                            }
                            .onEnded { value in
                                let gestureHandled = viewModel.touchGestures.touchUp(at: value.location)
                                dragInProgress = false
                                if gestureHandled {
                                    scheduleAutoHide()
                                }
                                if viewModel.gestureDidCancelTapToggle {
                                    mightWantToToggleControls = false
                                }
                                if mightWantToToggleControls {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        controlsVisible.toggle()
                                    }
                                    scheduleAutoHide()
                                }
                            }
                    )
            }

            // Non-zero size, invisible during normal playback — see
            // PictureInPictureLayerView's doc comment for why this
            // cannot be `.hidden` or zero-frame without silently
            // breaking PiP.
            PictureInPictureLayerView(coordinator: viewModel.pipCoordinator)
                .allowsHitTesting(false)
                .opacity(0)

            if let feedback = viewModel.gestureFeedbackText, !feedback.isEmpty {
                Text(feedback)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
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

            if showStatsOverlay {
                VStack {
                    HStack {
                        StatsOverlay(viewModel: viewModel)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 60)
                .padding(.leading, 12)
                .allowsHitTesting(false)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.start()
            viewModel.loadFile(url.isFileURL ? url.path : url.absoluteString)
            for extraURL in additionalPlaylistURLs {
                viewModel.addToPlaylist(extraURL.isFileURL ? extraURL.path : extraURL.absoluteString)
            }
            scheduleAutoHide()
            viewModel.pipCoordinator.setUpControllerIfNeeded()
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(isPresented: $showTrackSheet) {
            TrackSelectionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showPlaylistSheet) {
            PlaylistSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showVideoSettingsSheet) {
            VideoSettingsSheet(viewModel: viewModel)
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
                // "waveform" (not "list.bullet") specifically to stay
                // visually distinct from the playlist button below —
                // both used "list.bullet" in an earlier draft, which
                // would have made the two buttons indistinguishable at a
                // glance.
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            if viewModel.playlist.count > 1 {
                Button {
                    showPlaylistSheet = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }

            Button {
                showVideoSettingsSheet = true
            } label: {
                Image(systemName: "camera.aperture")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            Button {
                showStatsOverlay.toggle()
            } label: {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title3)
                    .foregroundStyle(showStatsOverlay ? .yellow : .white)
            }

            Menu {
                ForEach(OrientationLockController.Mode.allCases, id: \.self) { mode in
                    Button {
                        orientationLock.setMode(mode)
                    } label: {
                        if orientationLock.mode == mode {
                            Label(mode.rawValue.capitalized, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue.capitalized)
                        }
                    }
                }
            } label: {
                // Tap cycles landscape<->portrait directly (matching
                // mpv-android's cycleOrientation() button behavior);
                // long-press/tap-and-hold on a Menu shows the full mode
                // list (auto/landscape/portrait/unlocked), matching
                // mpv-android's own pattern of a tap-cycles /
                // long-press-opens-picker pair used elsewhere for
                // decoder selection.
                Image(systemName: orientationIconName)
                    .font(.title3)
                    .foregroundStyle(.white)
            } primaryAction: {
                orientationLock.cycleOrientation()
            }

            Button {
                viewModel.toggleMute()
            } label: {
                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            if AVPictureInPictureController.isPictureInPictureSupported() {
                Button {
                    if viewModel.pipCoordinator.isPictureInPictureActive {
                        viewModel.pipCoordinator.stopPictureInPicture()
                    } else {
                        viewModel.pipCoordinator.startPictureInPicture()
                    }
                } label: {
                    Image(systemName: "pip.enter")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
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

    private var orientationIconName: String {
        switch orientationLock.mode {
        case .auto: return "arrow.triangle.2.circlepath"
        case .landscape: return "rectangle.landscape.rotate"
        case .portrait: return "rectangle.portrait.rotate"
        case .unlocked: return "lock.open.rotation"
        }
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
