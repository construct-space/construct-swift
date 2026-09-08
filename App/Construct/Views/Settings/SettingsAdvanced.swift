import SwiftUI
import ConstructCore

// MARK: - System

struct SystemSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
    private var memoryGB: String {
        String(format: "%.1f GB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeading("System", "Runtime, services, and where Construct stores data.")
                .padding(.bottom, 12)

            group("Services") {
                statusRow("Brain (AI engine)", running: false, note: "bundled sidecar — not yet ported")
                statusRow("Desktop Bridge", running: false, note: "automation bridge — not yet ported")
            }
            group("System Info") {
                kv("Version", appVersion)
                kv("OS", ProcessInfo.processInfo.operatingSystemVersionString)
                kv("Architecture", machineArch())
                kv("Hostname", ProcessInfo.processInfo.hostName)
                kv("Locale", Locale.current.identifier)
                kv("Memory", memoryGB)
            }
            group("Storage") {
                kv("Data directory", env.paths.base.path)
                kv("Active profile", env.profiles.activeProfileId)
            }
        }
    }

    @ViewBuilder private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted)
            .padding(.top, 16).padding(.bottom, 6)
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(theme.muted); Spacer(); Text(v).foregroundStyle(theme.foreground).textSelection(.enabled) }
            .font(.system(size: 12))
            .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func statusRow(_ name: String, running: Bool, note: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(running ? .green : theme.muted).frame(width: 8, height: 8)
            Text(name).font(.system(size: 12)).foregroundStyle(theme.foreground)
            Spacer()
            Text(running ? "Running" : note).font(.system(size: 11)).foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func machineArch() -> String {
        var sysinfo = utsname(); uname(&sysinfo)
        let arch = withUnsafeBytes(of: &sysinfo.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return arch
    }
}

// MARK: - Privacy

struct PrivacySettings: View {
    @Environment(\.constructTheme) private var theme
    @AppStorage("construct.telemetry.consent") private var analyticsEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHeading("Privacy", "Control what Construct collects.")
            SettingsRow(title: "Usage Analytics",
                        description: "Help improve Construct by sharing anonymous usage data. No personal information is collected.") {
                Toggle("", isOn: $analyticsEnabled).labelsHidden().toggleStyle(.switch).tint(theme.accent)
            }
            Divider().overlay(theme.border)
            SettingsRow(title: "Data Residency",
                        description: "Where your data is stored. Managed by your organization's policy on my.construct.space.") {
                EmptyView()
            }
        }
    }
}

// MARK: - Developer (runtime detection + version + projects)

struct DeveloperSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @State private var runtimes: [(name: String, cmd: String, version: String?)] = []
    @State private var checking = true

    private let probes: [(String, String, [String])] = [
        ("Bun", "bun", ["--version"]),
        ("Node", "node", ["--version"]),
        ("Git", "git", ["--version"]),
        ("Rust", "rustc", ["--version"]),
        ("Cargo", "cargo", ["--version"]),
        ("Go", "go", ["version"]),
        ("Construct CLI", "construct", ["--version"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHeading("Developer", "Local toolchain and developer access.")

            Text("ENVIRONMENT").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted).padding(.top, 6)
            VStack(spacing: 0) {
                if checking {
                    HStack { ProgressView().controlSize(.small); Text("Detecting runtimes…").foregroundStyle(theme.muted).font(.system(size: 12)) }
                        .padding(12)
                } else {
                    ForEach(Array(runtimes.enumerated()), id: \.offset) { _, r in
                        HStack(spacing: 8) {
                            Circle().fill(r.version != nil ? .green : theme.muted).frame(width: 8, height: 8)
                            Text(r.name).font(.system(size: 12)).foregroundStyle(theme.foreground)
                            Spacer()
                            Text(r.version ?? "not installed")
                                .font(.system(size: 11)).foregroundStyle(theme.muted)
                                .lineLimit(1).textSelection(.enabled)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))

            SettingsRow(title: "Developer Access",
                        description: env.auth.isDeveloper ? "You're enrolled as a developer." : "Enroll to publish spaces and use developer tools.") {
                if env.auth.isDeveloper {
                    Text("ENROLLED").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                } else {
                    PillButton(title: "Manage on Portal", tint: theme.accent) { open("https://my.construct.space/developer") }
                }
            }
        }
        .task { await detect() }
    }

    private func detect() async {
        checking = true
        var found: [(String, String, String?)] = []
        for (name, cmd, args) in probes {
            let v = await Self.run(cmd, args)
            found.append((name, cmd, v))
        }
        runtimes = found
        checking = false
    }

    /// Runs `cmd args` via a login shell (to pick up PATH) and returns the first line.
    private static func run(_ cmd: String, _ args: [String]) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", "\(cmd) \(args.joined(separator: " ")) 2>/dev/null"]
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
                do { try p.run() } catch { cont.resume(returning: nil); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus == 0, !data.isEmpty,
                      let s = String(data: data, encoding: .utf8)?.split(separator: "\n").first
                else { cont.resume(returning: nil); return }
                cont.resume(returning: String(s).trimmingCharacters(in: .whitespaces))
            }
        }
    }

    private func open(_ url: String) {
        #if os(macOS)
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        #endif
    }
}

// MARK: - Organization

struct OrganizationSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @State private var createName = ""
    @State private var joinCode = ""

    private var org: Organization? { env.auth.scope.org }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let org {
                SettingsHeading(org.name, "Your active organization.")
                HStack {
                    Text("ACTIVE").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                    Spacer()
                    PillButton(title: "Manage on Portal", tint: theme.accent) { open("https://my.construct.space/org") }
                }
                Divider().overlay(theme.border)
                OrgCountsRow()
            } else {
                SettingsHeading("Organization", "Create or join an organization to collaborate with your team.")
                form("Create Organization", placeholder: "Organization name", text: $createName, button: "Create") {
                    // POST /api/source/org/enable {name}
                }
                form("Join Organization", placeholder: "Invite code", text: $joinCode, button: "Join") {
                    // POST /api/source/org/invites/{code}/accept
                }
                Text("Org creation/join is handled on my.construct.space for now.")
                    .font(.system(size: 12)).foregroundStyle(theme.muted)
            }
        }
    }

    @ViewBuilder private func form(_ title: String, placeholder: String, text: Binding<String>, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
            HStack {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain).padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
                PillButton(title: button, tint: theme.accent, filled: true) { open("https://my.construct.space/org") }
            }
        }
    }

    private func open(_ url: String) {
        #if os(macOS)
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        #endif
    }
}

/// Live member/department/team counts for the active org.
private struct OrgCountsRow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @State private var counts: [(String, Int)] = []

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(counts.enumerated()), id: \.offset) { _, c in
                VStack(spacing: 2) {
                    Text("\(c.1)").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.foreground)
                    Text(c.0).font(.system(size: 11)).foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
            }
            if counts.isEmpty { ProgressView().controlSize(.small) }
        }
        .task { await load() }
    }

    private func load() async {
        func count(_ path: String) async -> Int {
            (try? await env.api.request(.get, env.config.gateway.appendingPathComponent(path)) as [AnyJSON])?.count ?? 0
        }
        async let m = count("api/source/org/members")
        async let d = count("api/source/org/departments")
        async let t = count("api/source/org/teams")
        counts = [("Members", await m), ("Departments", await d), ("Teams", await t)]
    }
}

// MARK: - Brain/operator-backed scaffold

