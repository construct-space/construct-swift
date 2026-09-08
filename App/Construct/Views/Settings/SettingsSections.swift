import SwiftUI
import LocalAuthentication
import ConstructCore

// MARK: - Shared building blocks

/// A settings row: heading + description on the left, a trailing control.
struct SettingsRow<Trailing: View>: View {
    @Environment(\.constructTheme) private var theme
    let title: String
    let description: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased() + ".").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.foreground)
                Text(description).font(.system(size: 13)).foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 14)
    }
}

/// A pill button (filled/tinted), matching the settings actions.
struct PillButton: View {
    @Environment(\.constructTheme) private var theme
    let title: String
    var tint: Color? = nil
    var filled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(filled ? .white : (tint ?? theme.foreground))
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(filled ? (tint ?? theme.accent) : (tint ?? theme.foreground).opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Account / Profile

struct ProfileSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @State private var tvCode = ""
    @State private var biometricEnabled = UserDefaults.standard.bool(forKey: "construct.biometric.enabled")

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" }
    }
    private var firstName: String {
        (env.auth.user?.name?.split(separator: " ").first).map(String.init) ?? "there"
    }
    private var biometricAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting).font(.system(size: 15)).foregroundStyle(theme.muted)
                    (Text(firstName).foregroundStyle(theme.foreground) + Text(".").foregroundStyle(theme.accent))
                        .font(.system(size: 26, weight: .bold))
                    Text(env.auth.user?.email ?? "").font(.system(size: 13)).foregroundStyle(theme.muted)
                    Text("Update your profile, password, and security settings on my.construct.space")
                        .font(.system(size: 13)).foregroundStyle(theme.muted).padding(.top, 8)
                }
                Spacer()
                PillButton(title: "Open Account Portal") { open("https://my.construct.space/settings") }
            }
            .padding(.vertical, 16)

            Divider().overlay(theme.border)

            SettingsRow(title: "Biometric Unlock",
                        description: "Require Touch ID / Windows Hello to unlock Construct on launch. Your tokens stay in the OS keychain.") {
                if biometricAvailable {
                    PillButton(title: biometricEnabled ? "Enabled" : "Enable", tint: theme.accent, filled: biometricEnabled) {
                        toggleBiometric()
                    }
                } else {
                    Text("UNAVAILABLE").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted)
                }
            }
            Divider().overlay(theme.border)

            SettingsRow(title: "Link a TV",
                        description: "Open Construct TV on your television, then enter the code it shows to sign that TV into your account.") {
                EmptyView()
            }
            HStack(spacing: 10) {
                TextField("XXXX-XXXX", text: $tvCode)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
                PillButton(title: "Link TV", tint: theme.accent, filled: true) { /* wire to source-api */ }
                    .disabled(tvCode.isEmpty)
            }
            .padding(.bottom, 8)

            HStack {
                Rectangle().fill(theme.border).frame(height: 1)
                Text("DANGER ZONE").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent).padding(.horizontal, 8)
                Rectangle().fill(theme.border).frame(height: 1)
            }
            .padding(.vertical, 20)

            SettingsRow(title: "Delete Account",
                        description: "Permanently delete your account and all associated data. This action cannot be undone.") {
                // Destructive + irreversible: per policy, direct to the web portal.
                PillButton(title: "Delete Account", tint: .red) { open("https://my.construct.space/settings") }
            }
        }
    }

    private func toggleBiometric() {
        if biometricEnabled {
            biometricEnabled = false
            UserDefaults.standard.set(false, forKey: "construct.biometric.enabled")
            return
        }
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable biometric unlock for Construct") { ok, _ in
            DispatchQueue.main.async {
                if ok { biometricEnabled = true; UserDefaults.standard.set(true, forKey: "construct.biometric.enabled") }
            }
        }
    }

    private func open(_ url: String) {
        #if os(macOS)
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        #endif
    }
}

// MARK: - General / Appearance

struct AppearanceSettings: View {
    @Environment(\.constructTheme) private var theme
    var themeStore: ThemeStore?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeading("Theme", "Pick a theme for the Construct chrome. It applies instantly and is remembered.")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ConstructThemes.all, id: \.id) { t in
                    ThemeSwatch(theme: t, selected: t.id == themeStore?.current.id) {
                        themeStore?.select(id: t.id)
                    }
                }
            }
        }
    }
}

private struct ThemeSwatch: View {
    @Environment(\.constructTheme) private var current
    let theme: ConstructTheme
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(theme.background).frame(height: 56)
                    HStack(spacing: 4) {
                        Circle().fill(theme.accent).frame(width: 12, height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(theme.foreground.opacity(0.8)).frame(width: 30, height: 6)
                    }.padding(8)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? current.accent : current.border, lineWidth: selected ? 2 : 1))
                HStack(spacing: 4) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(current.accent).font(.system(size: 12)) }
                    Text(theme.name).font(.system(size: 12, weight: selected ? .semibold : .regular)).foregroundStyle(current.foreground)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Account / Notifications

