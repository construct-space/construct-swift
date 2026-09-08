import Foundation

/// Thread-safe holder of the credentials the `APIClient` attaches to requests.
/// The `AuthStore` (MainActor) writes into it; the `APIClient` (actor) reads
/// from it. Decouples UI state from the networking layer.
public actor CredentialVault: AuthProvider {
    private var _bearer: String?
    private var _apiKey: String?
    private var _orgID: String?

    public init() {}

    public func update(bearer: String?, apiKey: String? = nil, orgID: String? = nil) {
        _bearer = bearer
        _apiKey = apiKey
        _orgID = orgID
    }

    public func clear() {
        _bearer = nil
        _apiKey = nil
        _orgID = nil
    }

    public func bearerToken() async -> String? { _bearer }
    public func apiKey() async -> String? { _apiKey }
    public func orgID() async -> String? { _orgID }
}
