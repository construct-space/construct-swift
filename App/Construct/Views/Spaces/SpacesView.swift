import SwiftUI
import ConstructCore

/// The spaces launchpad — grid of installed spaces. Port of SpacesPage.vue.
struct SpacesView: View {
    @Environment(AppEnvironment.self) private var env
    let nav: NavigationModel

    /// Installed store spaces that aren't shadowed by a native core space of the
    /// same id (the native one renders instead, so show it once, as native).
    private var storeSpaces: [InstalledSpace] {
        env.spaces.installed.filter { !NativeSpaceRegistry.ids.contains($0.id) }
    }

    @ViewBuilder
    private func pinButton(_ id: String) -> some View {
        if env.pinned.isPinned(id) {
            Button("Unpin from sidebar", systemImage: "pin.slash") { env.pinned.unpin(id) }
        } else {
            Button("Pin to sidebar", systemImage: "pin") { env.pinned.pin(id) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                // Native core spaces (first-party, SwiftUI) lead the grid.
                ForEach(NativeSpaceRegistry.all) { core in
                    Button { nav.openSpaceId = core.id } label: {
                        NativeSpaceCard(core: core)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { pinButton(core.id) }
                }
                // Installed store spaces (WebUI).
                ForEach(storeSpaces) { space in
                    Button { nav.openSpaceId = space.id } label: {
                        SpaceCard(space: space)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { pinButton(space.id) }
                }
            }
            .padding(24)
        }
        .onAppear { env.spaces.loadInstalled() }
    }
}
