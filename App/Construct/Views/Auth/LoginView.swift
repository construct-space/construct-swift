import SwiftUI
import ConstructCore

/// Sign-in screen. Port of the auth pages. Password login for now; OAuth /
/// biometric unlock to follow.
struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    var devPreview: Binding<Bool>? = nil

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsTwoFactor = false
    @State private var pendingToken = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Construct")
                .font(.largeTitle.bold())
            Text("Sign in to continue")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                if needsTwoFactor {
                    TextField("2FA code", text: $code)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 320)
            }

            Button(action: signIn) {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign In").frame(maxWidth: 320)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || email.isEmpty || password.isEmpty)

            #if DEBUG
            if let devPreview {
                Button("Developer: Preview installed spaces") {
                    devPreview.wrappedValue = true
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            #endif
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func signIn() {
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            let outcome = needsTwoFactor
                ? await env.submitTwoFactor(pendingToken: pendingToken, code: code)
                : await env.login(email: email, password: password)
            switch outcome {
            case .success:
                break // RootView swaps to MainWindow on isAuthenticated.
            case let .needsTwoFactor(token):
                needsTwoFactor = true
                pendingToken = token
            case .mustChangePassword:
                error = "Password reset required. Please reset it on the web."
            case let .failed(message):
                error = message
            }
        }
    }
}
