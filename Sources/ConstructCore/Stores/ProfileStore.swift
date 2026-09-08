import Foundation
import Observation

/// Manages the multi-profile system. Port of the Vue `profile` store, backed
/// by `profiles.json` on disk (replaces the Rust `list/switch/create_profile`
/// commands).
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profiles: [Profile] = []
    public private(set) var activeProfileId: String = "default"

    private let paths: ConstructPaths

    public init(paths: ConstructPaths = ConstructPaths()) {
        self.paths = paths
    }

    public var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileId }
    }

    public func load() {
        guard let data = try? Data(contentsOf: paths.profilesFile),
              let registry = try? JSONDecoder().decode(ProfileRegistry.self, from: data),
              !registry.profiles.isEmpty
        else {
            // No shared registry yet: stay empty (don't write a bogus default
            // that could clobber a registry written by the Tauri app/CLI).
            profiles = []
            activeProfileId = ""
            return
        }
        profiles = registry.profiles
        activeProfileId = registry.activeProfile
    }

    public func create(_ profile: Profile) throws {
        if !profiles.contains(where: { $0.id == profile.id }) {
            profiles.append(profile)
        }
        try persist()
    }

    public func switchTo(_ profileId: String) throws {
        guard profiles.contains(where: { $0.id == profileId }) else { return }
        activeProfileId = profileId
        try persist()
    }

    private func persist() throws {
        try paths.ensureDir(paths.base)
        // Merge with whatever is already on disk so we never drop profiles
        // created by the Tauri app / CLI (they share this registry).
        var merged = profiles
        if let data = try? Data(contentsOf: paths.profilesFile),
           let existing = try? JSONDecoder().decode(ProfileRegistry.self, from: data) {
            for e in existing.profiles where !merged.contains(where: { $0.id == e.id }) {
                merged.append(e)
            }
        }
        profiles = merged
        let registry = ProfileRegistry(version: 1, activeProfile: activeProfileId, profiles: merged)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(registry).write(to: paths.profilesFile, options: .atomic)
    }

    /// Matches the Tauri app's `ProfileRegistry` (desktop/src/config.rs).
    private struct ProfileRegistry: Codable {
        var version: Int
        var activeProfile: String
        var profiles: [Profile]

        enum CodingKeys: String, CodingKey {
            case version
            case activeProfile = "active_profile"
            case profiles
        }
    }
}
