import Foundation

/// A published context payload from a running space (e.g. board selection),
/// mirroring the TS `spaceContextBus`. The host subscribes to these so the
/// operator/agent can read live space state.
public struct SpaceContextPayload: Sendable {
    public let spaceId: String
    public let type: String
    public let summary: [String: AnyCodableValue]
    public let timestamp: Date

    public init(spaceId: String, type: String, summary: [String: AnyCodableValue], timestamp: Date = Date()) {
        self.spaceId = spaceId
        self.type = type
        self.summary = summary
        self.timestamp = timestamp
    }
}

/// In-process pub/sub bus for space → host context. Host code subscribes by
/// payload `type`; the latest value per type is cached for late subscribers.
@MainActor
public final class SpaceContextBus {
    public static let shared = SpaceContextBus()

    private var subscribers: [String: [UUID: (SpaceContextPayload) -> Void]] = [:]
    private var latest: [String: SpaceContextPayload] = [:]

    public init() {}

    public func publish(_ payload: SpaceContextPayload) {
        latest[payload.type] = payload
        subscribers[payload.type]?.values.forEach { $0(payload) }
    }

    public func latest(type: String) -> SpaceContextPayload? {
        latest[type]
    }

    /// Subscribe to a payload type. Returns a token; call `unsubscribe` to stop.
    @discardableResult
    public func subscribe(type: String, _ handler: @escaping (SpaceContextPayload) -> Void) -> UUID {
        let id = UUID()
        subscribers[type, default: [:]][id] = handler
        return id
    }

    public func unsubscribe(type: String, _ id: UUID) {
        subscribers[type]?[id] = nil
    }
}

/// A minimal JSON value type for bridging arbitrary space payloads to/from JS
/// without losing structure. Avoids forcing every payload through a concrete
/// Codable type.
public enum AnyCodableValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([AnyCodableValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: AnyCodableValue].self) { self = .object(o) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(s): try c.encode(s)
        case let .number(n): try c.encode(n)
        case let .bool(b): try c.encode(b)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    /// Converts to a Foundation JSON object (for JSONSerialization bodies).
    public var foundationValue: Any {
        switch self {
        case let .string(s): return s
        case let .number(n): return n
        case let .bool(b): return b
        case let .array(a): return a.map(\.foundationValue)
        case let .object(o): return o.mapValues(\.foundationValue)
        case .null: return NSNull()
        }
    }

    /// Builds from an arbitrary Foundation JSON object.
    public static func from(_ any: Any) -> AnyCodableValue {
        switch any {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let n as NSNumber:
            // Distinguish bool-backed NSNumber.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let arr as [Any]: return .array(arr.map(AnyCodableValue.from))
        case let dict as [String: Any]:
            return .object(dict.mapValues(AnyCodableValue.from))
        default: return .null
        }
    }
}
