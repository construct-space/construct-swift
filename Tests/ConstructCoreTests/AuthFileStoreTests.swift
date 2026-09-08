import Testing
import Foundation
@testable import ConstructCore

@Suite("AuthFileStore + ConstructPaths")
struct AuthFileStoreTests {
    /// Builds a store rooted in a unique temp directory.
    private func makeStore() -> (AuthFileStore, ConstructPaths, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("construct-test-\(UUID().uuidString)")
        let paths = ConstructPaths(base: tmp)
        return (AuthFileStore(paths: paths), paths, tmp)
    }

    @Test("Save then load returns the same credentials")
    func saveLoad() throws {
        let (store, _, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let creds = AuthCredentials(token: "t", user: User(id: "u1", email: "a@b.com"))
        try store.save(creds, profileId: "p1")
        let loaded = store.load(profileId: "p1")
        #expect(loaded?.token == "t")
        #expect(loaded?.user?.id == "u1")
    }

    @Test("Save merges into existing auth.json, preserving unknown fields")
    func savePreservesExistingFields() throws {
        let (store, paths, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Simulate an auth.json written by the Tauri app/CLI with a publisher
        // block and extra user fields we don't model.
        try FileManager.default.createDirectory(at: paths.profileDir("p1"), withIntermediateDirectories: true)
        let existing = """
        {"publisher":{"name":"Me","kind":"user","api_key":"csk_live_abc"},
         "user":{"id":"u1","email":"a@b.com","username":"me","first_name":"A"},
         "token":"old","authenticated":true}
        """
        try existing.write(to: paths.authFile("p1"), atomically: true, encoding: .utf8)

        try store.save(AuthCredentials(token: "new", oauthToken: "oauth",
                                       user: User(id: "u1", email: "a@b.com", name: "A B")),
                       profileId: "p1")

        let raw = try Data(contentsOf: paths.authFile("p1"))
        let obj = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        #expect((obj["token"] as? String) == "new")                        // updated
        #expect((obj["oauth_token"] as? String) == "oauth")
        let publisher = obj["publisher"] as? [String: Any]
        #expect((publisher?["api_key"] as? String) == "csk_live_abc")      // preserved
        let user = obj["user"] as? [String: Any]
        #expect((user?["username"] as? String) == "me")                    // preserved
        #expect((user?["name"] as? String) == "A B")                       // updated
    }

    @Test("Clear removes the credentials file")
    func clear() throws {
        let (store, _, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try store.save(AuthCredentials(token: "t"), profileId: "p1")
        store.clear(profileId: "p1")
        #expect(store.load(profileId: "p1") == nil)
    }

    @Test("Paths are profile-scoped under the base directory")
    func pathLayout() {
        // Layout matches the Tauri app/CLI: <base>/profiles/<id>/...
        let base = URL(fileURLWithPath: "/tmp/construct-base")
        let paths = ConstructPaths(base: base)
        #expect(paths.authFile("p1").path == "/tmp/construct-base/profiles/p1/auth.json")
        #expect(paths.spacesDir("p1").path == "/tmp/construct-base/profiles/p1/spaces")
        #expect(paths.profilesFile.path == "/tmp/construct-base/profiles.json")
    }
}
