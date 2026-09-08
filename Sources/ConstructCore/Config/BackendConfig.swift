import Foundation

/// Central registry of backend service endpoints.
///
/// Mirrors the URL map from the Vue app's `frontend/config` / `frontend/lib`.
/// Most services are reached through the unified gateway at `my.construct.space`
/// (paths like `/api/source`, `/api/marketplace`); a few are absolute hosts.
public struct BackendConfig: Sendable {
    /// Unified gateway host. Hosts accounts, source, marketplace, developer,
    /// billing, telemetry, notifications and storage under `/api/*`.
    public let gateway: URL
    /// Public Graph API (tenant-scoped, used by spaces).
    public let graph: URL
    /// Automation control plane (outside the gateway).
    public let conductor: URL

    public init(gateway: URL, graph: URL, conductor: URL) {
        self.gateway = gateway
        self.graph = graph
        self.conductor = conductor
    }

    /// Production defaults.
    public static let production = BackendConfig(
        gateway: URL(string: "https://my.construct.space")!,
        graph: URL(string: "https://graph.construct.space")!,
        conductor: URL(string: "https://conductor.construct.space")!
    )

    /// Reads overrides from environment / UserDefaults, falling back to production.
    /// Lets us point a dev build at staging without recompiling.
    public static func resolved() -> BackendConfig {
        let env = ProcessInfo.processInfo.environment
        func url(_ key: String, _ fallback: URL) -> URL {
            if let raw = env[key], let u = URL(string: raw) { return u }
            if let raw = UserDefaults.standard.string(forKey: key), let u = URL(string: raw) { return u }
            return fallback
        }
        return BackendConfig(
            gateway: url("CONSTRUCT_GATEWAY_URL", production.gateway),
            graph: url("CONSTRUCT_GRAPH_URL", production.graph),
            conductor: url("CONSTRUCT_CONDUCTOR_URL", production.conductor)
        )
    }
}

public extension BackendConfig {
    // Gateway-relative service roots.
    var accounts: URL { gateway.appendingPathComponent("api/accounts") }
    var source: URL { gateway.appendingPathComponent("api/source") }
    var marketplace: URL { gateway.appendingPathComponent("api/marketplace") }
    var developer: URL { gateway.appendingPathComponent("api/developer") }
    var billing: URL { gateway.appendingPathComponent("api/billing") }
    var telemetry: URL { gateway.appendingPathComponent("api/telemetry") }
    var notifications: URL { gateway.appendingPathComponent("api/notifications") }
    var storage: URL { gateway.appendingPathComponent("api/storage") }
    var preferences: URL { gateway.appendingPathComponent("api/preferences") }
    /// Session scope endpoint on the accounts service. (Verified live:
    /// `/api/accounts/me/scope` — `/api/me/scope` 404s.)
    var scope: URL { gateway.appendingPathComponent("api/accounts/me/scope") }
}
