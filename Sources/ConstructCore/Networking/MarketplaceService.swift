import Foundation

/// Read access to the public marketplace catalog (`/api/marketplace`).
/// Response shapes verified against the live API.
public struct MarketplaceService: Sendable {
    private let api: APIClient
    private let config: BackendConfig

    public init(api: APIClient, config: BackendConfig) {
        self.api = api
        self.config = config
    }

    /// Paged catalog response: `{ page, pageSize, total, spaces }`.
    public struct CatalogPage: Decodable, Sendable {
        public let page: Int
        public let pageSize: Int
        public let total: Int
        public let spaces: [MarketplaceSpace]
    }

    /// Lists catalog spaces, optionally filtered by a search query.
    public func list(query: String? = nil, page: Int = 1, pageSize: Int = 24) async throws -> CatalogPage {
        var q: [String: String] = ["page": "\(page)", "pageSize": "\(pageSize)"]
        if let query, !query.isEmpty { q["q"] = query }
        return try await api.request(
            .get,
            config.marketplace.appendingPathComponent("spaces"),
            query: q,
            authenticated: false
        )
    }

    /// Fetches a single catalog entry by space id.
    public func detail(id: String) async throws -> MarketplaceSpace {
        try await api.request(
            .get,
            config.marketplace.appendingPathComponent("spaces").appendingPathComponent(id),
            authenticated: false
        )
    }
}
