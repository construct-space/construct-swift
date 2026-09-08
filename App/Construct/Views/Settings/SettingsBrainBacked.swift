import SwiftUI
import ConstructCore

// MARK: - Insights (brain `insights.overview`)

/// AI usage analytics, backed by the operator's `insights.overview` wire op.
/// Port of the Tauri `InsightsSettings.vue`.
struct InsightsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    struct AgentUsage: Decodable, Identifiable {
        let agent_id: String, sessions: Int, turns: Int, cost_usd: Double
        var id: String { agent_id }
    }
    struct SessionRecord: Decodable, Identifiable {
        let id: String, agent_id: String, turns: Int, cost_usd: Double
        let duration_secs: Double?, stop_reason: String?
    }
    struct Overview: Decodable {
        let total_sessions: Int, total_turns: Int, total_tokens: Int, total_cost_usd: Double
        let avg_turns_per_session: Double, avg_cost_per_session: Double
        let top_agents: [AgentUsage]?
        let recent_sessions: [SessionRecord]?
    }

    @State private var stats: Overview?
    @State private var loading = false
    @State private var days = 30
    private let ranges = [(7, "Last 7 days"), (30, "Last 30 days"), (90, "Last 90 days")]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SettingsHeading("Insights", "Sessions, tokens, and cost across your agents.")
                Spacer()
                Picker("", selection: $days) {
                    ForEach(ranges, id: \.0) { Text($0.1).tag($0.0) }
                }.labelsHidden().fixedSize()
            }

            if !env.brain.status.isRunning {
                BrainOfflineNotice(status: env.brain.status)
            } else if loading && stats == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if let s = stats {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    statCard("Sessions", "\(s.total_sessions)", "waveform.path.ecg")
                    statCard("Turns", "\(s.total_turns)", "arrow.triangle.2.circlepath")
                    statCard("Tokens", formatTokens(s.total_tokens), "number")
                    statCard("Cost", formatCost(s.total_cost_usd), "dollarsign.circle")
                }

                if let agents = s.top_agents, !agents.isEmpty {
                    Text("TOP AGENTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted).padding(.top, 6)
                    ForEach(agents) { a in
                        HStack {
                            Text(a.agent_id).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.foreground)
                            Spacer()
                            Text("\(a.sessions) sessions · \(a.turns) turns").font(.system(size: 11)).foregroundStyle(theme.muted)
                            Text(formatCost(a.cost_usd)).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
                        }
                        .padding(.vertical, 8)
                        Divider().overlay(theme.border)
                    }
                }

                if let recent = s.recent_sessions, !recent.isEmpty {
                    Text("RECENT SESSIONS").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted).padding(.top, 6)
                    ForEach(recent.prefix(10)) { r in
                        HStack {
                            Text(r.agent_id).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.foreground)
                            Spacer()
                            Text("\(r.turns) turns").font(.system(size: 11)).foregroundStyle(theme.muted)
                            if let reason = r.stop_reason { Text(reason).font(.system(size: 10)).foregroundStyle(theme.muted) }
                            Text(formatCost(r.cost_usd)).font(.system(size: 11)).foregroundStyle(theme.accent)
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(theme.border)
                    }
                }
            } else {
                Text("No usage recorded yet. Insights appear once agents run sessions.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted).padding(.top, 8)
            }
        }
        .task(id: days) { await load() }
    }

    private func statCard(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(theme.accent)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(theme.foreground)
            Text(label).font(.system(size: 11)).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.inputBg))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
    }

    private func load() async {
        guard env.brain.status.isRunning else { return }
        loading = true; defer { loading = false }
        struct Req: Encodable { let days: Int }
        stats = try? await env.brain.request("insights.overview", payload: Req(days: days)) as Overview
    }

    private func formatCost(_ usd: Double) -> String { usd < 0.01 ? "<$0.01" : String(format: "$%.2f", usd) }
    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }
}

// MARK: - Automations (Conductor control plane)

