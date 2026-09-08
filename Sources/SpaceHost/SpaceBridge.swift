import Foundation
import WebKit

/// Receives `window.webkit.messageHandlers.construct.postMessage(...)` calls
/// from a running space and routes them to the host context. Uses the
/// reply-capable handler so spaces get promise resolutions back.
@MainActor
public final class SpaceBridge: NSObject, WKScriptMessageHandlerWithReply {
    public static let handlerName = "construct"

    private let context: SpaceHostContext
    private let bus: SpaceContextBus

    public init(context: SpaceHostContext, bus: SpaceContextBus = .shared) {
        self.context = context
        self.bus = bus
    }

    // Imported from ObjC via WK_SWIFT_ASYNC as an async method returning the
    // (reply, errorMessage) tuple. Runs on the main actor (WK_SWIFT_UI_ACTOR).
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String else {
            return (nil, "Malformed bridge message")
        }
        let params = (body["params"] as? [String: Any]) ?? [:]
        do {
            let result = try await dispatch(method: method, params: params)
            return (Self.jsonSafe(result), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func dispatch(method: String, params: [String: Any]) async throws -> AnyCodableValue {
        switch method {
        case "auth.getAccessToken":
            let token = await context.accessToken()
            return token.map(AnyCodableValue.string) ?? .null

        case "auth.getUserId":
            return context.userId().map(AnyCodableValue.string) ?? .null

        case "storage.get":
            let key = params["key"] as? String ?? ""
            let value = await context.storageGet(key)
            return value.map(AnyCodableValue.string) ?? .null

        case "storage.set":
            let key = params["key"] as? String ?? ""
            let value = params["value"] as? String ?? ""
            await context.storageSet(key, value)
            return .null

        case "storage.remove":
            let key = params["key"] as? String ?? ""
            await context.storageRemove(key)
            return .null

        case "graph.query":
            let query = params["query"] as? String ?? ""
            let variables = (params["variables"] as? [String: Any]).map { AnyCodableValue.from($0) }
            let vars: [String: AnyCodableValue]
            if case let .object(obj)? = variables { vars = obj } else { vars = [:] }
            let spaceId = params["spaceId"] as? String
            return try await context.graphQuery(query, vars, spaceId)

        case "operator.send":
            let type = params["type"] as? String ?? ""
            guard SpaceOperatorPolicy.isAllowed(type) else {
                throw SpaceBridgeError.forbidden(type)
            }
            let payload = (params["payload"] as? [String: Any]).map { AnyCodableValue.from($0) }
            let pl: [String: AnyCodableValue]
            if case let .object(obj)? = payload { pl = obj } else { pl = [:] }
            return try await context.operatorSend(type, pl)

        case "shell.openUrl":
            if let url = params["url"] as? String { context.openURL(url) }
            return .null

        case "context.publish":
            let type = params["type"] as? String ?? ""
            let summary = (params["summary"] as? [String: Any]).map { AnyCodableValue.from($0) }
            let s: [String: AnyCodableValue]
            if case let .object(obj)? = summary { s = obj } else { s = [:] }
            bus.publish(SpaceContextPayload(spaceId: context.spaceId, type: type, summary: s))
            return .null

        default:
            throw SpaceBridgeError.unknownMethod(method)
        }
    }

    /// Converts an AnyCodableValue into a JSON-serializable Foundation object
    /// suitable for the WKScriptMessage reply handler.
    static func jsonSafe(_ value: AnyCodableValue) -> Any {
        switch value {
        case let .string(s): return s
        case let .number(n): return n
        case let .bool(b): return b
        case let .array(a): return a.map(jsonSafe)
        case let .object(o): return o.mapValues(jsonSafe)
        case .null: return NSNull()
        }
    }
}

public enum SpaceBridgeError: Error, LocalizedError {
    case unknownMethod(String)
    case forbidden(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownMethod(m): return "Unknown bridge method: \(m)"
        case let .forbidden(m): return "Operator method not permitted: \(m)"
        }
    }
}
