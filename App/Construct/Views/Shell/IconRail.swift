import SwiftUI
import ConstructCore

/// The 72pt icon-only left rail, matching the Tauri app's sidebar:
/// logo → nav/space-page icons → bottom dock (all-spaces, bell, avatar).
struct IconRail: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    let nav: NavigationModel
    let themeStore: ThemeStore

    private var openSpace: InstalledSpace? {
        guard let id = nav.openSpaceId else { return nil }
        return env.spaces.installed.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 4) {
            logo
                .padding(.top, 30) // clear the macOS traffic lights
                .padding(.bottom, 6)

            if let space = openSpace {
                spacePages(space)
            } else {
                appNav
            }

            Spacer()

            // Bottom dock
            RailButton(systemImage: "square.grid.2x2", active: nav.selection == .spaces && openSpace == nil) {
                nav.openSpaceId = nil; nav.selection = .spaces
            }
            RailButton(systemImage: "bell", active: false) {}
            ProfileMenu(nav: nav, themeStore: themeStore)
                .padding(.bottom, 12)
        }
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(theme.canvasBg)
    }

    private var logo: some View {
        Button {
            nav.openSpaceId = nil; nav.selection = .home
        } label: {
            ConstructLogo(color: theme.accent, size: 26)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    /// A pinned rail entry resolved from its id (native core space or installed).
    private struct PinnedEntry: Identifiable {
        let id: String, icon: String, title: String
    }
    private func resolvePinned(_ id: String) -> PinnedEntry? {
        if let core = NativeSpaceRegistry.space(for: id) {
            return PinnedEntry(id: id, icon: core.icon, title: core.name)
        }
        if let s = env.spaces.installed.first(where: { $0.id == id }) {
            return PinnedEntry(id: id, icon: LucideSymbol.sfSymbol(for: s.manifest.icon), title: s.manifest.name)
        }
        return nil
    }
    private var pinnedEntries: [PinnedEntry] { env.pinned.ids.compactMap(resolvePinned) }

    @ViewBuilder
    private var appNav: some View {
        RailButton(systemImage: "house", active: nav.selection == .home) {
            nav.openSpaceId = nil; nav.selection = .home
        }
        RailButton(systemImage: "square.grid.2x2", active: nav.selection == .spaces) {
            nav.openSpaceId = nil; nav.selection = .spaces
        }
        RailButton(systemImage: "bag", active: nav.selection == .marketplace) {
            nav.openSpaceId = nil; nav.selection = .marketplace
        }
        RailButton(systemImage: "gearshape", active: nav.selection == .settings) {
            nav.openSpaceId = nil; nav.selection = .settings
        }

        if !pinnedEntries.isEmpty {
            Rectangle().fill(theme.border).frame(width: 24, height: 1).padding(.vertical, 4)
        }
        // Dynamic pinned spaces — reorder by drag, unpin via context menu.
        ForEach(pinnedEntries) { entry in
            RailButton(systemImage: entry.icon, active: nav.openSpaceId == entry.id) {
                nav.openSpaceId = entry.id
            }
            .help(entry.title)
            .contextMenu {
                Button("Unpin \(entry.title)", systemImage: "pin.slash") { env.pinned.unpin(entry.id) }
            }
            .draggable(entry.id) {
                Image(systemName: entry.icon).font(.system(size: 18)).padding(8)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first,
                      let from = env.pinned.ids.firstIndex(of: dragged),
                      let to = env.pinned.ids.firstIndex(of: entry.id) else { return false }
                env.pinned.move(from: from, to: to)
                return true
            }
        }
    }

    @ViewBuilder
    private func spacePages(_ space: InstalledSpace) -> some View {
        let pages = space.manifest.pages.isEmpty
            ? [SpaceManifest.Page(path: "", label: space.manifest.name, icon: space.manifest.icon, isDefault: true)]
            : space.manifest.pages
        ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
            RailButton(
                systemImage: LucideSymbol.sfSymbol(for: page.icon ?? space.manifest.icon),
                active: idx == nav.openSpacePageIndex
            ) {
                nav.openSpacePageIndex = idx
            }
        }
    }

}

/// A 42×42 rail icon button (10pt radius), with Construct's active/hover states.
private struct RailButton: View {
    @Environment(\.constructTheme) private var theme
    let systemImage: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 42, height: 42)
                .foregroundStyle(active ? theme.accent : (hovering ? theme.foreground : theme.muted))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(active ? theme.accent.opacity(0.15) : (hovering ? theme.foreground.opacity(0.06) : .clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
