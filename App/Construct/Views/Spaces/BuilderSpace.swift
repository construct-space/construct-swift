import SwiftUI
import ConstructCore
#if os(macOS)
import AppKit
#endif

/// Native port of the host `builder` core space — plans, builds, and verifies
/// software. Project-aware: pick a working folder, then chat with the brain's
/// builder agent (agent_id "builder" → construct agent on the builder skill
/// surface) with `project_dir` set so its bash/read/write/edit tools operate in
/// the project. Shows a live file tree + interleaved text/tool blocks, matching
/// BuilderPage.vue's BlockRenderer.
struct BuilderSpace: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    /// Which agent + chrome this surface runs. Builder and Space Developer share
    /// the same project-scoped shell, differing only by agent + labels.
    var agentId: String = "builder"
    var title: String = "Builder"
    var icon: String = "hammer"
    var emptyTitle: String = "What should we build?"

    // MARK: Turn / block model (mirrors BlockRenderer)
    enum Block: Identifiable {
        case text(id: UUID, String)
        case tool(ToolBlock)
        var id: UUID { switch self { case .text(let id, _): id; case .tool(let t): t.uuid } }
    }
    struct ToolBlock: Identifiable {
        let uuid = UUID()
        let callId: String
        let name: String
        var input: String
        var output: String = ""
        var isError = false
        var running = true
        var id: UUID { uuid }
    }
    struct Turn: Identifiable {
        let id = UUID()
        let role: Role; enum Role { case user, assistant }
        var text: String = ""            // for user turns
        var blocks: [Block] = []         // for assistant turns
    }

    @Environment(NavigationModel.self) private var nav: NavigationModel?

    @State private var turns: [Turn] = []
    @State private var input = ""
    @State private var working = false
    @State private var error: String?
    @State private var streamTask: Task<Void, Never>?

    @State private var fileTree: [FileNode] = []
    @State private var showFiles = true

    /// Builder operates inside the selected project (set from the Projects hub).
    private var projectPath: String { env.projects.current?.path ?? "" }
    private var projectName: String { env.projects.current?.name ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(theme.border)
            if projectPath.isEmpty {
                projectChooser
            } else if !env.brain.status.isRunning {
                BrainOfflineNotice(status: env.brain.status).frame(maxWidth: 480).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    if showFiles {
                        fileTreeView.frame(width: 240)
                        Divider().overlay(theme.border)
                    }
                    VStack(spacing: 0) {
                        conversation
                        Divider().overlay(theme.border)
                        composer
                    }
                }
            }
        }
        .background(theme.surface)
        .onAppear { if !projectPath.isEmpty { refreshFiles() } }
        .onChange(of: projectPath) { _, _ in newThread(); refreshFiles() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(theme.accent)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
            if !projectPath.isEmpty {
                Button { showFiles.toggle() } label: { Image(systemName: "sidebar.left").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(showFiles ? theme.accent : theme.muted)
            }
            Spacer()
            if !projectPath.isEmpty {
                Menu {
                    Button("Open Projects…") { nav?.openSpaceId = "project" }
                    Button("Refresh Files") { refreshFiles() }
                    if !turns.isEmpty { Button("New Thread") { newThread() } }
                } label: {
                    Label(projectName, systemImage: "folder").font(.system(size: 12)).foregroundStyle(theme.foreground)
                }.menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding(12)
    }

    private var projectChooser: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(theme.muted.opacity(0.6))
            Text("Open a project to build").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.foreground)
            Text("Builder works inside a project. Pick or create one in the Projects hub.")
                .font(.system(size: 13)).foregroundStyle(theme.muted).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button { nav?.openSpaceId = "project" } label: {
                Label("Go to Projects", systemImage: "folder.badge.plus")
                    .font(.system(size: 13, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent)).foregroundStyle(theme.accentForeground)
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    // MARK: File tree

    private var fileTreeView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FILES").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                Spacer()
                Button { refreshFiles() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider().overlay(theme.border)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(fileTree) { node in FileRow(node: node, depth: 0) }
                }
                .padding(8)
            }
        }
        .background(theme.canvasBg.opacity(0.4))
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if turns.isEmpty {
                        VStack(spacing: 8) {
                            Text(emptyTitle).font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.foreground)
                            Text("Describe what you want — Builder plans, writes, and verifies it in \(projectName).")
                                .font(.system(size: 13)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    }
                    ForEach(turns) { turn in turnView(turn).id(turn.id) }
                    if working && turns.last?.role != .assistant {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 12)).foregroundStyle(theme.muted) }
                    }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                }
                .padding(18).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .onChange(of: turns.count) { _, _ in scrollEnd(proxy) }
            .onChange(of: turns.last?.blocks.count) { _, _ in scrollEnd(proxy) }
        }
    }

    private func scrollEnd(_ p: ScrollViewProxy) { if let l = turns.last { withAnimation { p.scrollTo(l.id, anchor: .bottom) } } }

    @ViewBuilder
    private func turnView(_ turn: Turn) -> some View {
        if turn.role == .user {
            HStack {
                Spacer(minLength: 60)
                Text(turn.text).font(.system(size: 14)).foregroundStyle(theme.accentForeground)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.accent)).textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(turn.blocks) { block in
                    switch block {
                    case .text(_, let t):
                        if !t.isEmpty {
                            Text(t).font(.system(size: 14)).foregroundStyle(theme.foreground)
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                    case .tool(let tb): ToolBlockView(block: tb)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Tell \(title) what to do…", text: $input, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...6).padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.inputBg))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
                .onSubmit(send).disabled(working)
            if working {
                Button { streamTask?.cancel(); working = false } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 24)).foregroundStyle(theme.muted)
                }.buttonStyle(.plain)
            } else {
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 24)).foregroundStyle(theme.accent) }
                    .buttonStyle(.plain).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func newThread() { streamTask?.cancel(); turns = []; working = false; error = nil }

    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !working else { return }
        input = ""; error = nil
        turns.append(Turn(role: .user, text: prompt))
        let aIdx = turns.count
        turns.append(Turn(role: .assistant))
        working = true
        let opts = BrainService.PromptOptions(spaceId: agentId, agentId: agentId)
        let path = projectPath
        streamTask = Task {
            defer { working = false; refreshFiles() }
            do {
                for try await event in env.brain.streamPrompt(prompt, options: withProjectDir(opts, path)) {
                    guard aIdx < turns.count else { break }
                    apply(event, to: aIdx)
                }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }

    /// project_dir isn't a PromptOptions field; pass it via spaceId-free path by
    /// extending options. We thread it through a dedicated overload.
    private func withProjectDir(_ opts: BrainService.PromptOptions, _ path: String) -> BrainService.PromptOptions {
        var o = opts; o.projectDir = path.isEmpty ? nil : path; return o
    }

    private func apply(_ event: BrainService.PromptEvent, to idx: Int) {
        switch event {
        case .textDelta(let d):
            if case .text(let id, let cur)? = turns[idx].blocks.last {
                turns[idx].blocks[turns[idx].blocks.count - 1] = .text(id: id, cur + d)
            } else {
                turns[idx].blocks.append(.text(id: UUID(), d))
            }
        case .toolCall(let cid, let name, let inputStr):
            turns[idx].blocks.append(.tool(ToolBlock(callId: cid, name: name, input: inputStr)))
        case .toolResult(let cid, let output, let isError):
            if let bi = turns[idx].blocks.firstIndex(where: { if case .tool(let t) = $0 { return t.callId == cid } else { return false } }),
               case .tool(var tb) = turns[idx].blocks[bi] {
                tb.output = output; tb.isError = isError; tb.running = false
                turns[idx].blocks[bi] = .tool(tb)
            }
        case .routing, .end:
            break
        case .error(let msg):
            self.error = msg
        }
    }

    // MARK: File tree loading

    private func refreshFiles() {
        guard !projectPath.isEmpty else { fileTree = []; return }
        fileTree = Self.loadDir(projectPath)
    }

    static func loadDir(_ path: String) -> [FileNode] {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        let ignored: Set<String> = [".git", "node_modules", ".DS_Store", ".construct", "dist", ".next", "target"]
        return names.filter { !ignored.contains($0) }.sorted().compactMap { name -> FileNode? in
            var isDir: ObjCBool = false
            let full = url.appendingPathComponent(name).path
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { return nil }
            return FileNode(name: name, path: full, isDir: isDir.boolValue)
        }.sorted { ($0.isDir ? 0 : 1, $0.name.lowercased()) < ($1.isDir ? 0 : 1, $1.name.lowercased()) }
    }
}

