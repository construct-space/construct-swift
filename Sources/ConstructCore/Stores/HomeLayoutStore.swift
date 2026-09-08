import Foundation
import Observation

/// The Home widget dashboard layout — which space widgets are shown, in what
/// order, at what size. Render-only UI state (the Tauri home-layout JSON
/// equivalent), persisted per profile to `<profile>/native/home-layout.json`.
@MainActor
@Observable
public final class HomeLayoutStore {
    /// One placed widget on the dashboard.
    public struct Item: Codable, Identifiable, Hashable, Sendable {
        public var spaceId: String
        public var widgetId: String
        public var sizeKey: String
        public var id: String { "\(spaceId):\(widgetId)" }
        public init(spaceId: String, widgetId: String, sizeKey: String) {
            self.spaceId = spaceId; self.widgetId = widgetId; self.sizeKey = sizeKey
        }
    }

    public private(set) var items: [Item] = []
    /// False until a layout file exists — lets the view seed defaults once.
    public private(set) var initialized = false

    private let paths: ConstructPaths
    private var profileId = ""

    public init(paths: ConstructPaths = ConstructPaths()) { self.paths = paths }

    private var fileURL: URL {
        paths.profileDir(profileId).appendingPathComponent("native", isDirectory: true)
            .appendingPathComponent("home-layout.json")
    }

    public func load(profile: String) {
        // Never persist under an empty/placeholder id — that strands the layout
        // in profiles/native/ instead of the active profile's folder.
        guard !profile.isEmpty else { return }
        profileId = profile
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            items = []; initialized = false; return
        }
        items = decoded; initialized = true
    }

    /// Writes the default layout (first run): every provided widget at its size.
    public func seed(_ defaults: [Item]) {
        items = defaults; initialized = true; save()
    }

    public func contains(spaceId: String, widgetId: String) -> Bool {
        items.contains { $0.spaceId == spaceId && $0.widgetId == widgetId }
    }

    public func add(_ item: Item) {
        guard !contains(spaceId: item.spaceId, widgetId: item.widgetId) else { return }
        items.append(item); save()
    }

    public func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }; save()
    }

    public func resize(_ item: Item, to sizeKey: String) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].sizeKey = sizeKey; save()
    }

    public func move(from: Int, to: Int) {
        guard items.indices.contains(from), to >= 0, to <= items.count else { return }
        let it = items.remove(at: from); items.insert(it, at: min(to, items.count)); save()
    }

    /// Drops widgets whose space is no longer installed.
    public func prune(installedSpaceIds: Set<String>) {
        let kept = items.filter { installedSpaceIds.contains($0.spaceId) }
        if kept.count != items.count { items = kept; save() }
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: fileURL, options: .atomic) }
    }
}
