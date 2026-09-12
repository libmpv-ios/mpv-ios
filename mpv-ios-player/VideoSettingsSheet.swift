import SwiftUI
import MPVKit

/// Video scale, interpolation, and aspect/zoom/rotation settings.
/// Equivalent to mpv-android's `ScalerDialogPreference` (scale/cscale/
/// dscale + params) and `InterpolationDialogPreference` (interpolation +
/// tscale + video-sync), combined with the aspect/zoom/rotation/panscan
/// controls mpv-android exposes as separate preference-screen entries.
struct VideoSettingsSheet: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    /// `--scale`/`--cscale`/`--dscale` share one filter namespace per
    /// `options.rst` ("As --scale, but for..." / "Like --scale, but...").
    /// This is the subset `options.rst` names explicitly in prose rather
    /// than only via `mpv --scale=help` (which this environment has no
    /// way to run against a real mpv binary) — good enough for a picker
    /// covering the filters most people would actually reach for, not
    /// claimed to be the complete list mpv itself supports.
    private static let spatialScaleFilters = [
        "bilinear", "lanczos", "ewa_lanczos", "ewa_lanczossharp",
        "ewa_lanczos4sharpest", "mitchell", "hermite", "catmull_rom", "oversample"
    ]

    /// `--tscale` is a SEPARATE, smaller filter namespace from the list
    /// above — options.rst states outright that only separable
    /// convolution filters are valid choices for it. Do not merge this
    /// with `spatialScaleFilters`; `oversample` and `linear` are the two
    /// this project's own reading of options.rst can confirm are
    /// `--tscale`-valid (an authoritative full list requires `mpv
    /// --tscale=help` on-device).
    private static let temporalScaleFilters = ["oversample", "linear"]

    var body: some View {
        NavigationStack {
            Form {
                scalerSection
                interpolationSection
                aspectSection
                zoomRotationSection
                panscanSection

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        viewModel.videoScale = "lanczos"
                        viewModel.chromaScale = "lanczos"
                        viewModel.downscale = "hermite"
                        viewModel.temporalScale = "oversample"
                        viewModel.scaleParam1 = ""
                        viewModel.scaleParam2 = ""
                        viewModel.setInterpolationEnabled(false)
                        viewModel.setAspectMode(.automatic)
                        viewModel.videoZoom = 0
                        viewModel.videoRotation = nil
                        viewModel.panscan = 0
                        viewModel.videoUnscaled = .no
                    }
                }
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Scaler section

    private var scalerSection: some View {
        Section {
            filterPicker("Upscale (scale)", selection: $viewModel.videoScale, options: Self.spatialScaleFilters)
            filterPicker("Chroma (cscale)", selection: $viewModel.chromaScale, options: Self.spatialScaleFilters)
            filterPicker("Downscale (dscale)", selection: $viewModel.downscale, options: Self.spatialScaleFilters)

            TextField("Param 1 (e.g. mitchell B)", text: $viewModel.scaleParam1)
                .keyboardType(.decimalPad)
            TextField("Param 2 (e.g. mitchell C)", text: $viewModel.scaleParam2)
                .keyboardType(.decimalPad)
        } header: {
            Text("Scaler")
        } footer: {
            // mpv silently ignores param1/param2 for filters that don't
            // use them (MPVCore.scaleParam1's doc comment) — worth
            // saying so here, otherwise a user who sets these against
            // e.g. "lanczos" (which doesn't take a B/C parameter) would
            // reasonably wonder why nothing changed.
            Text("Params only affect filters that use them (e.g. mitchell's B/C spline parameters). They're ignored otherwise.")
        }
    }

    // MARK: - Interpolation section

    private var interpolationSection: some View {
        Section {
            Toggle("Interpolation", isOn: Binding(
                get: { viewModel.isInterpolationEnabled },
                set: { viewModel.setInterpolationEnabled($0) }
            ))

            if viewModel.isInterpolationEnabled {
                filterPicker("Temporal (tscale)", selection: $viewModel.temporalScale, options: Self.temporalScaleFilters)
            }
        } header: {
            Text("Interpolation")
        } footer: {
            // Directly reflects the real constraint from
            // MPVCore.setInterpolationEnabled's doc comment, not just
            // flavor text — this footer is the user-facing half of that
            // consistency check, explaining *why* toggling this also
            // changes video-sync behind the scenes.
            Text("Reduces judder from mismatched video/display frame rates. Requires display-sync playback timing, which this switch enables automatically.")
        }
    }

    // MARK: - Aspect section

    private var aspectSection: some View {
        Section("Aspect Ratio") {
            Button("Automatic") { viewModel.setAspectMode(.automatic) }
            Button("Ignore (square pixels)") { viewModel.setAspectMode(.ignore) }
            ForEach(["4:3", "16:9", "1.85:1", "2.35:1"], id: \.self) { ratio in
                Button(ratio) { viewModel.setAspectMode(.forced(ratio)) }
            }
        }
    }

    // MARK: - Zoom / rotation section

    private var zoomRotationSection: some View {
        Section("Zoom & Rotation") {
            HStack {
                // videoZoom is a log2 factor (MPVCore.videoZoom's doc
                // comment) — the slider operates on that raw log2 value
                // (a natural range for it, roughly one full stop either
                // side of unscaled) while the label converts it to a
                // human-readable multiplier via pow(2, value) so the
                // user sees "2.0x" rather than a confusing raw "1".
                Text(String(format: "%.2fx", pow(2, viewModel.videoZoom)))
                    .monospacedDigit()
                    .frame(width: 60, alignment: .leading)
                Slider(value: $viewModel.videoZoom, in: -3...3, step: 0.1)
            }

            Picker("Rotation", selection: Binding(
                get: { viewModel.videoRotation ?? -1 },
                set: { viewModel.videoRotation = $0 == -1 ? nil : $0 }
            )) {
                Text("Auto (file metadata)").tag(-1)
                Text("0°").tag(0)
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }

            Picker("Unscaled", selection: $viewModel.videoUnscaled) {
                Text("Off").tag(MPVCore.UnscaledMode.no)
                Text("On").tag(MPVCore.UnscaledMode.yes)
                Text("Downscale if oversized").tag(MPVCore.UnscaledMode.downscaleBig)
            }
        }
    }

    // MARK: - Panscan section

    private var panscanSection: some View {
        Section {
            HStack {
                Text(String(format: "%.0f%%", viewModel.panscan * 100))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .leading)
                Slider(value: $viewModel.panscan, in: 0...1, step: 0.05)
            }
        } header: {
            Text("Pan & Scan")
        } footer: {
            Text("Crops video edges to fill the screen without black bars. Has no effect while Unscaled is on.")
        }
    }

    private func filterPicker(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }
}
