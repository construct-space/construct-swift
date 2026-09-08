import Foundation

/// The authenticated user (accounts service identity). Decoding tolerates the
/// several shapes the accounts API returns (login profile vs org member),
/// e.g. `uuid` vs `id`, `avatar_url` vs `avatar`, `name` vs `first/last_name`.
public struct User: Codable, Identifiable, Hashable, Sendable {
    /// Stable accounts UUID (used as the profile id).
    public let id: String
    public var email: String
    public var name: String?
    public var avatar: String?
    /// Personal developer enrollment status, if any.
    public var developerStatus: String?

    public init(id: String, email: String, name: String? = nil, avatar: String? = nil, developerStatus: String? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.avatar = avatar
        self.developerStatus = developerStatus
    }

    enum CodingKeys: String, CodingKey {
        case id, uuid, email, name, avatar
        case avatarURL = "avatar_url"
        case firstName = "first_name"
        case lastName = "last_name"
        case developerStatus = "developer_status"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Prefer the stable UUID; fall back to id (string or numeric).
        if let uuid = try? c.decode(String.self, forKey: .uuid) {
            id = uuid
        } else if let sid = try? c.decode(String.self, forKey: .id) {
            id = sid
        } else if let nid = try? c.decode(Int.self, forKey: .id) {
            id = String(nid)
        } else {
            id = ""
        }
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        if let n = try? c.decode(String.self, forKey: .name), !n.isEmpty {
            name = n
        } else {
            let first = try? c.decode(String.self, forKey: .firstName)
            let last = try? c.decode(String.self, forKey: .lastName)
            let joined = [first, last].compactMap { $0 }.joined(separator: " ")
            name = joined.isEmpty ? nil : joined
        }
        avatar = (try? c.decode(String.self, forKey: .avatar)) ?? (try? c.decode(String.self, forKey: .avatarURL))
        developerStatus = try? c.decode(String.self, forKey: .developerStatus)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(email, forKey: .email)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(avatar, forKey: .avatar)
        try c.encodeIfPresent(developerStatus, forKey: .developerStatus)
    }
}

/// A local profile (one per accounts UUID). Profiles isolate auth, org,
/// preferences and on-disk data. Desktop-native concept.
public struct Profile: Codable, Identifiable, Hashable, Sendable {
    /// Equals the accounts UUID.
    public let id: String
    public var name: String
    public var email: String?
    public var avatar: String?

    public init(id: String, name: String, email: String? = nil, avatar: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.avatar = avatar
    }
}

/// Operating scope returned by `/api/me/scope`. `user` = personal,
/// `org` = acting within an organization.
public enum Scope: String, Codable, Sendable {
    case user
    case org
}

/// Result of a scope refresh: who you are right now and what you can do.
public struct ScopeState: Codable, Sendable {
    public var scope: Scope
    public var roles: [String]
    public var developer: Bool
    public var org: Organization?

    public init(scope: Scope, roles: [String] = [], developer: Bool = false, org: Organization? = nil) {
        self.scope = scope
        self.roles = roles
        self.developer = developer
        self.org = org
    }

    public static let personal = ScopeState(scope: .user)
}
