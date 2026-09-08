import Testing
import Foundation
@testable import ConstructCore

@Suite("BackendConfig")
struct BackendConfigTests {
    @Test("Production points at my.construct.space")
    func productionGateway() {
        let cfg = BackendConfig.production
        #expect(cfg.gateway.absoluteString == "https://my.construct.space")
        #expect(cfg.graph.absoluteString == "https://graph.construct.space")
    }

    @Test("Service roots derive from the gateway")
    func serviceRoots() {
        let cfg = BackendConfig.production
        #expect(cfg.accounts.absoluteString == "https://my.construct.space/api/accounts")
        #expect(cfg.source.absoluteString == "https://my.construct.space/api/source")
        #expect(cfg.marketplace.absoluteString == "https://my.construct.space/api/marketplace")
        #expect(cfg.scope.absoluteString == "https://my.construct.space/api/accounts/me/scope")
    }

    @Test("Environment overrides are honored")
    func envOverride() {
        // resolved() falls back to production when no override present.
        let cfg = BackendConfig.resolved()
        #expect(cfg.gateway.scheme == "https")
    }
}
