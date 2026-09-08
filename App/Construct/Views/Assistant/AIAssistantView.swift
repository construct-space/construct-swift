import SwiftUI
import ConstructCore

/// A chat panel. Two engines:
/// - **On-device** — Apple's free Foundation Model. No key, no cost, private.
/// - **Operator** — the Go brain's agent loop (tools + provider routing),
///   streamed over `/v1/stream`. Available when the brain is running.
/// Opened from the toolbar ✦ button.
struct AIAssistantView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    /// The space the user currently has open, so operator tools target it.
    var activeSpaceId: String? = nil
    /// Bumped by right-⇧⇧ to cycle the model.
    var cycleModelSignal: Int = 0

    enum Engine: String, CaseIterable { case onDevice = "On-device", operatorBrain = "Operator" }

    /// A selectable operator model. `id` is the composite "provider:model"
    /// passed to the prompt op; empty means Auto (brain picks).
    struct ModelChoice: Identifiable, Hashable { let id: String; let label: String }

    struct Message: Identifiable { let id = UUID(); let role: Role; var text: String; var status: String?; enum Role { case user, assistant } }
    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var working = false
    @State private var error: String?
    @State private var engine: Engine = .onDevice
    @State private var streamTask: Task<Void, Never>?
    @State private var models: [ModelChoice] = [ModelChoice(id: "", label: "Auto")]
    @State private var selectedModel = ""   // composite id; "" = Auto
    private let modelDefaultsKey = "construct.assistant.model"

    private var fm: FoundationModelService { env.foundationModels }
    private var brainReady: Bool { env.brain.status.isRunning }
    /// Whether the active engine can take input right now.
    private var engineReady: Bool { engine == .operatorBrain ? brainReady : fm.anyAvailable }
    private var selectedModelLabel: String { models.first { $0.id == selectedModel }?.label ?? "Auto" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            enginePicker
            if engine == .operatorBrain { modelBar }
            Divider().overlay(theme.border)

            if !engineReady {
                unavailable
            } else {
                messagesList
                Divider().overlay(theme.border)
                composer
            }
        }
        .frame(width: 380)
        .background(theme.surface)
        .onAppear {
            fm.refreshAvailability()
            selectedModel = UserDefaults.standard.string(forKey: modelDefaultsKey) ?? ""
            // Prefer the richer operator engine when it's up.
            if brainReady { engine = .operatorBrain }
        }
        .task(id: brainReady) {
            if brainReady {
                // Prefer the operator engine once the brain is up, unless the
                // user has already started an on-device chat.
                if messages.isEmpty { engine = .operatorBrain }
                await loadModels()
            }
        }
        .onChange(of: cycleModelSignal) { _, _ in cycleModel() }
    }

    /// Operator model picker + active-space chip.
    private var modelBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(models) { m in
                    Button {
                        selectedModel = m.id
                        UserDefaults.standard.set(m.id, forKey: modelDefaultsKey)
                    } label: {
                        if m.id == selectedModel { Label(m.label, systemImage: "checkmark") } else { Text(m.label) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu").font(.system(size: 10))
                    Text(selectedModelLabel).font(.system(size: 11)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                }
                .foregroundStyle(theme.foreground)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Spacer()
            if let sid = activeSpaceId {
                Label(sid, systemImage: "square.grid.2x2").font(.system(size: 10)).foregroundStyle(theme.muted).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(theme.accent)
            Text("Assistant").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
            Spacer()
            engineBadge
            if !messages.isEmpty {
                Button { reset() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(theme.muted).font(.system(size: 11))
            }
        }
        .padding(12)
    }

    @ViewBuilder private var engineBadge: some View {
        switch engine {
        case .onDevice:
            Label(fm.onDevice.isAvailable ? "On-device · Free" : fm.onDevice.label,
                  systemImage: fm.onDevice.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .font(.system(size: 10)).foregroundStyle(fm.onDevice.isAvailable ? .green : theme.muted)
        case .operatorBrain:
            Label(brainReady ? "Operator · Tools" : "Operator offline",
                  systemImage: brainReady ? "cpu" : "exclamationmark.triangle")
                .font(.system(size: 10)).foregroundStyle(brainReady ? .green : theme.muted)
        }
    }

    private var enginePicker: some View {
        Picker("", selection: $engine) {
            Text("On-device").tag(Engine.onDevice)
            Text("Operator").tag(Engine.operatorBrain)
        }
        .pickerStyle(.segmented).labelsHidden()
        .padding(.horizontal, 12).padding(.vertical, 8)
        .disabled(working)
        .onChange(of: engine) { _, _ in reset() }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: engine == .operatorBrain ? "cpu" : "sparkles").font(.largeTitle).foregroundStyle(theme.muted)
            if engine == .operatorBrain {
                Text("Operator isn't running").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
                Text(operatorMessage).font(.system(size: 12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
            } else {
                Text("Apple Intelligence isn't available").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
                Text(fm.onDevice.label).font(.system(size: 12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                Button("Open System Settings") {
                    #if os(macOS)
                    if let u = URL(string: "x-apple.systempreferences:com.apple.AppleIntelligence-Settings.extension") { NSWorkspace.shared.open(u) }
                    #endif
                }
                .buttonStyle(.borderedProminent).tint(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private var operatorMessage: String {
        switch env.brain.status {
        case .starting: return "The local operator is starting up…"
        case .failed(let m): return "Operator unavailable: \(m)"
        default: return "The local operator (brain) isn't running."
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        Text(engine == .operatorBrain
                             ? "Ask anything — the operator can use your tools and spaces."
                             : "Ask anything — runs privately on your Mac, for free.")
                            .font(.system(size: 12)).foregroundStyle(theme.muted)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 24)
                    }
                    ForEach(messages) { m in bubble(m).id(m.id) }
                    if working && messages.last?.role != .assistant {
                        HStack { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 12)).foregroundStyle(theme.muted) }
                    }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                }
                .padding(12)
            }
            .onChange(of: messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: messages.last?.text) { _, _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
    }

    private func bubble(_ m: Message) -> some View {
        HStack {
            if m.role == .user { Spacer(minLength: 40) }
            VStack(alignment: m.role == .user ? .trailing : .leading, spacing: 4) {
                if let status = m.status, !status.isEmpty {
                    Label(status, systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 10)).foregroundStyle(theme.muted)
                }
                if !m.text.isEmpty {
                    Text(m.text)
                        .font(.system(size: 13))
                        .foregroundStyle(m.role == .user ? theme.accentForeground : theme.foreground)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(m.role == .user ? theme.accent : theme.inputBg))
                        .textSelection(.enabled)
                }
            }
            if m.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message…", text: $input, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...5)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
                .onSubmit(send)
                .disabled(working)
            if working {
                Button { streamTask?.cancel(); working = false } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 22)).foregroundStyle(theme.muted)
                }.buttonStyle(.plain)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func reset() {
        streamTask?.cancel()
        messages = []
        working = false
        error = nil
        fm.newChat()
    }

    /// Loads the operator model list from the brain catalog: Auto + every
    /// connected provider's models as composite "provider:model" ids.
    private func loadModels() async {
        struct Resp: Decodable {
            struct P: Decodable { let id: String; let name: String?; let connected: Bool?; let models: [M]? }
            struct M: Decodable { let id: String; let label: String? }
            let providers: [P]?
        }
        guard let resp: Resp = try? await env.brain.request("ai.providers") else { return }
        var out: [ModelChoice] = [ModelChoice(id: "", label: "Auto")]
        for p in (resp.providers ?? []) where (p.connected ?? false) {
            for m in (p.models ?? []) {
                out.append(ModelChoice(id: "\(p.id):\(m.id)", label: "\(p.name ?? p.id) · \(m.label ?? m.id)"))
            }
        }
        models = out
        // Drop a stale selection that's no longer available.
        if !models.contains(where: { $0.id == selectedModel }) { selectedModel = "" }
    }

    /// Right-⇧⇧: advance to the next model in the list (wraps).
    private func cycleModel() {
        guard models.count > 1 else { return }
        let i = models.firstIndex { $0.id == selectedModel } ?? 0
        let next = models[(i + 1) % models.count]
        selectedModel = next.id
        UserDefaults.standard.set(next.id, forKey: modelDefaultsKey)
        if engine != .operatorBrain { engine = .operatorBrain }
    }

    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !working else { return }
        input = ""; error = nil
        messages.append(Message(role: .user, text: prompt))
        working = true
        switch engine {
        case .onDevice: sendOnDevice(prompt)
        case .operatorBrain: sendOperator(prompt)
        }
    }

    private func sendOnDevice(_ prompt: String) {
        streamTask = Task {
            defer { working = false }
            do {
                let reply = try await fm.send(prompt)
                messages.append(Message(role: .assistant, text: reply))
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }

    private func sendOperator(_ prompt: String) {
        // One assistant bubble we append deltas + tool status into.
        let idx = messages.count
        messages.append(Message(role: .assistant, text: "", status: nil))
        let opts = BrainService.PromptOptions(spaceId: activeSpaceId, model: selectedModel)
        streamTask = Task {
            defer { working = false }
            do {
                for try await event in env.brain.streamPrompt(prompt, options: opts) {
                    guard idx < messages.count else { break }
                    switch event {
                    case .textDelta(let d):
                        messages[idx].text += d
                        messages[idx].status = nil
                    case .toolCall(_, let name, _):
                        messages[idx].status = "Running \(name)…"
                    case .toolResult:
                        messages[idx].status = nil
                    case .routing, .end:
                        messages[idx].status = nil
                    case .error(let msg):
                        self.error = msg
                    }
                }
                if messages[idx].text.isEmpty && error == nil {
                    messages[idx].text = "(no response)"
                }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }
}
