import UIKit

/// Exists for exactly one reason: orientation locking.
///
/// SwiftUI's `App` protocol has no equivalent of
/// `application(_:supportedInterfaceOrientationsFor:)` — that callback is
/// only ever asked of a `UIApplicationDelegate`, confirmed while
/// researching this feature (multiple independent sources, including
/// Apple's own developer forums, describe going through an app delegate
/// as the only working approach; attempting to set orientation-lock
/// state via KVC on `UIWindowScene`/`UIViewController` directly — code
/// like `windowScene?.effectiveGeometry.setValue(true, forKey:
/// "isInterfaceOrientationLocked")` — reliably crashes with "this class
/// is not key value coding-compliant for the key ...", not a
/// theoretical risk but a specifically documented failure mode).
///
/// `OrientationLockController.currentMask` is the single source of
/// truth this delegate method reads — `PlayerViewModel`/`MPVPlayerView`
/// never touch `AppDelegate` directly, only
/// `OrientationLockController.shared`, keeping the orientation-lock
/// feature's actual logic out of this thin UIKit bridge.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLockController.shared.currentMask
    }
}
