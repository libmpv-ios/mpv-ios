import SwiftUI
import MPVKit

/// Subtitle delay and style settings, equivalent to mpv-android's
/// SubDelayDialog (delay) plus the style-related entries of its
/// preferences screen (scale/position/color are Android `Preference`
/// screens there, not a single dialog — combined into one sheet here
/// since this project doesn't have a separate settings screen yet).
struct SubtitleStyleSheet: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    /// Matches mpv-android's own SubDelayDialog range (-600.0...600.0
    /// seconds — see that dialog's call site in MPVActivity.kt) rather
    /// than an arbitrary UI choice.
    private let delayRange: ClosedRange<Double> = -600...600
    /// mpv's own default `input.conf` steps sub-scale by 0.1 per
    /// keypress (see MPVCore.subtitleScale's doc comment for why this,
    /// not the option's misleading 0-100 syntax placeholder, is the real
    /// usable range) — 0.1 as a slider floor keeps text from shrinking
    /// to imperceptible/zero size, 3.0 as a ceiling matches roughly what
    /// stays legible without needing to scroll past the screen edges.
    private let scaleRange: ClosedRange<Double> = 0.1...3.0
    /// Matches `--sub-pos`'s own documented range exactly (0-150,
    /// consistent with its default of 100 — see MPVCore.subtitlePosition's
    /// doc comment on why this option's range didn't need correcting the
    /// way sub-scale's did).
    private let positionRange: ClosedRange<Double> = 0...150

    var body: some View {
        NavigationStack {
            Form {
                Section("Delay") {
                    HStack {
                        Text(String(format: "%.1fs", viewModel.subtitleDelay))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .leading)
                        Slider(
                            value: $viewModel.subtitleDelay,
                            in: delayRange,
                            step: 0.1
                        )
                    }
                    Text("Negative values make subtitles appear earlier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Size & Position") {
                    HStack {
                        Text("Size")
                        Slider(value: $viewModel.subtitleScale, in: scaleRange, step: 0.05)
                        Text(String(format: "%.0f%%", viewModel.subtitleScale * 100))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                    HStack {
                        Text("Position")
                        Slider(value: $viewModel.subtitlePosition, in: positionRange, step: 1)
                        Text(String(format: "%.0f", viewModel.subtitlePosition))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Section("Color") {
                    ColorPicker(
                        "Text",
                        selection: Binding(
                            get: { Color(hexAARRGGBB: viewModel.subtitleColorHex) },
                            set: { viewModel.subtitleColorHex = $0.toHexAARRGGBB() }
                        ),
                        supportsOpacity: true
                    )
                    ColorPicker(
                        "Background",
                        selection: Binding(
                            get: { Color(hexAARRGGBB: viewModel.subtitleBackgroundColorHex) },
                            set: { viewModel.subtitleBackgroundColorHex = $0.toHexAARRGGBB() }
                        ),
                        supportsOpacity: true
                    )
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        viewModel.subtitleDelay = 0
                        viewModel.subtitleScale = 1.0
                        viewModel.subtitlePosition = 100
                        viewModel.subtitleColorHex = "#FFFFFF"
                        viewModel.subtitleBackgroundColorHex = "#00000000"
                    }
                }
            }
            .navigationTitle("Subtitle Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension Color {
    /// Parses mpv's `#RRGGBB` / `#AARRGGBB` (alpha-FIRST) hex format —
    /// see `MPVCore.subtitleColorHex`'s doc comment for why this is not
    /// the same byte order as the `#RRGGBBAA` (alpha-last) convention
    /// several general-purpose iOS hex-color snippets assume. Falls back
    /// to opaque white on any unparseable input, matching mpv's own
    /// `sub-color` default.
    init(hexAARRGGBB hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }

        var value: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&value) else {
            self = .white
            return
        }

        let a, r, g, b: UInt64
        switch sanitized.count {
        case 8: // AARRGGBB
            a = (value >> 24) & 0xFF
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        case 6: // RRGGBB, fully opaque
            a = 0xFF
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        default:
            self = .white
            return
        }

        self = Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Formats this color as mpv's alpha-first `#AARRGGBB`. Always
    /// includes the alpha byte (rather than omitting it for fully-opaque
    /// colors and emitting bare `#RRGGBB`) — mpv accepts `#AARRGGBB`
    /// unconditionally per its own documented syntax, so there's no
    /// correctness reason to special-case the opaque form, and always
    /// writing 8 digits keeps this formatter's output trivially
    /// round-trippable through `init(hexAARRGGBB:)` above without a
    /// length-dependent branch on the write side too.
    func toHexAARRGGBB() -> String {
        // UIColor bridge, not Color's own `cgColor`: confirmed that
        // `cgColor` returns nil for dynamic/system colors (e.g.
        // `Color.blue`) and only succeeds for colors constructed from
        // constant RGB components — since this sheet's ColorPicker lets
        // the user pick from the system's full color picker UI (which
        // can hand back either kind), going through UIColor's
        // getRed(green:blue:alpha:) is the path that works
        // unconditionally for both.
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X%02X",
            Int((a * 255).rounded()),
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}