struct NotificationsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @AppStorage("construct.notify.desktop") private var desktop = true
    @AppStorage("construct.notify.sound") private var sound = true
    @AppStorage("construct.notify.mentions") private var mentions = true

    private var authLabel: String {
        switch env.notifications.authorization {
        case .authorized: return "ALLOWED"
        case .denied: return "DENIED"
        case .provisional: return "PROVISIONAL"
        case .notDetermined: return "NOT REQUESTED"
        }
    }
    private var authColor: Color {
        switch env.notifications.authorization {
        case .authorized, .provisional: return .green
        case .denied: return .red
        case .notDetermined: return theme.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsHeading("Notifications", "Control how Construct notifies you.")
                .padding(.bottom, 8)

            SettingsRow(title: "System notifications",
                        description: "Allow Construct to post native macOS notifications for operator alerts and reminders.") {
                HStack(spacing: 10) {
                    Text(authLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(authColor)
                    if env.notifications.authorization == .notDetermined {
                        PillButton(title: "Allow", tint: theme.accent, filled: true) {
                            Task { await env.notifications.requestAuthorization() }
                        }
                    } else if env.notifications.authorization == .denied {
                        PillButton(title: "Open Settings", tint: theme.accent) {
                            #if os(macOS)
                            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(u) }
                            #endif
                        }
                    } else {
                        PillButton(title: "Send test", tint: theme.accent) {
                            Task { await env.notifications.post(title: "Construct", body: "Notifications are working.", sound: sound) }
                        }
                    }
                }
            }
            Divider().overlay(theme.border).padding(.vertical, 6)

            Toggle("Desktop notifications", isOn: $desktop)
            Toggle("Play sound", isOn: $sound)
            Toggle("Only mentions & direct messages", isOn: $mentions)
        }
        .toggleStyle(.switch)
        .tint(theme.accent)
        .task { await env.notifications.refresh() }
    }
}

// MARK: - Organization lists (members / roles / departments)

struct OrgListSettings: View {
    enum Kind { case members, roles, departments, invitations, activity }
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    let kind: Kind

    @State private var rows: [[String: AnyJSON]] = []
    @State private var loading = true
    @State private var error: String?

    private var path: String {
        switch kind {
        case .members: "/api/source/org/members"
        case .roles: "/api/source/org/roles"
        case .departments: "/api/source/org/departments"
        case .invitations: "/api/source/org/invites"
        case .activity: "/api/source/org/activity"
        }
    }
    private var heading: String {
        switch kind {
        case .members: "Members"; case .roles: "Roles"; case .departments: "Departments"
        case .invitations: "Invitations"; case .activity: "Activity"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeading(heading, "Org \(heading.lowercased()) from your Construct organization.")
            if loading {
                ProgressView().padding(.top, 12)
            } else if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(theme.muted)
            } else if rows.isEmpty {
                Text("No \(heading.lowercased()) found (you may not be in an organization).")
                    .font(.system(size: 13)).foregroundStyle(theme.muted)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row["name"]?.string ?? row["email"]?.string ?? row["action"]?.string
                             ?? row["message"]?.string ?? row["type"]?.string ?? row["id"]?.string ?? "—")
                            .font(.system(size: 13)).foregroundStyle(theme.foreground).lineLimit(1)
                        Spacer()
                        if let meta = row["role"]?.string ?? row["status"]?.string ?? row["created_at"]?.string {
                            Text(meta).font(.system(size: 11)).foregroundStyle(theme.muted)
                        }
                    }
                    .padding(.vertical, 8)
                    Divider().overlay(theme.border)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            rows = try await env.api.request(.get, env.config.gateway.appendingPathComponent(String(path.dropFirst())))
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - Scaffold for not-yet-built sections

struct ScaffoldSettings: View {
    @Environment(\.constructTheme) private var theme
    let section: SettingsSection
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeading(section.title, description(for: section))
            PillButton(title: "Manage on my.construct.space") {
                #if os(macOS)
                if let u = URL(string: "https://my.construct.space/settings") { NSWorkspace.shared.open(u) }
                #endif
            }
            .padding(.top, 4)
        }
    }

    private func description(for s: SettingsSection) -> String {
        switch s {
        case .organization: return "Your organization's name, branding, and policies."
        case .spaces: return "Manage which spaces are available across your organization."
        case .invitations: return "Invite people to your organization and track pending invites."
        case .activity: return "Recent activity across your organization."
        case .orgDeveloper, .developer: return "Developer settings: API keys, publisher credentials, and space publishing."
        case .privacy: return "Privacy and data-residency preferences."
        case .system: return "System preferences: data directory, dependencies, and updates."
        case .insights: return "Usage insights and analytics."
        case .providers: return "AI model providers and credentials."
        case .skills: return "Reusable agent skills."
        case .memory: return "Long-term memory the operator can read and write."
        case .automations: return "Always-on automations and scheduled tasks."
        case .hooks: return "Lifecycle hooks that run on events."
        default: return "Configure \(s.title.lowercased())."
        }
    }
}

/// Minimal JSON value for decoding heterogeneous org rows.
enum AnyJSON: Decodable {
    case string(String), number(Double), bool(Bool), object([String: AnyJSON]), array([AnyJSON]), null
    var string: String? {
        switch self { case let .string(s): s; case let .number(n): String(n); default: nil }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([AnyJSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: AnyJSON].self) { self = .object(o) }
        else { self = .null }
    }
}
