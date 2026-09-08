import SwiftUI
import ConstructCore

/// A native, full-window agentic chat — the shared surface behind the host's
/// core agent spaces (Ask, Builder, Project, Space Developer). Streams the
/// brain's agent loop with a specific `agent_id`, so each space gets its
/// specialized persona + tools. Port of the AskPage / AgentView pattern.
struct AgentChatView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    let agentId: String
    let title: String
    let emptyTitle: String
    let emptySubtitle: String
    /// Optional space id this agent operates within (passed to tools).
    var spaceId: String? = nil

    struct Message: Identifiable { let id = UUID(); let role: Role; var text: String; var status: String?; enum Role { case user, assistant } }
    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var working = false
    @State private var error: String?
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            chrome
            Divider().overlay(theme.border)
            if !env.brain.status.isRunning {
                BrainOfflineNotice(status: env.brain.status)
                    .frame(maxWidth: 480).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                conversation
                Divider().overlay(theme.border)
                composer
            }
        }
        .background(theme.surface)
    }

    private var chrome: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(theme.accent)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
            Spacer()
            if !messages.isEmpty {
                Button { newThread() } label: { Label("New", systemImage: "square.and.pencil").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(theme.muted)
            }
        }
        .padding(12)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    emptyState.frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { m in bubble(m).id(m.id) }
                        if working && messages.last?.role != .assistant {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 12)).foregroundStyle(theme.muted) }
                        }
                        if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .onChange(of: messages.count) { _, _ in if let l = messages.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
            .onChange(of: messages.last?.text) { _, _ in if let l = messages.last { proxy.scrollTo(l.id, anchor: .bottom) } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(theme.muted.opacity(0.6))
            Text(emptyTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.foreground)
            Text(emptySubtitle).font(.system(size: 13)).foregroundStyle(theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .padding(24)
    }

    private func bubble(_ m: Message) -> some View {
        HStack {
            if m.role == .user { Spacer(minLength: 60) }
            VStack(alignment: m.role == .user ? .trailing : .leading, spacing: 4) {
                if let status = m.status, !status.isEmpty {
                    Label(status, systemImage: "wrench.and.screwdriver").font(.system(size: 10)).foregroundStyle(theme.muted)
                }
                if !m.text.isEmpty {
                    Text(m.text).font(.system(size: 14))
                        .foregroundStyle(m.role == .user ? theme.accentForeground : theme.foreground)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(m.role == .user ? theme.accent : theme.inputBg))
                        .textSelection(.enabled)
                }
            }
            if m.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message \(title)…", text: $input, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...6)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.inputBg))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
                .onSubmit(send).disabled(working)
            if working {
                Button { streamTask?.cancel(); working = false } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 24)).foregroundStyle(theme.muted)
                }.buttonStyle(.plain)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 24)).foregroundStyle(theme.accent)
                }.buttonStyle(.plain).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(maxWidth: 740)
        .frame(maxWidth: .infinity)
    }

    private func newThread() {
        streamTask?.cancel(); messages = []; working = false; error = nil
    }

    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !working else { return }
        input = ""; error = nil
        messages.append(Message(role: .user, text: prompt))
        working = true
        let idx = messages.count
        messages.append(Message(role: .assistant, text: "", status: nil))
        let opts = BrainService.PromptOptions(spaceId: spaceId, agentId: agentId)
        streamTask = Task {
            defer { working = false }
            do {
                for try await event in env.brain.streamPrompt(prompt, options: opts) {
                    guard idx < messages.count else { break }
                    switch event {
                    case .textDelta(let d): messages[idx].text += d; messages[idx].status = nil
                    case .toolCall(_, let name, _): messages[idx].status = "Running \(name)…"
                    case .toolResult: messages[idx].status = nil
                    case .routing, .end: messages[idx].status = nil
                    case .error(let msg): self.error = msg
                    }
                }
                if messages[idx].text.isEmpty && error == nil { messages[idx].text = "(no response)" }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }
}
