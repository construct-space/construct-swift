import Foundation

/// Downloads, extracts and installs a space bundle from the marketplace CDN.
///
/// Bundles are `bundle.tar.gz` archives whose single top-level entry is a
/// `<name>.space/` directory (manifest.json, app.iife.js, style.css, ...).
/// We install them as unpacked directories under the profile's spaces dir, so
/// the SpaceHost can serve assets over the `space://` scheme.
public struct SpaceInstaller: Sendable {
    private let paths: ConstructPaths
    private let session: URLSession

    public init(paths: ConstructPaths = ConstructPaths(), session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    public enum InstallError: Error, LocalizedError {
        case noTarball
        case downloadFailed(String)
        case extractionFailed(String)
        case bundleRootNotFound
        case manifestMissing

        public var errorDescription: String? {
            switch self {
            case .noTarball: return "Space has no downloadable bundle."
            case let .downloadFailed(m): return "Download failed: \(m)"
            case let .extractionFailed(m): return "Extraction failed: \(m)"
            case .bundleRootNotFound: return "Could not find the .space bundle in the archive."
            case .manifestMissing: return "Installed bundle has no manifest.json."
            }
        }
    }

    /// Installs a catalog space for a profile, returning the installed record.
    public func install(_ space: MarketplaceSpace, profileId: String) async throws -> InstalledSpace {
        guard let tarball = space.tarballURL, let url = URL(string: tarball) else {
            throw InstallError.noTarball
        }
        return try await install(spaceId: space.id, tarballURL: url, profileId: profileId)
    }

    /// Installs from an explicit tarball URL (also used by tests with a file URL).
    public func install(spaceId: String, tarballURL: URL, profileId: String) async throws -> InstalledSpace {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("construct-install-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // 1. Obtain the archive (download remote, or copy a local file URL).
        let archive = work.appendingPathComponent("bundle.tar.gz")
        if tarballURL.isFileURL {
            try fm.copyItem(at: tarballURL, to: archive)
        } else {
            do {
                let (tmp, response) = try await session.download(from: tarballURL)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw InstallError.downloadFailed("HTTP \(http.statusCode)")
                }
                try fm.moveItem(at: tmp, to: archive)
            } catch let e as InstallError {
                throw e
            } catch {
                throw InstallError.downloadFailed(error.localizedDescription)
            }
        }

        // 2. Extract.
        let extractDir = work.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try Self.extractTarGz(archive: archive, into: extractDir)

        // 3. Locate the bundle root (a dir containing manifest.json).
        let bundleRoot = try Self.findBundleRoot(in: extractDir)

        // 4. Install into the profile's spaces dir as `<id>` (replacing any prior).
        try paths.ensureDir(paths.spacesDir(profileId))
        let dest = paths.spacesDir(profileId).appendingPathComponent(spaceId, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: bundleRoot, to: dest)

        // 5. Read the manifest.
        let manifestURL = dest.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { throw InstallError.manifestMissing }
        let manifest = try JSONDecoder().decode(SpaceManifest.self, from: data)
        return InstalledSpace(manifest: manifest, bundleURL: dest, isUnpacked: true)
    }

    /// Removes an installed space.
    public func uninstall(spaceId: String, profileId: String) throws {
        let dest = paths.spacesDir(profileId).appendingPathComponent(spaceId, isDirectory: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
    }

    /// Extracts a .tar.gz using the system `tar` (available on macOS).
    static func extractTarGz(archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", directory.path]
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw InstallError.extractionFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "tar exited \(process.terminationStatus)"
            throw InstallError.extractionFailed(msg)
        }
    }

    /// Finds the directory containing `manifest.json` within an extracted tree.
    /// Handles the common `<name>.space/` top-level wrapper.
    static func findBundleRoot(in directory: URL) throws -> URL {
        let fm = FileManager.default
        // Direct hit?
        if fm.fileExists(atPath: directory.appendingPathComponent("manifest.json").path) {
            return directory
        }
        // Single-level children (skip AppleDouble `._` entries).
        let children = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { !$0.lastPathComponent.hasPrefix("._") } ?? []
        for child in children {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir, fm.fileExists(atPath: child.appendingPathComponent("manifest.json").path) {
                return child
            }
        }
        throw InstallError.bundleRootNotFound
    }
}
