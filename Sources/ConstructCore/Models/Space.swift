import Foundation

/// Which surfaces a space targets.
public enum SpaceScope: String, Codable, Sendable {
    case app
    case org
}

/// A space's `manifest.json` — the metadata the host needs to render and route
/// a space. Field shapes verified against the live marketplace API. Spaces
/// themselves run as web bundles in a WKWebView.
public struct SpaceManifest: Codable, Hashable, Sendable {
    /// A routable page within the space. Paths have no leading slash.
    public struct Page: Codable, Hashable, Sendable {
        public var path: String
        public var label: String?
        public var icon: String?
        public var isDefault: Bool?

        public init(path: String, label: String? = nil, icon: String? = nil, isDefault: Bool? = nil) {
            self.path = path
            self.label = label
            self.icon = icon
            self.isDefault = isDefault
        }

        enum CodingKeys: String, CodingKey {
            case path, label, icon
            case isDefault = "default"
        }
    }

    /// Sidebar navigation hint.
    public struct Navigation: Codable, Hashable, Sendable {
        public var to: String?
        public var icon: String?
        public var label: String?
        public var order: Int?
    }

    /// A dashboard widget the space provides (rendered on Home).
    public struct Widget: Codable, Hashable, Sendable {
        public var id: String
        public var name: String?
        public var icon: String?
        public var defaultSize: String?
        public var sizes: [String: String]?  // sizeKey -> component path
    }

    /// Build/integrity metadata (present on packaged bundles, not in catalog).
    public struct Build: Codable, Hashable, Sendable {
        /// SHA-256 of the JS bundle, verified before execution.
        public var checksum: String?
        /// ECDSA P-256 signature over the bundle, for published spaces.
        public var actionsSignature: String?
    }

    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var icon: String?
    public var author: String?
    public var pages: [Page]
    public var scopes: [SpaceScope]
    public var projectAware: Bool
    public var navigation: Navigation?
    public var widgets: [Widget]
    public var hostApiVersion: String?
    public var build: Build?

    public init(id: String, name: String, version: String, description: String? = nil,
                icon: String? = nil, author: String? = nil, pages: [Page] = [],
                scopes: [SpaceScope] = [.app], projectAware: Bool = false,
                navigation: Navigation? = nil, widgets: [Widget] = [],
                hostApiVersion: String? = nil, build: Build? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.icon = icon
        self.author = author
        self.pages = pages
        self.scopes = scopes
        self.projectAware = projectAware
        self.navigation = navigation
        self.widgets = widgets
        self.hostApiVersion = hostApiVersion
        self.build = build
    }

    enum CodingKeys: String, CodingKey {
        case id, name, version, description, icon, author, pages, scopes, navigation, widgets, build
        case projectAware
        case hostApiVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
        description = try c.decodeIfPresent(String.self, forKey: .description)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        // `author` is a string in the catalog but an object {name} in packaged
        // bundles — accept either.
        if let s = try? c.decodeIfPresent(String.self, forKey: .author) {
            author = s
        } else if let obj = try? c.decodeIfPresent([String: String].self, forKey: .author) {
            author = obj["name"]
        } else {
            author = nil
        }
        pages = try c.decodeIfPresent([Page].self, forKey: .pages) ?? []
        scopes = try c.decodeIfPresent([SpaceScope].self, forKey: .scopes) ?? [.app]
        projectAware = try c.decodeIfPresent(Bool.self, forKey: .projectAware) ?? false
        navigation = try c.decodeIfPresent(Navigation.self, forKey: .navigation)
        widgets = (try? c.decodeIfPresent([Widget].self, forKey: .widgets)) ?? []
        hostApiVersion = try c.decodeIfPresent(String.self, forKey: .hostApiVersion)
        build = try c.decodeIfPresent(Build.self, forKey: .build)
    }
}

/// An installed space on disk (resolved bundle).
public struct InstalledSpace: Identifiable, Hashable, Sendable {
    public var id: String { manifest.id }
    public var manifest: SpaceManifest
    /// Path to the `.space` file or unpacked directory.
    public var bundleURL: URL
    /// True if the bundle is an unpacked directory (dev-linked).
    public var isUnpacked: Bool

    public init(manifest: SpaceManifest, bundleURL: URL, isUnpacked: Bool) {
        self.manifest = manifest
        self.bundleURL = bundleURL
        self.isUnpacked = isUnpacked
    }
}

/// A marketplace catalog entry. Field shapes verified against the live
/// `/api/marketplace/spaces` response (mixed camelCase/snake_case).
public struct MarketplaceSpace: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var description: String?
    public var icon: String?
    public var version: String?
    public var hostApiVersion: String?
    public var manifest: SpaceManifest?
    public var tarballURL: String?
    public var scopes: [SpaceScope]?
    public var projectAware: Bool?
    public var visibility: String?
    public var publisherSlug: String?
    public var publisherName: String?
    public var category: String?
    public var tags: [String]?
    public var downloads: Int?
    public var installs7d: Int?
    public var installs30d: Int?
    public var updatedAt: String?

    public init(id: String, name: String, description: String? = nil, icon: String? = nil,
                version: String? = nil, manifest: SpaceManifest? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.version = version
        self.manifest = manifest
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, version, manifest, scopes, projectAware
        case visibility, category, tags, downloads
        case hostApiVersion = "host_api_version"
        case tarballURL = "tarball_url"
        case publisherSlug = "publisher_slug"
        case publisherName = "publisher_name"
        case installs7d = "installs_7d"
        case installs30d = "installs_30d"
        case updatedAt = "updated_at"
    }
}
