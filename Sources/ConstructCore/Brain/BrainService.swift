import Foundation
import Observation

/// Manages the Go "brain" operator as a background service and talks to it over
/// its loopback HTTP API (`/v1/request`, `/v1/stream`). Swift equivalent of the
/// Tauri `brain.rs` — the brain itself is the unmodified Go binary, bundled as a
/// sidecar resource.
///
/// Wire protocol (brain/wire): Request `{id,type,payload}` →
/// Response `{id,success,data,error,done}`; auth via `Authorization: Bearer
/// <token>` where the token is a shared secret we generate and pass through
/// `CONSTRUCT_BRIDGE_TOKEN`.
@MainActor
@Observable
public final class BrainService {
    public enum Status: Equatable, Sendable {
        case stopped, starting, running
        case failed(String)

        public var isRunning: Bool { self == .running }
    }

    public private(set) var status: Status = .stopped

    /// Loopback HTTP port the brain serves on. Distinct from the Tauri app's
    /// default (60182) so both can run side by side during the port.
    public let httpPort: Int
    private let tcpPort: Int
    private let token = UUID().uuidString
    private let paths: ConstructPaths

    private var process: Process?
    private let session: URLSession

    public init(paths: ConstructPaths = ConstructPaths(), httpPort: Int = 61182, tcpPort: Int = 61100) {
        self.paths = paths
        self.httpPort = httpPort
        self.tcpPort = tcpPort
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    private var baseURL: URL { URL(string: "http://127.0.0.1:\(httpPort)")! }

    /// Resolves the bundled brain binary.
    private var binaryURL: URL? {
        Bundle.main.url(forResource: "construct-brain", withExtension: nil, subdirectory: "sidecars")
            ?? Bundle.main.url(forResource: "construct-brain", withExtension: nil)
    }

    // MARK: Lifecycle

    /// Spawns the brain for a profile and waits until it answers `ping`.
    public func start(profileId: String) async {
        guard process == nil else { return }
        guard let binary = binaryURL else {
            status = .failed("brain binary not bundled")
            return
        }
        status = .starting

        // Reap any orphaned instance of *our* brain binary (e.g. left behind by
        // a crash) so it doesn't hold our loopback port against this launch.
        // Matched on the exact bundled binary path, so it never touches the
        // Tauri app's brain (a different path) or anything else.
        Self.reapStale(binaryPath: binary.path)

        let dataDir = paths.profileDir(profileId)
        try? paths.ensureDir(dataDir)

        let p = Process()
        p.executableURL = binary
        p.arguments = ["--port", String(tcpPort), "--http-port", String(httpPort)]
        var env = ProcessInfo.processInfo.environment
        env["CONSTRUCT_DATA_DIR"] = dataDir.path
        env["CONSTRUCT_BRIDGE_TOKEN"] = token
        p.environment = env
        // Drain pipes so the child never blocks on a full buffer.
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty, let s = String(data: d, encoding: .utf8) {
                for line in s.split(separator: "\n") { print("[brain] \(line)") }
            }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.process = nil; if case .running = self?.status { self?.status = .stopped } }
        }
        do {
            try p.run()
        } catch {
            status = .failed("spawn failed: \(error.localizedDescription)")
            return
        }
        process = p

        // Poll readiness via ping (brain binds within ~1s).
        for _ in 0..<40 {
            if (try? await ping()) == true { status = .running; return }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        status = .failed("brain did not become ready")
    }

    /// Kills any leftover process running the given brain binary path. Best
    /// effort; quietly does nothing if `pkill` isn't available.
    private static func reapStale(binaryPath: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", binaryPath]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        // Give the OS a beat to release the bound port before we re-bind.
        if p.terminationStatus == 0 { Thread.sleep(forTimeInterval: 0.3) }
    }

