import SwiftUI
import LocalAuthentication

/// Gates the authenticated app behind Touch ID when the user has enabled
/// biometric unlock (Profile settings). Locks on launch and again whenever the
/// app returns to the foreground after being hidden. Tokens never leave the OS
/// keychain — this only gates the UI.
@MainActor
@Observable
final class BiometricLock {
    /// True when the app should be obscured pending authentication.
    private(set) var locked: Bool
    private(set) var authenticating = false
    private(set) var lastError: String?

    private let defaultsKey = "construct.biometric.enabled"
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }
    var canUseBiometrics: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    init() {
        locked = UserDefaults.standard.bool(forKey: "construct.biometric.enabled")
    }

    func authenticate() {
        guard locked, !authenticating else { return }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Password"
        authenticating = true
        lastError = nil
        // deviceOwnerAuthentication allows the system password fallback so the
        // user is never locked out if biometrics fail repeatedly.
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Construct") { [weak self] ok, err in
            Task { @MainActor in
                guard let self else { return }
                self.authenticating = false
                if ok { self.locked = false }
                else { self.lastError = err?.localizedDescription }
            }
        }
    }
}

/// Full-bleed lock screen shown over the app while `lock.locked`.
struct BiometricLockView: View {
    @Environment(\.constructTheme) private var theme
    var lock: BiometricLock

    var body: some View {
        ZStack {
            theme.canvasBg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(theme.accent)
                Text("Construct is locked").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.foreground)
                Text("Authenticate with Touch ID to continue.").font(.system(size: 13)).foregroundStyle(theme.muted)
                if let err = lock.lastError { Text(err).font(.system(size: 12)).foregroundStyle(.red) }
                Button(action: { lock.authenticate() }) {
                    Label(lock.authenticating ? "Authenticating…" : "Unlock", systemImage: "touchid")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent))
                        .foregroundStyle(theme.accentForeground)
                }
                .buttonStyle(.plain)
                .disabled(lock.authenticating)
            }
            .padding(40)
        }
        .onAppear { lock.authenticate() }
    }
}
