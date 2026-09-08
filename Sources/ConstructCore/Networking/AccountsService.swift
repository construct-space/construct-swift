import Foundation

/// Password / token auth against the accounts service.
///
/// Verified against the live API: `POST {gateway}/api/auth/login` with
/// `{email, password, client_id}` returns a bearer-token response
/// `{access_token, refresh_token?, scope?, user}` (same shape as /oauth/token).
/// Passing `client_id` switches the server from session-cookie to bearer mode.
public struct AccountsService: Sendable {
    /// OAuth client id the desktop app identifies as (appConfig.oauthClientId).
    public static let clientID = "construct_app"

    private let api: APIClient
    private let config: BackendConfig

    public init(api: APIClient, config: BackendConfig) {
        self.api = api
        self.config = config
    }

    struct LoginRequest: Encodable {
        let email: String
        let password: String
        let client_id: String
    }

    struct VerifyTwoFactorRequest: Encodable {
        let pending_token: String
        let code: String
        let client_id: String
    }

    /// Union of the success / 2FA / must-reset responses.
    public struct LoginResponse: Decodable, Sendable {
        public let accessToken: String?
        public let refreshToken: String?
        public let scope: String?
        public let user: User?

        public let requires2FA: Bool?
        public let pendingToken: String?
        public let mustChangePassword: Bool?
        public let error: String?

        enum CodingKeys: String, CodingKey {
            case scope, user, error
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case requires2FA = "requires_2fa"
            case pendingToken = "pending_token"
            case mustChangePassword = "must_change_password"
        }
    }

    private var loginURL: URL { config.gateway.appendingPathComponent("api/auth/login") }
    private var verify2FAURL: URL { config.gateway.appendingPathComponent("api/auth/verify-2fa") }

    public func login(email: String, password: String) async throws -> LoginResponse {
        try await api.request(.post, loginURL,
                              body: LoginRequest(email: email, password: password, client_id: Self.clientID),
                              authenticated: false)
    }

    public func verifyTwoFactor(pendingToken: String, code: String) async throws -> LoginResponse {
        try await api.request(.post, verify2FAURL,
                              body: VerifyTwoFactorRequest(pending_token: pendingToken, code: code, client_id: Self.clientID),
                              authenticated: false)
    }
}
