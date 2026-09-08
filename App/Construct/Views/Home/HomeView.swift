import SwiftUI
import ConstructCore

/// The home dashboard — recent activity and quick access. Port of HomePage.vue.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    var nav: NavigationModel? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back")
                        .font(.largeTitle.bold())
                    Text(env.auth.user?.name ?? env.auth.user?.email ?? "")
                        .foregroundStyle(.secondary)
                }

                Text("Your spaces").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                    // Native core spaces (first-party, SwiftUI).
                    ForEach(NativeSpaceRegistry.all) { core in
                        Button { nav?.openSpaceId = core.id } label: {
                            NativeSpaceCard(core: core)
                        }
                        .buttonStyle(.plain)
                    }
                    // Installed store spaces (WebUI).
                    ForEach(env.spaces.installed) { space in
                        Button { nav?.openSpaceId = space.id } label: {
                            SpaceCard(space: space)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
    }
}

/// A grid card for a native core space, with a "Native" badge.
struct NativeSpaceCard: View {
    let core: NativeCoreSpace
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: core.icon).font(.largeTitle).foregroundStyle(.tint)
                Spacer()
                Text("NATIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.tint)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            Text(core.name).font(.headline).lineLimit(1)
            Text(core.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A grid card for an installed space.
struct SpaceCard: View {
    let space: InstalledSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text(space.manifest.name)
                .font(.headline)
                .lineLimit(1)
            if let desc = space.manifest.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
