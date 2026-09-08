import SwiftUI
import ConstructCore

/// The marketplace catalog browser. Port of MarketplacePage.vue.
struct MarketplaceView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    var body: some View {
        ScrollView {
            if env.spaces.isLoadingCatalog {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if env.spaces.catalog.isEmpty {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "bag",
                    description: Text(env.spaces.lastError ?? "Pull the catalog to browse spaces.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(env.spaces.catalog) { space in
                        MarketplaceCard(space: space)
                            .environment(env)
                    }
                }
                .padding(24)
            }
        }
        .searchable(text: $query, prompt: "Search spaces")
        .onSubmit(of: .search) {
            Task { await env.spaces.loadCatalog(query: query) }
        }
        .task { await env.spaces.loadCatalog() }
    }
}

private struct MarketplaceCard: View {
    @Environment(AppEnvironment.self) private var env
    let space: MarketplaceSpace
    @State private var showDetail = false

    private var isInstalled: Bool { env.spaces.isInstalled(space.id) }
    private var isInstalling: Bool { env.spaces.installing.contains(space.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cube.box.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                Spacer()
                if let installs = space.installs30d {
                    Label("\(installs)", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(space.name).font(.headline).lineLimit(1)
            if let description = space.description {
                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let publisher = space.publisherName {
                Text(publisher).font(.caption2).foregroundStyle(.tertiary)
            }

            installButton
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) { MarketplaceDetailSheet(space: space).environment(env) }
    }

    @ViewBuilder
    private var installButton: some View {
        if isInstalling {
            ProgressView().controlSize(.small)
        } else if isInstalled {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Button("Install") {
                Task { await env.spaces.install(space) }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Detail view for a marketplace space — full description, metadata, install.
/// Port of MarketplaceSpaceDetail.vue.
private struct MarketplaceDetailSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let space: MarketplaceSpace

    private var isInstalled: Bool { env.spaces.isInstalled(space.id) }
    private var isInstalling: Bool { env.spaces.installing.contains(space.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plain).foregroundStyle(theme.accent)
            }.padding(14)
            Divider().overlay(theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "cube.box.fill").font(.system(size: 40)).foregroundStyle(theme.accent)
                            .frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 12).fill(theme.accent.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(space.name).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.foreground)
                            if let pub = space.publisherName { Text("by \(pub)").font(.system(size: 12)).foregroundStyle(theme.muted) }
                            HStack(spacing: 10) {
                                if let v = space.version { meta("v\(v)") }
                                if let c = space.category { meta(c) }
                                if let d = space.downloads { meta("\(d) installs") }
                            }
                        }
                        Spacer()
                        installControl
                    }
                    if let desc = space.description {
                        Text(desc).font(.system(size: 14)).foregroundStyle(theme.foreground).fixedSize(horizontal: false, vertical: true)
                    }
                    if let tags = space.tags, !tags.isEmpty {
                        FlowTags(tags: tags)
                    }
                    if let pages = space.manifest?.pages, !pages.isEmpty {
                        Text("PAGES").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                        ForEach(Array(pages.enumerated()), id: \.offset) { _, p in
                            Label(p.label ?? p.path, systemImage: "doc").font(.system(size: 12)).foregroundStyle(theme.foreground)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 560)
        .background(theme.surface)
    }

    private func meta(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(theme.muted)
    }

    @ViewBuilder private var installControl: some View {
        if isInstalling { ProgressView().controlSize(.small) }
        else if isInstalled {
            Label("Installed", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green)
        } else {
            PillButton(title: "Install", tint: theme.accent, filled: true) { Task { await env.spaces.install(space) } }
        }
    }
}

/// Simple wrapping tag row.
private struct FlowTags: View {
    @Environment(\.constructTheme) private var theme
    let tags: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { t in
                Text(t).font(.system(size: 10)).foregroundStyle(theme.muted)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(theme.muted.opacity(0.14)))
            }
        }
    }
}
