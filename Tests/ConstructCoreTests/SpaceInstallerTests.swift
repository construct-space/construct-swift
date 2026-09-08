import Testing
import Foundation
@testable import ConstructCore

@Suite("SpaceInstaller")
struct SpaceInstallerTests {
    /// Builds a `<name>.space/` bundle, tars it, and returns the archive URL.
    private func makeFixtureTarball(in dir: URL, spaceId: String) throws -> URL {
        let fm = FileManager.default
        let bundle = dir.appendingPathComponent("\(spaceId).space", isDirectory: true)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        let manifest = """
        {"id":"\(spaceId)","name":"Test Space","version":"1.0.0","scopes":["app"],
         "pages":[{"path":"","label":"Home","default":true}]}
        """
        try manifest.write(to: bundle.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "window.__x=1".write(to: bundle.appendingPathComponent("app.iife.js"), atomically: true, encoding: .utf8)

        let archive = dir.appendingPathComponent("bundle.tar.gz")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-czf", archive.path, "-C", dir.path, "\(spaceId).space"]
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        return archive
    }

    @Test("Installs a bundle from a local tarball")
    func installFromTarball() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("ci-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let fixtureDir = tmp.appendingPathComponent("fixture")
        try fm.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let archive = try makeFixtureTarball(in: fixtureDir, spaceId: "test-space")

        let paths = ConstructPaths(base: tmp.appendingPathComponent("data"))
        let installer = SpaceInstaller(paths: paths)
        let installed = try await installer.install(spaceId: "test-space", tarballURL: archive, profileId: "p1")

        #expect(installed.id == "test-space")
        #expect(installed.manifest.name == "Test Space")
        #expect(installed.isUnpacked)
        // The bundle landed under the profile's spaces dir.
        #expect(installed.bundleURL.path == paths.spacesDir("p1").appendingPathComponent("test-space").path)
        #expect(fm.fileExists(atPath: installed.bundleURL.appendingPathComponent("app.iife.js").path))
    }

    @Test("Reinstall replaces the prior bundle")
    func reinstallReplaces() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("ci-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let fixtureDir = tmp.appendingPathComponent("fixture")
        try fm.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let archive = try makeFixtureTarball(in: fixtureDir, spaceId: "dup")

        let paths = ConstructPaths(base: tmp.appendingPathComponent("data"))
        let installer = SpaceInstaller(paths: paths)
        _ = try await installer.install(spaceId: "dup", tarballURL: archive, profileId: "p1")
        let second = try await installer.install(spaceId: "dup", tarballURL: archive, profileId: "p1")
        #expect(second.manifest.id == "dup")

        try installer.uninstall(spaceId: "dup", profileId: "p1")
        #expect(!fm.fileExists(atPath: paths.spacesDir("p1").appendingPathComponent("dup").path))
    }
}