/// One node in the Builder file tree.
struct FileNode: Identifiable, Hashable {
    let name: String
    let path: String
    let isDir: Bool
    var id: String { path }
}

/// Recursive disclosure row for the file tree.
private struct FileRow: View {
    @Environment(\.constructTheme) private var theme
    let node: FileNode
    let depth: Int
    @State private var expanded = false
    @State private var children: [FileNode] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                if node.isDir {
                    expanded.toggle()
                    if expanded && children.isEmpty { children = BuilderSpace.loadDir(node.path) }
                }
            } label: {
                HStack(spacing: 4) {
                    if node.isDir {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8)).foregroundStyle(theme.muted).frame(width: 10)
                        Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(theme.accent.opacity(0.8))
                    } else {
                        Spacer().frame(width: 10)
                        Image(systemName: "doc").font(.system(size: 11)).foregroundStyle(theme.muted)
                    }
                    Text(node.name).font(.system(size: 12)).foregroundStyle(theme.foreground).lineLimit(1)
                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 12)
                .padding(.vertical, 3).padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(children) { child in FileRow(node: child, depth: depth + 1) }
            }
        }
    }
}

/// A collapsible tool-call block (read/write/edit/bash/…).
private struct ToolBlockView: View {
    @Environment(\.constructTheme) private var theme
    let block: BuilderSpace.ToolBlock
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    if block.running { ProgressView().controlSize(.small) }
                    else { Image(systemName: block.isError ? "xmark.circle" : "checkmark.circle").font(.system(size: 11)).foregroundStyle(block.isError ? .red : .green) }
                    Image(systemName: icon(block.name)).font(.system(size: 11)).foregroundStyle(theme.accent)
                    Text(block.name).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(theme.foreground)
                    if !block.input.isEmpty {
                        Text(summary(block.input)).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9)).foregroundStyle(theme.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !block.input.isEmpty { codeBlock(block.input, label: "input") }
                    if !block.output.isEmpty { codeBlock(block.output, label: "output") }
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
    }

    private func codeBlock(_ s: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.muted)
            Text(s.count > 4000 ? String(s.prefix(4000)) + "…" : s)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(theme.canvasBg.opacity(0.5)))
        }
    }

    private func icon(_ name: String) -> String {
        switch name {
        case "read", "read_file": "doc.text"
        case "write", "write_file": "square.and.pencil"
        case "edit", "edit_file": "pencil"
        case "bash", "shell": "terminal"
        case "glob", "grep", "search": "magnifyingglass"
        case "web_fetch", "web_search": "globe"
        default: "wrench.and.screwdriver"
        }
    }
    private func summary(_ input: String) -> String {
        // Show a path/command hint from the JSON input if present.
        if let data = input.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for k in ["path", "file_path", "file", "command", "pattern", "query", "url"] {
                if let v = obj[k] as? String { return v }
            }
        }
        return ""
    }
}