    public func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        status = .stopped
    }

    // MARK: Requests

    private struct WireResponse: Decodable {
        let id: String?
        let success: Bool?
        let data: AnyDecodable?
        let error: String?
    }

    public enum BrainError: Error, LocalizedError {
        case notRunning, http(Int), rpc(String), decode(String)
        public var errorDescription: String? {
            switch self {
            case .notRunning: return "Brain is not running"
            case let .http(c): return "Brain HTTP \(c)"
            case let .rpc(m): return m
            case let .decode(m): return "Decode error: \(m)"
            }
        }
    }

    private func ping() async throws -> Bool {
        let data = try await rawRequest(type: "ping", payload: nil)
        let resp = try? JSONDecoder().decode(WireResponse.self, from: data)
        return resp?.success == true
    }

    /// Sends a single request and returns the decoded `data` field as `T`.
    public func request<T: Decodable>(_ type: String, payload: Encodable? = nil) async throws -> T {
        let raw = try await rawRequest(type: type, payload: payload)
        let resp = try JSONDecoder().decode(WireResponse.self, from: raw)
        if resp.success == false { throw BrainError.rpc(resp.error ?? "request failed") }
        guard let data = resp.data else { throw BrainError.decode("no data") }
        let dataJSON = try JSONEncoder().encode(data)
        do { return try JSONDecoder().decode(T.self, from: dataJSON) }
        catch { throw BrainError.decode("\(error)") }
    }

    // MARK: Streaming prompt (agent loop)

    /// One event from the brain's streaming agent loop (`prompt` op over
    /// `/v1/stream`). Mirrors the `streamHandler` emit types in wire_prompt.go.
    public enum PromptEvent: Sendable, Equatable {
        case textDelta(String)
        case toolCall(id: String, name: String, input: String)
        case toolResult(id: String, output: String, isError: Bool)
        case routing(model: String)
        case end(stopReason: String?)
        case error(String)
    }

    /// Payload for a streaming prompt. Mirrors brain's `promptPayload` (subset).
    public struct PromptOptions: Sendable {
        public var system: String?
        public var spaceId: String?
        public var sessionId: String?
        public var tier: String?
        /// Composite "provider:model" id (e.g. "anthropic:claude-opus-4-8").
        /// Empty → the brain credential-aware-selects the best provider + model.
        public var model: String?
        /// Agent config to run (e.g. "ask", "builder", "project"). Selects the
        /// brain's agent persona/tools; empty → the default agent.
        public var agentId: String?
        /// Working directory the agent's file/shell tools resolve against.
        public var projectDir: String?
        public init(system: String? = nil, spaceId: String? = nil, sessionId: String? = nil,
                    tier: String? = nil, model: String? = nil, agentId: String? = nil, projectDir: String? = nil) {
            self.system = system; self.spaceId = spaceId; self.sessionId = sessionId
            self.tier = tier; self.model = model; self.agentId = agentId; self.projectDir = projectDir
        }
    }

    /// Runs the agent loop and yields events as they stream in. The stream
    /// finishes after the terminal `.end`/`.error` event.
    public func streamPrompt(_ prompt: String, options: PromptOptions = .init()) -> AsyncThrowingStream<PromptEvent, Error> {
        let url = baseURL.appendingPathComponent("v1/stream")
        let token = token
        let session = session
        var body: [String: Any] = ["id": UUID().uuidString, "type": "prompt"]
        var payload: [String: Any] = ["prompt": prompt]
        if let s = options.system { payload["system"] = s }
        if let s = options.spaceId { payload["space_id"] = s }
        if let s = options.sessionId { payload["session_id"] = s }
        if let s = options.tier { payload["tier"] = s }
        if let s = options.model, !s.isEmpty { payload["model"] = s }
        if let s = options.agentId, !s.isEmpty { payload["agent_id"] = s }
        if let s = options.projectDir, !s.isEmpty { payload["project_dir"] = s }
        body["payload"] = payload

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    req.timeoutInterval = 600

                    let (bytes, resp) = try await session.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        continuation.finish(throwing: BrainError.http(http.statusCode)); return
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = json.data(using: .utf8),
                              let event = Self.parseStreamChunk(data) else { continue }
                        continuation.yield(event)
                        if case .end = event { break }
                        if case .error = event { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Decodes one SSE chunk (a `wire.Response`) into a PromptEvent, or nil for
    /// chunks we don't surface (e.g. tool_request, session).
    nonisolated static func parseStreamChunk(_ data: Data) -> PromptEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let err = obj["error"] as? String, !err.isEmpty { return .error(err) }
        let payload = obj["data"] as? [String: Any]
        switch obj["type"] as? String {
        case "text_delta":
            if let d = payload?["delta"] as? String { return .textDelta(d) }
        case "tool_call":
            if let n = payload?["name"] as? String {
                let id = payload?["id"] as? String ?? ""
                return .toolCall(id: id, name: n, input: Self.jsonString(payload?["input"]))
            }
        case "tool_result":
            return .toolResult(id: payload?["id"] as? String ?? "",
                               output: (payload?["output"] as? String) ?? Self.jsonString(payload?["output"]),
                               isError: payload?["is_error"] as? Bool ?? false)
        case "routing":
            if let m = payload?["model"] as? String ?? payload?["operator"] as? String { return .routing(model: m) }
        case "end":
            return .end(stopReason: payload?["stop_reason"] as? String)
        default:
            break
        }
        if obj["done"] as? Bool == true { return .end(stopReason: nil) }
        return nil
    }

    /// Compact JSON string for a tool input/output value (for block display).
    private nonisolated static func jsonString(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let s = value as? String { return s }
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let s = String(data: data, encoding: .utf8) { return s }
        return String(describing: value)
    }

    /// Sends a request and returns the raw HTTP body.
    @discardableResult
    public func rawRequest(type: String, payload: Encodable?) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/request"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["id": UUID().uuidString, "type": type]
        if let payload {
            let pdata = try JSONEncoder().encode(AnyEncodableBox(payload))
            body["payload"] = try JSONSerialization.jsonObject(with: pdata)
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw BrainError.notRunning }
        guard let http = resp as? HTTPURLResponse else { throw BrainError.notRunning }
        guard (200..<300).contains(http.statusCode) else { throw BrainError.http(http.statusCode) }
        return data
    }
}

/// Type-erased Encodable for request payloads.
private struct AnyEncodableBox: Encodable {
    let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}

/// Decodes arbitrary JSON so the wire `data` field can be re-encoded into T.
struct AnyDecodable: Codable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyDecodable].self) { value = a.map(\.value) }
        else if let o = try? c.decode([String: AnyDecodable].self) { value = o.mapValues(\.value) }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let a as [Any]: try c.encode(a.map(AnyDecodable.init(any:)))
        case let o as [String: Any]: try c.encode(o.mapValues(AnyDecodable.init(any:)))
        default: try c.encodeNil()
        }
    }
    init(any: Any) { value = any }
}
