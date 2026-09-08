import Foundation
import Observation

/// Central authentication & identity state. Port of the Vue `auth` Pinia store.
///
/// Owns the signed-in user, tokens, and operating scope. Persists to
/// `auth.json` and pushes the active bearer into the shared `CredentialVault`
/// so the `APIClient` picks it up.
@MainActor
@Observable
public final class AuthStore {
    public private(set) var user: User?
    public private(set) var scope: ScopeState = .personal
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    /// The active profile id (== accounts UUID). Drives where auth.json lives.
    public var activeProfileId: String

    public var isAuthenticated: Bool { user != nil && token != nil }
    public var isDeveloper: Bool { scope.developer }
    public var isOrgScoped: Bool { scope.scope == .org }

    private var token: String?
    private var oauthToken: String?

    private let config: BackendConfig
    private let vault: CredentialVault
    private let fileStore: AuthFileStore
    private let keychain: Keychain
    private let api: APIClient

    public init(config: BackendConfig,
                vault: CredentialVault,
                api: APIClient,
                fileStore: AuthFileStore = AuthFileStore(),
                keychain: Keychain = Keychain(),
                activeProfileId: String = "default") {
        self.config = config
        self.vault = vault
        self.api = api
        self.fileStore = fileStore
        self.keychain = keychain
        self.activeProfileId = activeProfileId
    }

    /// Loads persisted credentials for the active profile and validates scope.
    public func checkAuth() async {
        guard let creds = fileStore.load(profileId: activeProfileId) else { return }
        apply(creds)
        await pushToVault()
        await refreshScope()
    }

    /// Refreshes operating scope/roles from `/api/me/scope`.
    public func refreshScope() async {
        guard isAuthenticated else { return }
        do {
            let state: ScopeState = try await api.request(.get, config.scope)
            scope = state
            if let org = state.org { setOrg(org.id) }
        } catch {
            // Non-fatal: keep last known scope. A 401 will be surfaced elsewhere.
            lastError = (error as? APIError)?.errorDescription
        }
    }

    /// Persists the current credentials and refreshes derived state.
    public func signIn(token: String, oauthToken: String?, user: User, orgId: String? = nil) async {
        self.token = token
        self.oauthToken = oauthToken
        self.user = user
        var creds = AuthCredentials(token: token, oauthToken: oauthToken, user: user, orgId: orgId)
        creds.publisher = fileStore.load(profileId: activeProfileId)?.publisher
        try? fileStore.save(creds, profileId: activeProfileId)
        await pushToVault()
        await refreshScope()
    }

    /// The current API access token, for surfaces that need it directly
    /// (e.g. the space runtime bridge). Nil when signed out.
    public func currentAccessToken() -> String? { token }

    public func signOut() async {
        token = nil
        oauthToken = nil
        user = nil
        scope = .personal
        fileStore.clear(profileId: activeProfileId)
        await vault.clear()
    }

    /// Switches the active profile and reloads its auth state.
    public func switchProfile(_ profileId: String) async {
        activeProfileId = profileId
        token = nil; oauthToken = nil; user = nil; scope = .personal
        await checkAuth()
    }

    private func setOrg(_ orgId: String) {
        Task { await vault.update(bearer: token, orgID: orgId) }
    }

    private func apply(_ creds: AuthCredentials) {
        token = creds.token
        oauthToken = creds.oauthToken
        user = creds.user
    }

    private func pushToVault() async {
        await vault.update(bearer: token, orgID: scope.org?.id)
    }
}
