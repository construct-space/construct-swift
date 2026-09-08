import Foundation
import Observation

/// Which spaces are pinned to the nav rail, and in what order. Render-only UI
/// state (like the Tauri `pinned` store / localStorage), persisted per profile
/// in UserDefaults. Ids may reference native core spaces or installed store
/// spaces — the rail resolves each to an icon/title.
@MainActor
@Observable
public final class PinnedSpacesStore {
    public private(set) var ids: [String] = []
    private var key = "construct.pinnedSpaces.v1"

    /// Default pinned set on first run — the host's core agent spaces + org.
    public static let defaults = ["ask", "builder", "project", "space-developer", "org"]

    public init() {}

    public func load(profile: String) {
        key = "construct.pinnedSpaces.v1.\(profile)"
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            ids = saved
        } else {
            ids = Self.defaults
            save()
        }
    }

    public func isPinned(_ id: String) -> Bool { ids.contains(id) }

    public func pin(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.append(id); save()
    }

    public func unpin(_ id: String) {
        ids.removeAll { $0 == id }; save()
    }

    public func toggle(_ id: String) {
        if isPinned(id) { unpin(id) } else { pin(id) }
    }

    public func move(from: Int, to: Int) {
        guard ids.indices.contains(from), to >= 0, to <= ids.count else { return }
        let item = ids.remove(at: from)
        ids.insert(item, at: min(to, ids.count))
        save()
    }

    private func save() { UserDefaults.standard.set(ids, forKey: key) }
}
