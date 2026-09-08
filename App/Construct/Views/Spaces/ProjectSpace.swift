import SwiftUI
import ConstructCore
#if os(macOS)
import AppKit
#endif

/// Native port of the host Developer portal (`developer` space) — the projects
/// hub. Two paths (Builder vs SpaceKit) up top, then your projects as a badged
/// grid (Space / Builder), each opening in the right agent. Matches
/// DeveloperPortal.vue + ProjectsPage.vue + ProjectCard.vue.
struct ProjectSpace: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @Environment(NavigationModel.self) private var nav: NavigationModel?

    @State private var showNew = false
    @State private var newName = ""
    @State private var newDesc = ""
    @State private var newIsSpace = false
    @State private var error: String?
    @State private var query = ""

    private var projects: [Project] {
        let all = env.projects.projects
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) || ($0.path ?? "").lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                pathsRow
                projectsSection
            }
            .padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .background(theme.surface)
        .onAppear { env.projects.scan() }
        .sheet(isPresented: $showNew) { newProjectSheet }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                (Text("Developer").foregroundStyle(theme.foreground) + Text(".").foregroundStyle(theme.accent))
                    .font(.system(size: 13, weight: .medium)).textCase(.uppercase).tracking(1)
                Text("Build, ship, and verify apps and Spaces with Construct.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted)
            }
            Spacer()
            PillButton(title: "New Project", tint: theme.accent, filled: true) { newName = ""; newDesc = ""; newIsSpace = false; showNew = true }
            PillButton(title: "Open Folder", tint: theme.accent) { openFolder() }
        }
    }

    // MARK: The two paths

    private var pathsRow: some View {
        HStack(spacing: 12) {
            pathCard(title: "Builder", tint: .green, icon: "bolt.fill",
                     blurb: "Plans, writes, and verifies general software — landing pages, sites, apps.",
                     bullets: ["Full plan → write → verify loop with your chosen LLM.",
                               "Builds against any framework — Next, Vue, Go, Rust…",
                               "Deploys to your hosting target when ready."],
                     open: "Open Builder") { nav?.openSpaceId = "builder" }
            pathCard(title: "SpaceKit", tint: .purple, icon: "shippingbox.fill",
                     blurb: "Scaffold and verify a Construct Space — a mini-app that runs inside the host.",
                     bullets: ["Inherits host auth, theme, and the agent runtime.",
                               "Publishes to the marketplace or stays org-private.",
                               "Verifies in the Space Runner before you ship."],
                     open: "Open SpaceKit") { nav?.openSpaceId = "space-developer" }
        }
    }

    private func pathCard(title: String, tint: Color, icon: String, blurb: String, bullets: [String], open: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint)
                        .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 3) {
                        (Text(title).foregroundStyle(theme.foreground) + Text(".").foregroundStyle(theme.accent))
                            .font(.system(size: 13, weight: .medium)).textCase(.uppercase).tracking(1)
                        Text(blurb).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bullets, id: \.self) { b in
                        HStack(alignment: .top, spacing: 6) {
                            Text("▸").foregroundStyle(tint).font(.system(size: 10))
                            Text(b).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("\(open) →").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.accent).textCase(.uppercase).tracking(1).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        }.buttonStyle(.plain)
    }

    // MARK: Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR PROJECTS").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted).tracking(1)
                Spacer()
                Text(env.projects.root.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.muted).lineLimit(1)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.muted)
                TextField("Search projects…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg)).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))

            if projects.isEmpty {
                Text(query.isEmpty ? "No projects yet. Create one or open an existing folder." : "No projects match “\(query)”.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted).padding(.top, 4)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(projects) { project in projectCard(project) }
                }
            }
        }
    }

    private func projectCard(_ project: Project) -> some View {
        let detected = env.projects.detect(project)
        let agent = env.projects.primaryAgent(for: project)
        let color = Self.color(for: project.name)
        return Button {
            env.projects.select(project)
            nav?.openSpaceId = agent.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "folder.fill").font(.system(size: 16)).foregroundStyle(color)
                        .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(project.name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.foreground).lineLimit(1)
                            badge(for: detected)
                        }
                        Text(shortPath(project.path ?? "")).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                    Spacer()
                }
                if let updated = project.updatedAt {
                    Text(timeAgo(updated)).font(.system(size: 11)).foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in TUI", systemImage: "terminal") { env.projects.select(project); nav?.openSpaceId = "tui" }
            Button("Reveal in Finder", systemImage: "folder") {
                #if os(macOS)
                if let p = project.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                #endif
            }
        }
    }

    @ViewBuilder
    private func badge(for detected: ProjectStore.Detected) -> some View {
        switch detected {
        case .space:
            chip("Space", "shippingbox", .blue)
        default:
            chip("Builder", "wrench.and.screwdriver", theme.accent)
        }
    }
    private func chip(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(text).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color).padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: New project

    private var newProjectSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Project").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.foreground)
            Picker("", selection: $newIsSpace) {
                Text("App / Website (Builder)").tag(false)
                Text("Construct Space (SpaceKit)").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            VStack(alignment: .leading, spacing: 6) {
                Text("NAME").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                TextField("my-project", text: $newName).textFieldStyle(.plain).padding(9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg)).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("DESCRIPTION").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                TextField("Optional", text: $newDesc).textFieldStyle(.plain).padding(9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg)).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
            }
            Text("Creates \(env.projects.root.appendingPathComponent(newName.isEmpty ? "name" : newName).path)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.muted).lineLimit(1)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { showNew = false }.buttonStyle(.plain).foregroundStyle(theme.muted)
                PillButton(title: newIsSpace ? "Create & Open SpaceKit" : "Create & Open Builder", tint: theme.accent, filled: true) { create() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 460).background(theme.surface)
    }

    private func create() {
        do {
            _ = try env.projects.create(name: newName, description: newDesc.isEmpty ? nil : newDesc,
                                        kind: newIsSpace ? "space-project" : "project")
            showNew = false
            nav?.openSpaceId = newIsSpace ? "space-developer" : "builder"
        } catch { self.error = error.localizedDescription }
    }

    private func openFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            let project = env.projects.openFolder(url)
            nav?.openSpaceId = env.projects.primaryAgent(for: project).id
        }
        #endif
    }

    // MARK: Helpers

    private func shortPath(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
    private func timeAgo(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date.now)
    }
    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .yellow, .red, .cyan, .green, .indigo]
    static func color(for name: String) -> Color {
        var hash = 0
        for ch in name.unicodeScalars { hash = ((hash << 5) &- hash &+ Int(ch.value)) }
        return palette[abs(hash) % palette.count]
    }
}
