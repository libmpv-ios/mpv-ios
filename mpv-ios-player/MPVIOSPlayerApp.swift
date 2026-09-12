import SwiftUI

@main
struct MPVIOSPlayerApp: App {
    // Required only for orientation locking — see AppDelegate.swift's
    // own doc comment for why SwiftUI's App protocol alone can't
    // provide `application(_:supportedInterfaceOrientationsFor:)`.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MPVRootView()
        }
    }
}
