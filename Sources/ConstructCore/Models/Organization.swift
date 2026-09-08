import Foundation

/// An organization the user belongs to.
public struct Organization: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var slug: String?
    public var icon: String?
    public var developerStatus: String?

    public init(id: String, name: String, slug: String? = nil, icon: String? = nil, developerStatus: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.icon = icon
        self.developerStatus = developerStatus
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, icon
        case developerStatus = "developer_status"
    }
}

/// A member of an organization.
public struct OrgMember: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var userId: String
    public var name: String?
    public var email: String?
    public var role: String
    public var department: String?
    public var status: String?

    public init(id: String, userId: String, name: String? = nil, email: String? = nil,
                role: String, department: String? = nil, status: String? = nil) {
        self.id = id
        self.userId = userId
        self.name = name
        self.email = email
        self.role = role
        self.department = department
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, name, email, role, department, status
        case userId = "user_id"
    }
}

/// An RBAC role definition with the permissions it grants.
public struct OrgRole: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var permissions: [String]

    public init(id: String, name: String, permissions: [String] = []) {
        self.id = id
        self.name = name
        self.permissions = permissions
    }
}
