import Foundation

/// Resolves on-disk locations, mirroring the Rust `get_*_data_dir` commands.
/// Base: `~/Library/Application Support/Construct` on macOS.
public struct ConstructPaths: Sendable {
    public let base: URL

    public init(base: URL? = nil) {
        if let base {
            self.base = base
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.base = appSupport.appendingPathComponent("Construct", isDirectory: true)
        }
    }

    /// `profiles.json` registry of all profiles (shared with the Tauri app/CLI).
    public var profilesFile: URL { base.appendingPathComponent("profiles.json") }

    /// Root holding all per-profile directories (`<base>/profiles`).
    public var profilesRoot: URL { base.appendingPathComponent("profiles", isDirectory: true) }

    /// Per-profile data directory (`<base>/profiles/<profileId>`) — the same
    /// layout the Tauri app + CLI use, so the Swift app shares the session.
    public func profileDir(_ profileId: String) -> URL {
        profilesRoot.appendingPathComponent(profileId, isDirectory: true)
    }

    /// Per-profile `auth.json` (the app owns writes; CLI reads this file).
    public func authFile(_ profileId: String) -> URL {
        profileDir(profileId).appendingPathComponent("auth.json")
    }

    /// Per-profile installed spaces directory.
    public func spacesDir(_ profileId: String) -> URL {
        profileDir(profileId).appendingPathComponent("spaces", isDirectory: true)
    }

    /// The Go operator's data root (`<profile>/brain`).
    public func brainDir(_ profileId: String) -> URL {
        profileDir(profileId).appendingPathComponent("brain", isDirectory: true)
    }
    /// Operator memory dir (`brain/memory`) — shared with the Go operator.
    public func memoryDir(_ profileId: String) -> URL {
        brainDir(profileId).appendingPathComponent("memory", isDirectory: true)
    }
    /// Personal "about you" memory (`brain/memory/user.md`). This is the
    /// brain's only user-scope memory file; project memory lives in the repo.
    public func userMemoryFile(_ profileId: String) -> URL {
        memoryDir(profileId).appendingPathComponent("user.md")
    }
    /// Procedural skills directory (`skills/<name>/SKILL.md`).
    public func skillsDir(_ profileId: String) -> URL {
        profileDir(profileId).appendingPathComponent("skills", isDirectory: true)
    }
    /// Provider credentials (`providers/auth.json`).
    public func providersAuthFile(_ profileId: String) -> URL {
        profileDir(profileId).appendingPathComponent("providers").appendingPathComponent("auth.json")
    }

    /// Ensures a directory exists, creating intermediates.
    public func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
