import SwiftUI
import ConstructCore

/// Native port of the host `org-project` core space — org-wide project
/// management (source-api `/api/source/org/projects`). Lists shared org
/// projects: name, framework, repo, description.
struct OrgProjectsSpace: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    struct OrgProject: Decodable, Identifiable {
        let id: String
        let name: String
        let description: String?
        let repo_url: String?
        let framework: String?
        let updated_at: String?
    }

    @State private var projects: [OrgProject] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Org Projects").font(.system(size: 22, weight: .bold)).foregroundStyle(theme.foreground)
                        Text("Shared projects across your organization.").font(.system(size: 13)).foregroundStyle(theme.muted)
                    }
                    Spacer()
                    PillButton(title: "Refresh", tint: theme.accent) { Task { await load() } }
                }

                if !env.auth.isOrgScoped {
                    notice("Switch to an organization to see org projects.")
                } else if let error {
                    notice(error)
                } else if loading && projects.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else if projects.isEmpty {
                    notice("No org projects yet.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                        ForEach(projects) { card($0) }
                    }
                }
            }
            .padding(24)
        }
        .background(theme.canvasBg)
        .task { await load() }
    }

    private func card(_ p: OrgProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill.badge.person.crop").foregroundStyle(theme.accent)
                Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.foreground).lineLimit(1)
                Spacer()
                if let fw = p.framework, !fw.isEmpty {
                    Text(fw.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.muted)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(theme.muted.opacity(0.14)))
                }
            }
            if let d = p.description, !d.isEmpty {
                Text(d).font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(2)
            }
            if let r = p.repo_url, !r.isEmpty {
                Label(r, systemImage: "link").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .contextMenu {
            if let r = p.repo_url, let url = URL(string: r) {
                Button("Open Repo", systemImage: "link") {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func load() async {
        guard env.auth.isOrgScoped else { loading = false; return }
        loading = true; error = nil; defer { loading = false }
        do {
            projects = try await env.api.request(.get, env.config.gateway.appendingPathComponent("api/source/org/projects"))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
