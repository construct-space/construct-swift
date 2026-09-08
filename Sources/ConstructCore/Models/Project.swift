import Foundation

/// Where a project lives.
public enum ProjectKind: String, Codable, Sendable {
    /// Local filesystem-only project (personal, never synced).
    case local
    /// Org project synced via source-api.
    case org
}

/// A project the user works in. Local projects are filesystem state;
/// org projects are backed by source-api.
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var path: String?
    public var kind: ProjectKind
    /// Space ids enabled within this project.
    public var spaces: [String]
    public var updatedAt: Date?

    public init(id: String, name: String, path: String? = nil, kind: ProjectKind = .local,
                spaces: [String] = [], updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.spaces = spaces
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, path, kind, spaces
        case updatedAt = "updated_at"
    }
}

/// A dock / quick-access shortcut.
public struct PinnedItem: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case project, folder, page, space, link, task
    }

    public let id: String
    public var kind: Kind
    public var label: String
    public var target: String
    public var icon: String?

    public init(id: String, kind: Kind, label: String, target: String, icon: String? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.target = target
        self.icon = icon
    }
}
