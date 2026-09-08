import Foundation

/// On-disk auth state, persisted to `profiles/<id>/auth.json`.
/// This is the unified format the desktop app owns and the CLI reads.
///
/// `token` is the JWT used for API calls; `oauthToken` is the accounts-service
/// identity token used for profile/scope. `publisher` holds developer keys.
public struct AuthCredentials: Codable, Sendable {
    public var token: String?
    public var oauthToken: String?
    public var user: User?
    public var orgId: String?
    /// Publisher credentials block (`csk_live_*`) when developer-enrolled.
    public var publisher: [String: String]?

    public init(token: String? = nil, oauthToken: String? = nil, user: User? = nil,
                orgId: String? = nil, publisher: [String: String]? = nil) {
        self.token = token
        self.oauthToken = oauthToken
        self.user = user
        self.orgId = orgId
        self.publisher = publisher
    }

    enum CodingKeys: String, CodingKey {
        case token, user, publisher
        case oauthToken = "oauth_token"
        case orgId = "org_id"
    }
}

/// Reads/writes `auth.json` for a profile. Mirrors `loadFromApp` in the CLI.
public struct AuthFileStore: Sendable {
    private let paths: ConstructPaths

    public init(paths: ConstructPaths = ConstructPaths()) {
        self.paths = paths
    }

    public func load(profileId: String) -> AuthCredentials? {
        let url = paths.authFile(profileId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        return try? dec.decode(AuthCredentials.self, from: data)
    }

    /// Writes auth.json in the format the Tauri app + CLI share, merging into
    /// any existing file so we never drop fields we don't model (publisher
    /// api_key, username/first_name/last_name, etc.). Only the fields we own
    /// are updated.
    public func save(_ creds: AuthCredentials, profileId: String) throws {
        try paths.ensureDir(paths.profileDir(profileId))
        let url = paths.authFile(profileId)

        // Start from the existing file so unknown fields survive.
        var root: [String: Any] = {
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            return [:]
        }()

        if let token = creds.token { root["token"] = token }
        if let oauth = creds.oauthToken { root["oauth_token"] = oauth }
        if let orgId = creds.orgId { root["org_id"] = orgId }
        root["authenticated"] = creds.token != nil

        // Merge the user object rather than replacing it wholesale.
        if let user = creds.user {
            var u = (root["user"] as? [String: Any]) ?? [:]
            u["id"] = user.id
            u["email"] = user.email
            if let name = user.name { u["name"] = name }
            if let avatar = user.avatar { u["avatar_url"] = avatar }
            root["user"] = u
        }

        // ISO8601 stamp like the host.
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        root["updated_at"] = fmt.string(from: Date())

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    public func clear(profileId: String) {
        try? FileManager.default.removeItem(at: paths.authFile(profileId))
    }
}
