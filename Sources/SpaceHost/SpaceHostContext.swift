import Foundation

/// The runtime services a running space can call back into. The app supplies
/// real implementations (backed by `AppEnvironment`); SpaceHost wires them to
/// the JS `window.construct` object. Mirrors the TS runtime context.
public struct SpaceHostContext: Sendable {
    public struct Config: Sendable {
        public var graphURL: String
        public var apiBase: String
        public init(graphURL: String, apiBase: String) {
            self.graphURL = graphURL
            self.apiBase = apiBase
        }
    }

    public var config: Config
    public var spaceId: String
    public var projectId: String?
    public var scope: String
    /// Initial in-space route path (e.g. "" or "places").
    public var initialPath: String?

    /// auth.getAccessToken()
    public var accessToken: @Sendable () async -> String?
    /// auth.getUserId()
    public var userId: @Sendable () -> String?

    /// storage.get / set / remove (per-space key/value).
    public var storageGet: @Sendable (String) async -> String?
    public var storageSet: @Sendable (String, String) async -> Void
    public var storageRemove: @Sendable (String) async -> Void

    /// graph.query(query, variables, spaceId) -> JSON result. spaceId is the
    /// active space at call time (lets Home widgets hit their own tenant).
    public var graphQuery: @Sendable (String, [String: AnyCodableValue], String?) async throws -> AnyCodableValue

    /// operator.send(type, payload). Host enforces the `media.`/`storage.`
    /// allowlist before this is called.
    public var operatorSend: @Sendable (String, [String: AnyCodableValue]) async throws -> AnyCodableValue

    /// shell.openUrl(url) — opens in the system browser.
    public var openURL: @Sendable (String) -> Void

    public init(
        config: Config,
        spaceId: String,
        projectId: String? = nil,
        scope: String = "app",
        initialPath: String? = nil,
        accessToken: @escaping @Sendable () async -> String?,
        userId: @escaping @Sendable () -> String?,
        storageGet: @escaping @Sendable (String) async -> String?,
        storageSet: @escaping @Sendable (String, String) async -> Void,
        storageRemove: @escaping @Sendable (String) async -> Void,
        graphQuery: @escaping @Sendable (String, [String: AnyCodableValue], String?) async throws -> AnyCodableValue,
        operatorSend: @escaping @Sendable (String, [String: AnyCodableValue]) async throws -> AnyCodableValue,
        openURL: @escaping @Sendable (String) -> Void
    ) {
        self.config = config
        self.spaceId = spaceId
        self.projectId = projectId
        self.scope = scope
        self.initialPath = initialPath
        self.accessToken = accessToken
        self.userId = userId
        self.storageGet = storageGet
        self.storageSet = storageSet
        self.storageRemove = storageRemove
        self.graphQuery = graphQuery
        self.operatorSend = operatorSend
        self.openURL = openURL
    }
}

/// Methods a space may invoke on `operator.send` are restricted to these
/// prefixes (matches the TS host filter). Anything else is rejected.
public enum SpaceOperatorPolicy {
    public static let allowedPrefixes = ["media.", "storage."]
    public static func isAllowed(_ method: String) -> Bool {
        allowedPrefixes.contains { method.hasPrefix($0) }
    }
}
