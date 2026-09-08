import Testing
import Foundation
@testable import ConstructCore

@Suite("Model coding")
struct ModelCodingTests {
    @Test("User decodes snake_case developer_status")
    func userDecoding() throws {
        let json = #"{"id":"u1","email":"a@b.com","name":"Ada","developer_status":"active"}"#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(user.id == "u1")
        #expect(user.email == "a@b.com")
        #expect(user.name == "Ada")
        #expect(user.developerStatus == "active")
    }

    @Test("AuthCredentials round-trips through JSON")
    func authCredentialsRoundTrip() throws {
        let creds = AuthCredentials(
            token: "jwt",
            oauthToken: "oauth",
            user: User(id: "u1", email: "a@b.com"),
            orgId: "org1",
            publisher: ["key": "csk_live_x"]
        )
        let data = try JSONEncoder().encode(creds)
        let decoded = try JSONDecoder().decode(AuthCredentials.self, from: data)
        #expect(decoded.token == "jwt")
        #expect(decoded.oauthToken == "oauth")
        #expect(decoded.orgId == "org1")
        #expect(decoded.user?.id == "u1")
        #expect(decoded.publisher?["key"] == "csk_live_x")
    }

    @Test("SpaceManifest decodes the live marketplace shape")
    func manifestDecoding() throws {
        // Mirrors a real /api/marketplace/spaces manifest object.
        let json = """
        {"id":"maps","name":"Maps","version":"0.1.12","icon":"i-lucide-map",
         "author":"Construct","projectAware":false,"hostApiVersion":"^0.2.0",
         "scopes":["app"],
         "pages":[{"icon":"i-lucide-map","path":"","label":"Map","default":true},
                  {"icon":"i-lucide-map-pin","path":"places","label":"Places"}],
         "navigation":{"to":"maps","icon":"i-lucide-map","label":"Maps","order":85}}
        """
        let m = try JSONDecoder().decode(SpaceManifest.self, from: Data(json.utf8))
        #expect(m.id == "maps")
        #expect(m.projectAware == false)
        #expect(m.scopes == [.app])
        #expect(m.pages.first?.isDefault == true)
        #expect(m.pages.first?.path == "")
        #expect(m.navigation?.order == 85)
        #expect(m.hostApiVersion == "^0.2.0")
    }

    @Test("SpaceManifest accepts author as string or object")
    func authorBothForms() throws {
        let asString = #"{"id":"a","name":"A","version":"1","author":"Construct"}"#
        let asObject = #"{"id":"a","name":"A","version":"1","author":{"name":"Construct"}}"#
        let m1 = try JSONDecoder().decode(SpaceManifest.self, from: Data(asString.utf8))
        let m2 = try JSONDecoder().decode(SpaceManifest.self, from: Data(asObject.utf8))
        #expect(m1.author == "Construct")
        #expect(m2.author == "Construct")
    }

    @Test("MarketplaceSpace decodes mixed camel/snake fields")
    func marketplaceSpaceDecoding() throws {
        let json = """
        {"id":"maps","name":"Maps","description":"d","icon":"i-lucide-map",
         "version":"0.1.12","host_api_version":"^0.2.0","tarball_url":"https://x/y",
         "scopes":["app"],"projectAware":false,"visibility":"public",
         "publisher_slug":"construct","publisher_name":"Construct",
         "installs_7d":3,"installs_30d":9,"downloads":42,"updated_at":"2026-01-01"}
        """
        let s = try JSONDecoder().decode(MarketplaceSpace.self, from: Data(json.utf8))
        #expect(s.id == "maps")
        #expect(s.hostApiVersion == "^0.2.0")
        #expect(s.tarballURL == "https://x/y")
        #expect(s.publisherName == "Construct")
        #expect(s.installs7d == 3)
        #expect(s.downloads == 42)
    }

    @Test("ScopeState defaults to personal")
    func scopeDefault() {
        #expect(ScopeState.personal.scope == .user)
        #expect(ScopeState.personal.developer == false)
    }
}
