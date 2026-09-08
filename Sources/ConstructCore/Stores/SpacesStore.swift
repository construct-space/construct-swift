import Foundation
import Observation

/// Tracks installed and marketplace spaces. Combines the on-disk installed
/// bundles with the remote catalog. Spaces themselves render in a WKWebView
/// via the SpaceHost module.
@MainActor
@Observable
public final class SpacesStore {
    public private(set) var installed: [InstalledSpace] = []
    public private(set) var catalog: [MarketplaceSpace] = []
    public private(set) var isLoadingCatalog = false
    public private(set) var lastError: String?

    /// Space ids currently being installed (for UI progress).
    public private(set) var installing: Set<String> = []

    private let paths: ConstructPaths
    private let marketplace: MarketplaceService
    private let installer: SpaceInstaller
    private var profileId: String

    public init(paths: ConstructPaths, marketplace: MarketplaceService,
                installer: SpaceInstaller = SpaceInstaller(), profileId: String = "default") {
        self.paths = paths
        self.marketplace = marketplace
        self.installer = installer
        self.profileId = profileId
    }

    public func isInstalled(_ spaceId: String) -> Bool {
        installed.contains { $0.id == spaceId }
    }

    public func setProfile(_ profileId: String) {
        self.profileId = profileId
        loadInstalled()
    }

    /// Scans the per-profile spaces directory for installed bundles.
    public func loadInstalled() {
        let dir = paths.spacesDir(profileId)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            installed = []
            return
        }
        var result: [InstalledSpace] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if let manifest = readManifest(at: url) {
                    result.append(InstalledSpace(manifest: manifest, bundleURL: url, isUnpacked: true))
                }
            } else if url.pathExtension == "space" {
                // Packed .space ZIP bundle (the format the Tauri app/CLI use).
                if let manifest = Self.readManifestFromZip(url) {
                    result.append(InstalledSpace(manifest: manifest, bundleURL: url, isUnpacked: false))
                }
            }
        }
        installed = result.sorted { $0.manifest.name < $1.manifest.name }
    }

    /// Loads the remote catalog.
    public func loadCatalog(query: String? = nil) async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            catalog = try await marketplace.list(query: query).spaces
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? "\(error)"
        }
    }

    /// Installs a marketplace space, then refreshes the installed list.
    @discardableResult
    public func install(_ space: MarketplaceSpace) async -> Bool {
        guard !installing.contains(space.id) else { return false }
        installing.insert(space.id)
        defer { installing.remove(space.id) }
        do {
            _ = try await installer.install(space, profileId: profileId)
            loadInstalled()
            return true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// Uninstalls a space and refreshes the installed list.
    public func uninstall(_ spaceId: String) {
        do {
            try installer.uninstall(spaceId: spaceId, profileId: profileId)
            loadInstalled()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Reads `manifest.json` from a `.space` ZIP via the system `unzip`.
    static func readManifestFromZip(_ archive: URL) -> SpaceManifest? {
        guard let data = unzipEntry(archive, "manifest.json") else { return nil }
        return try? JSONDecoder().decode(SpaceManifest.self, from: data)
    }

    /// Returns the bytes of a single entry from a ZIP using `unzip -p`.
    static func unzipEntry(_ archive: URL, _ entry: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", archive.path, entry]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    /// Reads `manifest.json` from an unpacked space directory.
    private func readManifest(at url: URL) -> SpaceManifest? {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard isDir else { return nil }
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(SpaceManifest.self, from: data)
    }
}
