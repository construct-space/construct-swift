import SwiftUI
import ConstructCore

// MARK: - Providers (full LLM settings: catalog + BYOK + OAuth + tier slots)

/// AI provider management, 1:1 with the Tauri LLMProviders page. Merges the
/// brain's rich catalog (`models.list` → models, capabilities, auth shapes)
/// with live connection state (`ai.providers`). Per provider: an API-key card
/// (`settings.set provider_key:<id>`), a Pro/Max OAuth card for monthly-enabled
/// providers (`oauth.login`/`poll`/`logout`), Large/Default/Small tier slots
/// (local, UserDefaults), and a capability-badged model grid.
struct ProvidersSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    @State private var providers: [MergedProvider] = []
    @State private var loading = false
    @State private var error: String?
    @State private var expanded: Set<String> = []
    @State private var drafts: [String: String] = [:]
    @State private var busy: Set<String> = []
    @State private var status: [String: String] = [:]
    @State private var tiers = TierStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsHeading("Providers", "AI model providers. Apple Intelligence runs free, on-device, and private.")

                appleSection

                Text("MODEL PROVIDERS").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted).padding(.top, 6)
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                if !env.brain.status.isRunning {
                    BrainOfflineNotice(status: env.brain.status)
                } else if loading && providers.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(providers) { providerCard($0) }
                }

                PillButton(title: "Manage on my.construct.space", tint: theme.accent) {
                    #if os(macOS)
                    if let u = URL(string: "https://my.construct.space/settings") { NSWorkspace.shared.open(u) }
                    #endif
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .onAppear { env.foundationModels.refreshAvailability(); tiers.load(profile: env.profiles.activeProfileId) }
        .task { await load() }
    }

    // MARK: Apple Intelligence

    private var appleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("APPLE INTELLIGENCE · FREE").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
            appleRow("On-device model", env.foundationModels.onDevice)
            appleRow("Private Cloud Compute", env.foundationModels.privateCloud)
        }
    }

    private func appleRow(_ name: String, _ a: FoundationModelService.Availability) -> some View {
        HStack {
            Image(systemName: "apple.logo").foregroundStyle(theme.foreground)
            Text(name).font(.system(size: 13)).foregroundStyle(theme.foreground)
            Spacer()
            Text(a.isAvailable ? "AVAILABLE" : a.label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(a.isAvailable ? .green : theme.muted)
        }
        .padding(.vertical, 9)
    }

    // MARK: Provider card

    @ViewBuilder
    private func providerCard(_ p: MergedProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header — the whole row toggles expansion.
            HStack(alignment: .top) {
                Image(systemName: p.icon).font(.system(size: 18)).foregroundStyle(p.connected ? theme.accent : theme.muted).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.foreground)
                    if let sub = p.subtitle { Text(sub).font(.system(size: 11)).foregroundStyle(theme.muted) }
                }
                Spacer()
                if busy.contains(p.id) { ProgressView().controlSize(.small) }
                if let s = status[p.id] { Text(s).font(.system(size: 11)).foregroundStyle(theme.muted) }
                Text(p.statusLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(p.statusColor(theme))
                if p.canExpand {
                    Image(systemName: expanded.contains(p.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11)).foregroundStyle(theme.muted)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if p.canExpand { toggle(p.id) } }

            if expanded.contains(p.id) {
                HStack(alignment: .top, spacing: 12) {
                    if p.supportsKey { apiKeyCard(p).frame(maxWidth: .infinity) }
                    if p.supportsOAuth { oauthCard(p).frame(maxWidth: .infinity) }
                }
                if !p.usableModels.isEmpty {
                    tierSlots(p)
                    modelGrid(p)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
    }

    private func apiKeyCard(_ p: MergedProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("API KEY", systemImage: "key").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.foreground)
            HStack(spacing: 8) {
                SecureField(p.keyPlaceholder, text: draftBinding(p.id))
                    .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
                PillButton(title: "Save", tint: theme.accent, filled: true) { Task { await saveKey(p) } }
                    .disabled((drafts[p.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                if let docs = p.docsURL {
                    Button("Get a key at \(docs.host ?? "the provider")") {
                        #if os(macOS)
                        NSWorkspace.shared.open(docs)
                        #endif
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.accent)
                }
                Spacer()
                if p.apiKeyPresent {
                    Button("Remove") { Task { await removeKey(p) } }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
    }

    private func oauthCard(_ p: MergedProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(p.oauthCardTitle, systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.foreground)
                Spacer()
                if p.oauthLinked {
                    PillButton(title: "Sign out", tint: .red) { Task { await logout(p) } }
                } else {
                    PillButton(title: "Sign in", tint: theme.accent, filled: true) { Task { await oauthLogin(p) } }
                }
            }
            if p.oauthLinked {
                HStack(spacing: 6) {
                    badge("SIGNED IN", .green)
                }
            } else {
                Text("Sign in with your subscription — opens your browser to authorize.")
                    .font(.system(size: 11)).foregroundStyle(theme.muted)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.oauthLinked ? theme.accent.opacity(0.5) : theme.border))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: Tier slots

    private func tierSlots(_ p: MergedProvider) -> some View {
        let models = p.usableModels
        let meta: [(Tier, String, String)] = [
            (.large, "Large", "Hard reasoning, frontier work. Opt-in."),
            (.medium, "Default", "User-visible chat. Standard tier."),
            (.small, "Small", "Cheap fast — summarisation, classification, internal calls."),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), alignment: .leading, spacing: 10) {
            ForEach(meta, id: \.0) { tier, label, desc in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                    Picker("", selection: tierBinding(p.id, tier)) {
                        Text("— pick a model —").tag("")
                        ForEach(models) { m in Text(m.name).tag(m.id) }
                    }.labelsHidden()
                    Text(desc).font(.system(size: 10)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 4)
    }

    private func modelGrid(_ p: MergedProvider) -> some View {
        let models = p.usableModels
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(models.count) / \(p.models.count) MODELS AVAILABLE")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted).padding(.top, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                ForEach(models) { m in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.name).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.foreground).lineLimit(1)
                        let caps = m.capabilities?.values ?? []
                        if !caps.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(caps.prefix(3), id: \.self) { cap in
                                    Text(cap.uppercased()).font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.muted)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Capsule().fill(theme.muted.opacity(0.12)))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
                }
            }
        }
    }

    // MARK: Bindings

    private func draftBinding(_ id: String) -> Binding<String> {
        Binding(get: { drafts[id] ?? "" }, set: { drafts[id] = $0 })
    }
    private func tierBinding(_ providerId: String, _ tier: Tier) -> Binding<String> {
        Binding(
            get: { tiers.get(providerId, tier) },
            set: { tiers.set(providerId, tier, $0, profile: env.profiles.activeProfileId) }
        )
    }
    private func toggle(_ id: String) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }

    // MARK: Brain ops

    private func load() async {
        guard env.brain.status.isRunning else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            async let catalogTask: Catalog = env.brain.request("models.list")
            async let stateTask: AIProvidersResp = env.brain.request("ai.providers")
            let catalog = try await catalogTask
            let state = (try? await stateTask) ?? AIProvidersResp(providers: nil)
            let stateById = Dictionary(uniqueKeysWithValues: (state.providers ?? []).map { ($0.id, $0) })
            providers = (catalog.data ?? []).map { MergedProvider(catalog: $0, state: stateById[$0.slug]) }
                .sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
        } catch { self.error = error.localizedDescription }
    }

    private struct Empty: Decodable {}

    private func saveKey(_ p: MergedProvider) async {
        let value = (drafts[p.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        await mutate(p.id) {
            struct Req: Encodable { let key: String; let value: String }
            let _: Empty = try await env.brain.request("settings.set", payload: Req(key: "provider_key:\(p.id)", value: value))
            drafts[p.id] = ""
        }
    }

    private func removeKey(_ p: MergedProvider) async {
        await mutate(p.id) {
            struct Req: Encodable { let key: String; let value: String }
            let _: Empty = try await env.brain.request("settings.set", payload: Req(key: "provider_key:\(p.id)", value: ""))
        }
    }

    private func logout(_ p: MergedProvider) async {
        let flow = p.oauthFlowId ?? p.id
        await mutate(p.id) {
            struct Req: Encodable { let provider: String }
            let _: Empty = try await env.brain.request("oauth.logout", payload: Req(provider: flow))
        }
    }

    /// Starts the brain PKCE flow (it opens the browser), polls until resolved,
    /// then refreshes. Sends the OAuth *flow id* ("claude", not "anthropic") so
    /// the brain stores creds under the key its connector reads — then the
    /// Anthropic provider injects the Claude Code system prompt + OAuth beta
    /// headers automatically, exactly as the Go version.
    private func oauthLogin(_ p: MergedProvider) async {
        let flow = p.oauthFlowId ?? p.id
        busy.insert(p.id); error = nil; status[p.id] = "Waiting for browser…"
        defer { busy.remove(p.id); status[p.id] = nil }
        struct Req: Encodable { let provider: String }
        do {
            let _: Empty = try await env.brain.request("oauth.login", payload: Req(provider: flow))
            struct Poll: Decodable { let status: String?; let success: Bool? }
            for _ in 0..<120 {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let poll: Poll = try await env.brain.request("oauth.poll", payload: Req(provider: flow))
                if poll.success == true || poll.status == "success" { break }
            }
            let _: Empty = try await env.brain.request("providers.refresh")
            await load()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func mutate(_ id: String, _ op: @escaping () async throws -> Void) async {
        busy.insert(id); error = nil; defer { busy.remove(id) }
        do {
            try await op()
            let _: Empty = try await env.brain.request("providers.refresh")
            await load()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - Wire shapes

/// Decodes capability lists that may be a string array or absent/other.
struct FlexStrings: Decodable, Hashable {
    let values: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        values = (try? c.decode([String].self)) ?? []
    }
    init() { values = [] }
}

/// `models.list` catalog snapshot (`{data:[...]}`).
struct Catalog: Decodable { let data: [CatalogProvider]? }

struct CatalogProvider: Decodable, Identifiable {
    let slug: String
    let name: String
    let api_key: CatalogAPIKey?
    let monthly: CatalogMonthly?
    let models: [CatalogModel]?
    var id: String { slug }
}
struct CatalogAPIKey: Decodable { let enabled: Bool?; let env_keys: [String]?; let has_shared_key: Bool? }
struct CatalogMonthly: Decodable { let enabled: Bool?; let auth_type: String? }
struct CatalogModel: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let capabilities: FlexStrings?
    let available_on_api_key: Bool?
    let available_on_monthly: Bool?
    let deprecated: Bool?
}

/// `ai.providers` connection state.
struct AIProvidersResp: Decodable { let providers: [AIProviderState]? }
struct AIProviderState: Decodable {
    let id: String
    let api_key_present: Bool?
    let oauth_linked: Bool?
    let connected: Bool?
}

/// A catalog provider merged with its live connection state, plus the
/// view-model helpers the card needs.
struct MergedProvider: Identifiable {
    let catalog: CatalogProvider
    let state: AIProviderState?
    var id: String { catalog.slug }
    var name: String { catalog.name }
    var models: [CatalogModel] { catalog.models ?? [] }
    var usableModels: [CatalogModel] {
        models.filter { !($0.deprecated ?? false) && (($0.available_on_api_key ?? false) || ($0.available_on_monthly ?? false)) }
    }
    var apiKeyPresent: Bool { state?.api_key_present ?? false }
    var oauthLinked: Bool { state?.oauth_linked ?? false }
    var hasSharedKey: Bool { catalog.api_key?.has_shared_key ?? false }
    var connected: Bool { state?.connected ?? (apiKeyPresent || oauthLinked || hasSharedKey) }
    var supportsKey: Bool { catalog.api_key?.enabled ?? false }
    var supportsOAuth: Bool { (catalog.monthly?.enabled ?? false) && oauthFlowId != nil }
    var canExpand: Bool { supportsKey || supportsOAuth || !usableModels.isEmpty }

    /// OAuth flow id ≠ catalog id (see SettingsProviders.oauthLogin).
    var oauthFlowId: String? {
        switch catalog.slug {
        case "anthropic", "claude": return "claude"
        case "openai", "openai-codex": return "openai-codex"
        default: return nil
        }
    }

    var subtitle: String? {
        // "Model A, Model B · vision · tools" — a few model names + union of caps.
        let names = usableModels.prefix(3).map { shortName($0.name) }
        let caps = Set(usableModels.flatMap { $0.capabilities?.values ?? [] })
            .intersection(["vision", "tools", "reasoning"])
            .sorted()
        var parts: [String] = []
        if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        if !caps.isEmpty { parts.append(caps.joined(separator: " · ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private func shortName(_ n: String) -> String {
        n.replacingOccurrences(of: "\(name) ", with: "").replacingOccurrences(of: name, with: "")
            .trimmingCharacters(in: .whitespaces).isEmpty ? n : n
    }

    var statusLabel: String {
        if oauthLinked { return "SIGNED IN" }
        if apiKeyPresent { return "CONNECTED" }
        if hasSharedKey { return "ORG KEY" }
        return "NOT SET UP"
    }
    func statusColor(_ t: ConstructTheme) -> Color {
        (oauthLinked || apiKeyPresent) ? .green : (hasSharedKey ? t.accent : t.muted)
    }

    var icon: String { "cpu" }
    var oauthCardTitle: String { catalog.slug == "anthropic" ? "Claude Pro/Max" : "Subscription" }
    var keyPlaceholder: String {
        switch catalog.slug {
        case "anthropic": return "sk-ant-…"
        case "openai": return "sk-…"
        default: return "Paste API key…"
        }
    }
    var docsURL: URL? {
        switch catalog.slug {
        case "anthropic": return URL(string: "https://console.anthropic.com")
        case "openai": return URL(string: "https://platform.openai.com/api-keys")
        case "google": return URL(string: "https://aistudio.google.com/apikey")
        case "deepseek": return URL(string: "https://platform.deepseek.com")
        default: return nil
        }
    }
}

// MARK: - Tier config (local, like the Tauri localStorage tierConfig)

enum Tier: String, CaseIterable, Hashable { case large, medium, small }

/// Per-provider Large/Default/Small model assignment, stored in UserDefaults
/// (render-only state — the Tauri app keeps this in localStorage). Keyed by
/// profile so switching profiles doesn't cross tiers.
@Observable
final class TierStore {
    private var map: [String: [String: String]] = [:]   // providerId -> {tier: modelId}
    private var key = "construct.tierConfig.v1"

    func load(profile: String) {
        key = "construct.tierConfig.v1.\(profile)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { map = [:]; return }
        map = decoded
    }
    func get(_ provider: String, _ tier: Tier) -> String { map[provider]?[tier.rawValue] ?? "" }
    func set(_ provider: String, _ tier: Tier, _ modelId: String, profile: String) {
        if key.hasSuffix(profile) == false { load(profile: profile) }
        map[provider, default: [:]][tier.rawValue] = modelId
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: key) }
    }
}