/// Natural-language scheduled automations, backed by the Conductor control
/// plane (`{conductor}/api/automations`). Port of `AutomationsSettings.vue`.
struct AutomationsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    struct Automation: Codable, Identifiable {
        let id: String
        var instruction: String
        var interval_min: Int
        var enabled: Bool
        var last_run_at: Double?
        var last_result: String?
    }

    @State private var rules: [Automation] = []
    @State private var loading = false
    @State private var error: String?
    @State private var draft = ""
    @State private var draftInterval = 15
    @State private var saving = false
    @State private var pendingDelete: Automation?
    private let intervals = [5, 15, 30, 60, 180, 720, 1440]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeading("Automations", "Always-on rules. An English instruction runs on a schedule with your space tools.")

            // New-rule composer.
            VStack(alignment: .leading, spacing: 8) {
                TextField("e.g. When I get a meeting invite, add it to my calendar", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
                HStack {
                    Picker("Every", selection: $draftInterval) {
                        ForEach(intervals, id: \.self) { Text(intervalLabel($0)).tag($0) }
                    }.fixedSize()
                    Spacer()
                    PillButton(title: saving ? "Adding…" : "Add automation", tint: theme.accent, filled: true) {
                        Task { await add() }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))

            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }

            if loading && rules.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if rules.isEmpty {
                Text("No automations yet. Add one above — it runs even when the app is closed.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted).padding(.top, 8)
            } else {
                ForEach(rules) { rule in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(get: { rule.enabled }, set: { _ in Task { await toggle(rule) } }))
                            .labelsHidden().toggleStyle(.switch)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.instruction).font(.system(size: 13)).foregroundStyle(theme.foreground)
                            HStack(spacing: 8) {
                                Label(intervalLabel(rule.interval_min), systemImage: "clock").font(.system(size: 11)).foregroundStyle(theme.muted)
                                if let r = rule.last_result, !r.isEmpty {
                                    Text("· \(r)").font(.system(size: 11)).foregroundStyle(theme.muted).lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                        Button { Task { await runNow(rule) } } label: {
                            Image(systemName: "play.circle").foregroundStyle(theme.accent)
                        }.buttonStyle(.plain).help("Run now")
                        Button { pendingDelete = rule } label: {
                            Image(systemName: "trash").foregroundStyle(.red).font(.system(size: 12))
                        }.buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                    Divider().overlay(theme.border)
                }
            }
        }
        .task { await load() }
        .confirmationDialog("Delete this automation?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let r = pendingDelete { Task { await remove(r) } } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func intervalLabel(_ m: Int) -> String {
        if m >= 1440 { return "Every \(m / 1440)d" }
        if m >= 60 { return "Every \(m / 60)h" }
        return "Every \(m)m"
    }

    // MARK: Conductor HTTP

    private func conductorRequest(_ path: String, method: String, body: Encodable? = nil) async throws -> Data {
        var req = URLRequest(url: env.config.conductor.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = env.auth.currentAccessToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "conductor", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Conductor HTTP \(http.statusCode)"])
        }
        return data
    }

    private func load(quiet: Bool = false) async {
        if !quiet { loading = true; error = nil }
        defer { if !quiet { loading = false } }
        do {
            let data = try await conductorRequest("api/automations", method: "GET")
            struct Resp: Decodable { let automations: [Automation]? }
            rules = (try JSONDecoder().decode(Resp.self, from: data)).automations ?? []
        } catch { if !quiet { self.error = error.localizedDescription } }
    }

    private func add() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        saving = true; error = nil; defer { saving = false }
        struct New: Encodable { let instruction: String; let interval_min: Int; let enabled: Bool }
        do {
            _ = try await conductorRequest("api/automations", method: "POST",
                                           body: New(instruction: text, interval_min: draftInterval, enabled: true))
            draft = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func toggle(_ r: Automation) async {
        var updated = r; updated.enabled.toggle()
        do { _ = try await conductorRequest("api/automations", method: "POST", body: updated); await load(quiet: true) }
        catch { self.error = error.localizedDescription }
    }

    private func runNow(_ r: Automation) async {
        do { _ = try await conductorRequest("api/automations/\(r.id)/run", method: "POST"); await load(quiet: true) }
        catch { self.error = error.localizedDescription }
    }

    private func remove(_ r: Automation) async {
        pendingDelete = nil
        do { _ = try await conductorRequest("api/automations/\(r.id)", method: "DELETE"); await load() }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Hooks (brain `hooks.*`)

/// Lifecycle hooks that run on tool/session/file events, backed by the
/// operator's `hooks.*` wire ops. Port of `HooksSettings.vue`.
struct HooksSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    struct Hook: Decodable, Identifiable {
        let id: String, name: String, type: String
        let priority: Int?, description: String?, source: String?, enabled: Bool
    }

    @State private var hooks: [Hook] = []
    @State private var loading = false
    @State private var error: String?
    @State private var typeFilter = ""
    @State private var pendingDelete: Hook?
    private let types = [("", "All types"), ("pre_tool", "Pre-tool"), ("post_tool", "Post-tool"),
                        ("session", "Session"), ("file", "File changed")]

    private var filtered: [Hook] { typeFilter.isEmpty ? hooks : hooks.filter { $0.type.hasPrefix(typeFilter) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SettingsHeading("Hooks", "Run on tool, session, and file events to guard or extend the operator.")
                Spacer()
                Picker("", selection: $typeFilter) {
                    ForEach(types, id: \.0) { Text($0.1).tag($0.0) }
                }.labelsHidden().fixedSize()
                PillButton(title: "Refresh", tint: theme.accent) { Task { await load() } }
            }

            if !env.brain.status.isRunning {
                BrainOfflineNotice(status: env.brain.status)
            } else if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }

            if loading && hooks.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if env.brain.status.isRunning && filtered.isEmpty {
                Text("No hooks. Built-in hooks and skill hooks appear here; add your own from the desktop app.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted).padding(.top, 8)
            } else {
                ForEach(filtered) { hook in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(get: { hook.enabled }, set: { _ in Task { await toggle(hook) } }))
                            .labelsHidden().toggleStyle(.switch)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(hook.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
                                Text(hook.type).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.accent)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(theme.accent.opacity(0.12)))
                                if let src = hook.source, src != "user" {
                                    Text(src.uppercased()).font(.system(size: 9)).foregroundStyle(theme.muted)
                                }
                            }
                            if let d = hook.description, !d.isEmpty {
                                Text(d).font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(2)
                            }
                        }
                        Spacer()
                        if hook.source == "user" {
                            Button { pendingDelete = hook } label: {
                                Image(systemName: "trash").foregroundStyle(.red).font(.system(size: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 10)
                    Divider().overlay(theme.border)
                }
            }
        }
        .task { await load() }
        .confirmationDialog("Delete hook “\(pendingDelete?.name ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let h = pendingDelete { Task { await remove(h) } } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func load() async {
        guard env.brain.status.isRunning else { return }
        loading = true; error = nil; defer { loading = false }
        struct Resp: Decodable { let hooks: [Hook]? }
        do {
            let resp: Resp = try await env.brain.request("hooks.list")
            hooks = resp.hooks ?? []
        } catch { self.error = error.localizedDescription }
    }

    private func toggle(_ h: Hook) async {
        struct Req: Encodable { let id: String }
        do {
            let _: Empty = try await env.brain.request(h.enabled ? "hooks.disable" : "hooks.enable", payload: Req(id: h.id))
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ h: Hook) async {
        pendingDelete = nil
        struct Req: Encodable { let id: String }
        do {
            let _: Empty = try await env.brain.request("hooks.delete", payload: Req(id: h.id))
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private struct Empty: Decodable {}
}

// MARK: - Shared

/// Shown when an operator-backed page is opened but the brain isn't running.
struct BrainOfflineNotice: View {
    @Environment(\.constructTheme) private var theme
    let status: BrainService.Status
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu").foregroundStyle(theme.muted)
            Text(message).font(.system(size: 12)).foregroundStyle(theme.muted)
            if case .starting = status { ProgressView().controlSize(.small) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
    }
    private var message: String {
        switch status {
        case .starting: return "Starting the local operator…"
        case .failed(let m): return "Operator unavailable: \(m)"
        default: return "The local operator (brain) isn't running."
        }
    }
}

/// Type-erased Encodable so settings calls can pass heterogeneous payloads.
private struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
