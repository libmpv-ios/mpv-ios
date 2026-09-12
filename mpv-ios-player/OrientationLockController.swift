import UIKit

/// Orientation locking, equivalent to mpv-android's
/// `cycleOrientation()` (manual toggle) and `updateOrientation()`
/// (auto-lock landscape/portrait based on the current video's aspect
/// ratio).
///
/// `AppDelegate.application(_:supportedInterfaceOrientationsFor:)`
/// reads `currentMask` from this singleton — see that file's own doc
/// comment for why a `UIApplicationDelegate` is required at all in a
/// SwiftUI-lifecycle app. This class owns the actual mode/mask logic;
/// `AppDelegate` is a thin, mostly-logic-free UIKit bridge.
@MainActor
final class OrientationLockController: ObservableObject {
    static let shared = OrientationLockController()

    enum Mode: String, CaseIterable {
        /// Follow the current video's aspect ratio, matching
        /// mpv-android's "auto" `autoRotationMode` — landscape video
        /// locks to landscape, portrait video locks to portrait, square
        /// (or no video) leaves rotation unrestricted.
        case auto
        case landscape
        case portrait
        /// Unrestricted — mpv-android's `SCREEN_ORIENTATION_UNSPECIFIED`
        /// fallback, exposed here as its own case rather than folding it
        /// into `.auto` with a permanently-square aspect, since a user
        /// explicitly choosing "no lock" is a different intent from
        /// "lock is currently open because this video happens to be
        /// square."
        case unlocked
    }

    @Published private(set) var mode: Mode = .auto
    /// Set from the currently-playing video's aspect ratio (width /
    /// height) whenever it changes — see `PlayerViewModel`'s
    /// `video-params/w`/`video-params/h`-driven update, mirroring
    /// mpv-android's own `player.getVideoAspect()` call inside
    /// `updateOrientation()`.
    private var videoAspectRatio: Double?

    /// Threshold below which a video is treated as "square enough" to
    /// leave rotation unrestricted rather than force-locking to either
    /// orientation. mpv-android defines an equivalent
    /// `ASPECT_RATIO_MIN` constant for the identical purpose (its
    /// `updateOrientation()` checks `ratio in (1f/ASPECT_RATIO_MIN)
    /// ..ASPECT_RATIO_MIN`); mpv-android's own source was not consulted
    /// for the *exact* numeric constant, so 1.2 here is this project's
    /// own reasonable choice for "closer to square than to a standard
    /// 4:3/16:9 shape," not a value ported directly from mpv-android.
    private let squareAspectThreshold = 1.2

    private init() {}

    var currentMask: UIInterfaceOrientationMask {
        switch mode {
        case .auto:
            return autoModeMask
        case .landscape:
            return .landscape
        case .portrait:
            return .portrait
        case .unlocked:
            return .all
        }
    }

    private var autoModeMask: UIInterfaceOrientationMask {
        guard let ratio = videoAspectRatio, ratio > 0 else { return .all }
        if ratio > (1 / squareAspectThreshold) && ratio < squareAspectThreshold {
            // Square-ish video: let the system rotate freely, matching
            // mpv-android's identical "let Android do what it wants"
            // fallback for this same case.
            return .all
        }
        return ratio > 1 ? .landscape : .portrait
    }

    /// Cycles landscape <-> portrait, matching mpv-android's
    /// `cycleOrientation()` exactly (a two-state toggle, not a
    /// three/four-state cycle through every `Mode` case — mpv-android's
    /// own cycling button only ever flips between its two locked
    /// states, leaving `auto`/unspecified reachable only via the
    /// settings screen, not the cycle button).
    func cycleOrientation() {
        mode = (mode == .landscape) ? .portrait : .landscape
        applyChange()
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        applyChange()
    }

    /// Called from `PlayerViewModel` whenever `video-params/w`/`/h`
    /// change (i.e. on file load, and if a video track switch changes
    /// dimensions) — mirrors mpv-android's `updateOrientation()` being
    /// invoked from its own video-reconfig handling.
    func updateVideoAspectRatio(width: Int64?, height: Int64?) {
        guard let width, let height, height > 0 else {
            videoAspectRatio = nil
            return
        }
        videoAspectRatio = Double(width) / Double(height)
        if mode == .auto {
            applyChange()
        }
    }

    /// Pushes the current `currentMask` to the system. iOS 16's
    /// `UIWindowScene.requestGeometryUpdate(_:errorHandler:)` plus
    /// `UIViewController.setNeedsUpdateOfSupportedInterfaceOrientations()`
    /// together are the only combination confirmed (via Apple's own
    /// developer forums discussing this exact API) to reliably apply an
    /// orientation-lock change at runtime on iOS 16+ — the older
    /// `supportedInterfaceOrientationsForWindow:`-only approach is
    /// separately reported as broken specifically on iOS 16 (not
    /// applying the lock until some other rotation event happens to
    /// trigger a re-check).
    private func applyChange() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: currentMask)) { error in
            // Not a fatal error worth surfacing to the user: worst case,
            // the orientation simply doesn't change until the next
            // rotation-eligible event, matching this feature's own
            // "best-effort" character elsewhere (mpv-android's
            // equivalent has no error path here either — Android's
            // requestedOrientation setter has no failure mode to
            // report).
            #if DEBUG
            print("OrientationLockController: geometry update failed: \(error)")
            #endif
        }

        if let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
