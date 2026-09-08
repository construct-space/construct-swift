import Foundation

public enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case http(status: Int, body: String)
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case let .http(status, body): return "HTTP \(status): \(body)"
        case let .decoding(msg): return "Decoding error: \(msg)"
        case let .transport(msg): return "Network error: \(msg)"
        }
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

/// Supplies the credentials/headers attached to each request. Implemented by
/// the auth layer so the client never owns token storage directly.
public protocol AuthProvider: Sendable {
    /// Bearer JWT for API calls (source/org/billing/developer), if signed in.
    func bearerToken() async -> String?
    /// Optional per-space API key header (`X-API-Key`).
    func apiKey() async -> String?
    /// Active org id, sent as `X-Auth-Org-ID` when acting in org scope.
    func orgID() async -> String?
}

/// A minimal async HTTP client shared by every service wrapper.
/// Mirrors the Vue `useApi()` composable (Bearer + X-API-Key + 10s timeout).
public actor APIClient {
    private let session: URLSession
    private let auth: AuthProvider?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(auth: AuthProvider? = nil, session: URLSession? = nil) {
        self.auth = auth
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 30
            cfg.waitsForConnectivity = true
            self.session = URLSession(configuration: cfg)
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    /// Performs a request and decodes the JSON body into `T`.
    public func request<T: Decodable>(
        _ method: HTTPMethod,
        _ url: URL,
        query: [String: String] = [:],
        body: Encodable? = nil,
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await requestData(method, url, query: query, body: body, headers: headers, authenticated: authenticated)
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }
    }

    /// Performs a request and returns the raw body.
    @discardableResult
    public func requestData(
        _ method: HTTPMethod,
        _ url: URL,
        query: [String: String] = [:],
        body: Encodable? = nil,
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> Data {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let finalURL = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: finalURL)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        if authenticated, let auth {
            if let token = await auth.bearerToken() {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            if let key = await auth.apiKey() {
                req.setValue(key, forHTTPHeaderField: "X-API-Key")
            }
            if let org = await auth.orgID() {
                req.setValue(org, forHTTPHeaderField: "X-Auth-Org-ID")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport("\(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: http.statusCode, body: bodyText)
        }
        return data
    }
}

/// Sentinel for endpoints with no meaningful body.
public struct EmptyResponse: Decodable, Sendable { public init() {} }

/// Type-erasing wrapper so `Encodable` existentials can be encoded.
struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
