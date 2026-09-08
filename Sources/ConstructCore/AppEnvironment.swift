import Foundation
import Observation

/// Root dependency container. Constructs and wires the shared services and
/// stores, and is injected into the SwiftUI environment. Single source of
/// truth for app-wide state, analogous to the Pinia root.
@MainActor
@Observable
public final class AppEnvironment {
    public let config: BackendConfig
    public let paths: ConstructPaths
    public let vault: CredentialVault
    public let api: APIClient

    public let auth: AuthStore
    public let profiles: ProfileStore
    public let spaces: SpacesStore
    public let accounts: AccountsService
    public let brain: BrainService
    /// Native, free on-device AI (Apple Foundation Models).
    public let foundationModels = FoundationModelService()
    /// Native system notifications (UserNotifications).
    public let notifications = NotificationService()
    /// Which spaces are pinned to the nav rail (per-profile, local).
    public let pinned = PinnedSpacesStore()
    /// Local projects (Builder / Space Developer / TUI work inside one).
    public let projects = ProjectStore()
    /// Home widget-dashboard layout (per-profile, local).
    public let homeLayout: HomeLayoutStore

    public init(config: BackendConfig = .resolved(), paths: ConstructPaths = ConstructPaths()) {
        self.config = config
        self.paths = paths

        let vault = CredentialVault()
        let api = APIClient(auth: vault)
        self.vault = vault
        self.api = api

        let profiles = ProfileStore(paths: paths)
        self.profiles = profiles

        self.auth = AuthStore(config: config, vault: vault, api: api,
                              activeProfileId: profiles.activeProfileId)

        let marketplace = MarketplaceService(api: api, config: config)
        let installer = SpaceInstaller(paths: paths)
        self.spaces = SpacesStore(paths: paths, marketplace: marketplace,
                                  installer: installer, profileId: profiles.activeProfileId)
        self.accounts = AccountsService(api: api, config: config)
        self.brain = BrainService(paths: paths)
        self.homeLayout = HomeLayoutStore(paths: paths)
    }

    /// Outcome of a login attempt.
    public enum LoginOutcome: Sendable, Equatable {
        case success
        case needsTwoFactor(pendingToken: String)
        case mustChangePassword
        case failed(String)
    }

    /// Password login, then persist via the auth store.
    public func login(email: String, password: String) async -> LoginOutcome {
        do {
            return try await complete(accounts.login(email: email, password: password))
        } catch let APIError.http(_, body) {
            return .failed(extractError(body))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Submits a 2FA code for a pending login.
    public func submitTwoFactor(pendingToken: String, code: String) async -> LoginOutcome {
        do {
            return try await complete(accounts.verifyTwoFactor(pendingToken: pendingToken, code: code))
        } catch let APIError.http(_, body) {
            return .failed(extractError(body))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func complete(_ resp: AccountsService.LoginResponse) async -> LoginOutcome {
        if let err = resp.error { return .failed(err) }
        if resp.requires2FA == true, let pending = resp.pendingToken {
            return .needsTwoFactor(pendingToken: pending)
        }
        if resp.mustChangePassword == true { return .mustChangePassword }
        guard let token = resp.accessToken, let user = resp.user else {
            return .failed("Malformed login response")
        }
        // Register + activate this user's profile so the session persists across
        // restarts (profiles.json drives the next boot's activeProfileId).
        try? profiles.create(Profile(id: user.id, name: user.name ?? user.email,
                                     email: user.email, avatar: user.avatar))
        try? profiles.switchTo(user.id)
        // Direct login returns one bearer token used for both API + identity.
        auth.activeProfileId = user.id
        await auth.signIn(token: token, oauthToken: token, user: user)
        spaces.setProfile(user.id)
        return .success
    }

    private func extractError(_ body: String) -> String {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            return err
        }
        return body.isEmpty ? "Login failed" : body
    }

    /// Switches the active profile: persist it, reload that profile's auth
    /// session and installed spaces (shared with the Tauri app / CLI).
    public func switchProfile(_ profileId: String) async {
        try? profiles.switchTo(profileId)
        spaces.setProfile(profileId)
        await auth.switchProfile(profileId)
        spaces.loadInstalled()
        pinned.load(profile: profileId)
        homeLayout.load(profile: profileId)
    }

    /// Boots the app: load profiles, restore auth, scan installed spaces.
    public func bootstrap() async {
        profiles.load()
        auth.activeProfileId = profiles.activeProfileId
        spaces.setProfile(profiles.activeProfileId)
        await auth.checkAuth()
        spaces.loadInstalled()
        pinned.load(profile: profiles.activeProfileId)
        homeLayout.load(profile: profiles.activeProfileId)
        projects.scan()
        foundationModels.refreshAvailability()
        // Start the brain operator as a background service (non-blocking).
        let pid = profiles.activeProfileId
        Task { await brain.start(profileId: pid) }
    }
}
