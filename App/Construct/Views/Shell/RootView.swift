import SwiftUI
import ConstructCore

/// Top-level gate: shows login when unauthenticated, the main shell otherwise.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var devPreview = false
    @State private var lock = BiometricLock()

    var body: some View {
        Group {
            if env.auth.isAuthenticated || devPreview {
                MainWindow()
            } else {
                LoginView(devPreview: $devPreview)
            }
        }
        .animation(.default, value: env.auth.isAuthenticated)
        .animation(.default, value: devPreview)
        // Biometric gate: obscure the app until Touch ID unlocks it.
        .overlay {
            if lock.locked && (env.auth.isAuthenticated || devPreview) {
                BiometricLockView(lock: lock).transition(.opacity)
            }
        }
        .animation(.default, value: lock.locked)
    }
}
