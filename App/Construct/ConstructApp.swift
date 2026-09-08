import SwiftUI
import ConstructCore

/// App entry point. Owns the root `AppEnvironment` and injects it into the
/// SwiftUI environment.
@main
struct ConstructApp: App {
    @State private var env = AppEnvironment()
    @State private var booted = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .task {
                    guard !booted else { return }
                    booted = true
                    appDelegate.env = env
                    await env.bootstrap()
                }
                .frame(minWidth: 960, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(env)
        }
    }
}

/// Stops the bundled brain sidecar on quit so it doesn't outlive the app and
/// hold its loopback port against the next launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var env: AppEnvironment?
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { env?.brain.stop() }
    }
}
