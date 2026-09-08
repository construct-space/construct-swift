import SwiftUI
import ConstructCore

// MARK: - Memory (reads/writes the same files the operator uses)

struct MemorySettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    /// Brain memory scopes. `user` follows you everywhere; `project` lives with
    /// the repo (needs an active project — deferred); `org` is shared (not yet
    /// available locally). Matches MemorySettings.vue.
    enum Scope: String, CaseIterable { case user = "Personal" }
    @State private var scope: Scope = .user
    @State private var content = ""
    @State private var original = ""
    @State private var saved = false
    @State private var loading = false
    @State private var error: String?

    private var dirty: Bool { content != original }
    /// Direct-file fallback when the brain is offline (brain dir, lowercase file).
    private var fallbackURL: URL {
        env.paths.memoryDir(env.profiles.activeProfileId).appendingPathComponent("user.md")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeading("Memory", "Durable facts the operator keeps about you — preferences, working style, identity. Edit directly too.")

            TextEditor(text: $content)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 320)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))

            HStack {
                PillButton(title: "Save", tint: theme.accent, filled: true) { Task { await save() } }
                    .disabled(!dirty || loading)
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                else if saved { Text("Saved").font(.system(size: 12)).foregroundStyle(.green) }
                else if dirty { Text("Unsaved changes").font(.system(size: 12)).foregroundStyle(theme.muted) }
                Spacer()
                Text("Personal — follows you across projects and orgs.").font(.system(size: 11)).foregroundStyle(theme.muted)
            }
        }
        .task { await load() }
        .onChange(of: content) { _, _ in saved = false }
    }

    private struct MemoryResult: Decodable { let content: String? }

    private func load() async {
        loading = true; error = nil; defer { loading = false }
        if env.brain.status.isRunning {
            struct Req: Encodable { let scope: String; let project_dir: String }
            do {
                let res: MemoryResult = try await env.brain.request("memory.get", payload: Req(scope: "user", project_dir: ""))
                content = res.content ?? ""
            } catch {
                content = (try? String(contentsOf: fallbackURL, encoding: .utf8)) ?? ""
            }
        } else {
            content = (try? String(contentsOf: fallbackURL, encoding: .utf8)) ?? ""
        }
        original = content
        saved = false
    }

    private func save() async {
        loading = true; error = nil; defer { loading = false }
        if env.brain.status.isRunning {
            struct Req: Encodable { let scope: String; let project_dir: String; let content: String }
            struct Empty: Decodable {}
            do {
                let _: Empty = try await env.brain.request("memory.set", payload: Req(scope: "user", project_dir: "", content: content))
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                return
            }
        } else {
            try? env.paths.ensureDir(env.paths.memoryDir(env.profiles.activeProfileId))
            try? content.write(to: fallbackURL, atomically: true, encoding: .utf8)
        }
        original = content
        saved = true
    }
}

// MARK: - Skills (lists skills/<name>/SKILL.md)

struct SkillsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    struct Skill: Identifiable { let id: String; let name: String; let description: String; let url: URL }
    @State private var skills: [Skill] = []
    @State private var pendingDelete: Skill?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SettingsHeading("Skills", "Procedural skills the operator can load (skills/<name>/SKILL.md).")
                Spacer()
                PillButton(title: "Refresh", tint: theme.accent) { load() }
            }
            if skills.isEmpty {
                Text("No skills yet. The operator writes SKILL.md files here as it learns procedures.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted).padding(.top, 8)
            } else {
                ForEach(skills) { skill in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
                            if !skill.description.isEmpty {
                                Text(skill.description).font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(2)
                            }
                        }
                        Spacer()
                        Button { pendingDelete = skill } label: {
                            Image(systemName: "trash").foregroundStyle(.red).font(.system(size: 12))
                        }.buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                    Divider().overlay(theme.border)
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Delete skill “\(pendingDelete?.name ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let s = pendingDelete { delete(s) } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This permanently removes the skill folder from disk.")
        }
    }

    private func load() {
        let dir = env.paths.skillsDir(env.profiles.activeProfileId)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { skills = []; return }
        skills = entries.compactMap { folder -> Skill? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let md = folder.appendingPathComponent("SKILL.md")
            let text = (try? String(contentsOf: md, encoding: .utf8)) ?? ""
            let (name, desc) = Self.frontmatter(text)
            return Skill(id: folder.lastPathComponent,
                         name: name ?? folder.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized,
                         description: desc ?? "", url: folder)
        }.sorted { $0.name < $1.name }
    }

    private func delete(_ s: Skill) {
        try? FileManager.default.removeItem(at: s.url)
        pendingDelete = nil
        load()
    }

    /// Pulls `name:` / `description:` from a SKILL.md YAML frontmatter block.
    static func frontmatter(_ text: String) -> (String?, String?) {
        guard text.hasPrefix("---") else { return (nil, nil) }
        let lines = text.components(separatedBy: "\n")
        var name: String?, desc: String?
        for line in lines.dropFirst() {
            if line.hasPrefix("---") { break }
            if let v = value(line, "name") { name = v }
            if let v = value(line, "description") { desc = v }
        }
        return (name, desc)
    }
    private static func value(_ line: String, _ key: String) -> String? {
        guard line.hasPrefix("\(key):") else { return nil }
        return line.dropFirst(key.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }
}

// MARK: - Spaces (installed spaces for this profile)

struct SpacesSettings: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeading("Spaces", "Spaces installed for this profile. Manage availability across your organization on the portal.")
            if env.spaces.installed.isEmpty {
                Text("No spaces installed. Browse the Marketplace to install spaces.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted).padding(.top, 8)
            } else {
                ForEach(env.spaces.installed) { space in
                    HStack {
                        Image(systemName: LucideSymbol.sfSymbol(for: space.manifest.icon)).foregroundStyle(theme.accent).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(space.manifest.name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.foreground)
                            if let d = space.manifest.description {
                                Text(d).font(.system(size: 11)).foregroundStyle(theme.muted).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("v\(space.manifest.version)").font(.system(size: 11)).foregroundStyle(theme.muted)
                    }
                    .padding(.vertical, 8)
                    Divider().overlay(theme.border)
                }
            }
        }
        .onAppear { env.spaces.loadInstalled() }
    }
}
