import Foundation
import ConstructCore

/// Read access to a space bundle's files. Mirrors the TS `SpaceSource`
/// abstraction (Zip vs Directory). The host loads the JS entry, CSS and
/// manifest through this interface and serves assets to the webview.
public protocol SpaceBundleSource: Sendable {
    var spaceId: String { get }
    func readText(_ entry: String) throws -> String
    func readBytes(_ entry: String) throws -> Data
    func exists(_ entry: String) -> Bool
    func manifest() throws -> SpaceManifest
}

public enum SpaceBundleError: Error, LocalizedError {
    case notFound(String)
    case checksumMismatch(expected: String, actual: String)
    case invalidManifest(String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(e): return "Bundle entry not found: \(e)"
        case let .checksumMismatch(expected, actual):
            return "Checksum mismatch: expected \(expected), got \(actual)"
        case let .invalidManifest(m): return "Invalid manifest: \(m)"
        }
    }
}

/// Reads an unpacked space directory (dev-linked or extracted bundle).
public struct DirectorySpaceSource: SpaceBundleSource {
    public let spaceId: String
    public let root: URL

    public init(spaceId: String, root: URL) {
        self.spaceId = spaceId
        self.root = root
    }

    private func url(for entry: String) -> URL {
        root.appendingPathComponent(entry)
    }

    public func readText(_ entry: String) throws -> String {
        let u = url(for: entry)
        guard let data = try? Data(contentsOf: u) else { throw SpaceBundleError.notFound(entry) }
        return String(decoding: data, as: UTF8.self)
    }

    public func readBytes(_ entry: String) throws -> Data {
        let u = url(for: entry)
        guard let data = try? Data(contentsOf: u) else { throw SpaceBundleError.notFound(entry) }
        return data
    }

    public func exists(_ entry: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: entry).path)
    }

    public func manifest() throws -> SpaceManifest {
        let data = try readBytes("manifest.json")
        do {
            return try JSONDecoder().decode(SpaceManifest.self, from: data)
        } catch {
            throw SpaceBundleError.invalidManifest("\(error)")
        }
    }
}

/// Reads a packed `.space` ZIP bundle lazily via the system `unzip` — the
/// format the Tauri app + CLI install. Entries are at the archive root
/// (manifest.json, app.iife.js, style.css, ...).
public struct ZipSpaceSource: SpaceBundleSource {
    public let spaceId: String
    public let archive: URL

    public init(spaceId: String, archive: URL) {
        self.spaceId = spaceId
        self.archive = archive
    }

    public func readBytes(_ entry: String) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", archive.path, entry]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw SpaceBundleError.notFound(entry) }
        return data
    }

    public func readText(_ entry: String) throws -> String {
        String(decoding: try readBytes(entry), as: UTF8.self)
    }

    public func exists(_ entry: String) -> Bool {
        (try? readBytes(entry)) != nil
    }

    public func manifest() throws -> SpaceManifest {
        do { return try JSONDecoder().decode(SpaceManifest.self, from: try readBytes("manifest.json")) }
        catch { throw SpaceBundleError.invalidManifest("\(error)") }
    }
}
