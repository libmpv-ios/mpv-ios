import SwiftUI

@main
struct MPVIOSPlayerApp: App {
    // Required only for orientation locking — see AppDelegate.swift's
    // own doc comment for why SwiftUI's App protocol alone can't
    // provide `application(_:supportedInterfaceOrientationsFor:)`.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        setupInitialEnvironment()
    }

    private func setupInitialEnvironment() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let scriptsDir = docs.appendingPathComponent("scripts")
        let mpvConf = docs.appendingPathComponent("mpv.conf")

        try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)


        if !FileManager.default.fileExists(atPath: mpvConf.path) {
            let defaultConf = """
            # mpv-ios configuration file
            # Options set here are automatically loaded on startup.
            """
            try? defaultConf.write(to: mpvConf, atomically: true, encoding: .utf8)
        }
    }

    var body: some Scene {
        WindowGroup {
            MPVRootView()
        }
    }
}
