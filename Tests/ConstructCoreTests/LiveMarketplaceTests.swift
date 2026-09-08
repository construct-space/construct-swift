import Testing
import Foundation
@testable import ConstructCore

/// Hits the real my.construct.space marketplace to verify our models decode the
/// live contract. Network-dependent: skipped gracefully when offline.
@Suite("Live marketplace API", .tags(.live))
struct LiveMarketplaceTests {
    @Test("Catalog decodes into MarketplaceSpace")
    func liveCatalog() async throws {
        let api = APIClient()
        let service = MarketplaceService(api: api, config: .production)
        let page: MarketplaceService.CatalogPage
        do {
            page = try await service.list(pageSize: 5)
        } catch let APIError.transport(msg) {
            // Offline / DNS failure — don't fail the suite for environment.
            Issue.record("Skipping live test (transport): \(msg)")
            return
        }
        #expect(page.spaces.count > 0)
        let first = try #require(page.spaces.first)
        #expect(!first.id.isEmpty)
        #expect(!first.name.isEmpty)
        // The live entries embed a manifest with at least one page.
        if let manifest = first.manifest {
            #expect(!manifest.id.isEmpty)
        }
    }

    @Test("Installs a real space end-to-end from the CDN")
    func liveInstall() async throws {
        let api = APIClient()
        let service = MarketplaceService(api: api, config: .production)
        let page: MarketplaceService.CatalogPage
        do {
            page = try await service.list(pageSize: 5)
        } catch let APIError.transport(msg) {
            Issue.record("Skipping live install (transport): \(msg)")
            return
        }
        // Pick the first entry that actually has a tarball.
        guard let space = page.spaces.first(where: { $0.tarballURL != nil }) else {
            Issue.record("No catalog entry with a tarball to install")
            return
        }

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("live-install-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let installer = SpaceInstaller(paths: ConstructPaths(base: tmp))
        do {
            let installed = try await installer.install(space, profileId: "p1")
            #expect(installed.id == space.id)
            #expect(fm.fileExists(atPath: installed.bundleURL.appendingPathComponent("manifest.json").path))
        } catch let SpaceInstaller.InstallError.downloadFailed(msg) {
            Issue.record("Skipping live install (download): \(msg)")
        }
    }
}

extension Tag {
    @Tag static var live: Self
}
