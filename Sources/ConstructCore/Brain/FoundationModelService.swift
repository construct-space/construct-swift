import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Native, FREE on-device AI via Apple's Foundation Models (macOS 26+):
/// `SystemLanguageModel` (on-device) and `PrivateCloudComputeLanguageModel`
/// (Apple Private Cloud Compute). No API key, no cost, private by default —
/// the Swift app can offer AI out of the box without any provider setup.
@MainActor
@Observable
public final class FoundationModelService {
    public enum Availability: Equatable, Sendable {
        case available
        case unavailable(String)
        case unsupported // framework/OS too old

        public var isAvailable: Bool { self == .available }
        public var label: String {
            switch self {
            case .available: return "Available"
            case .unsupported: return "Requires macOS 26+"
            case let .unavailable(why): return why
            }
        }
    }

    public private(set) var onDevice: Availability = .unsupported
    public private(set) var privateCloud: Availability = .unsupported

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    public init() { refreshAvailability() }

    /// Re-checks model availability (call when Apple Intelligence settings change).
    public func refreshAvailability() {
        #if canImport(FoundationModels)
        onDevice = Self.map(SystemLanguageModel.default.availability)
        privateCloud = Self.map(PrivateCloudComputeLanguageModel().availability)
        #else
        onDevice = .unsupported
        privateCloud = .unsupported
        #endif
    }

    /// Whether any native model can be used right now.
    public var anyAvailable: Bool { onDevice.isAvailable || privateCloud.isAvailable }

    /// Starts (or restarts) a chat session with optional system instructions.
    public func newChat(instructions: String? = nil) {
        #if canImport(FoundationModels)
        if let instructions {
            session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        } else {
            session = LanguageModelSession(model: SystemLanguageModel.default)
        }
        #endif
    }

    /// Whether the current chat session is mid-response.
    public var isResponding: Bool {
        #if canImport(FoundationModels)
        return session?.isResponding ?? false
        #else
        return false
        #endif
    }

    /// Sends a prompt in the current chat (creating one if needed) and returns
    /// the full response. Multi-turn: the session retains the transcript.
    public func send(_ prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if session == nil { newChat() }
        guard let session else { throw FMError.noSession }
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw FMError.unsupported
        #endif
    }

    /// One-shot completion with fresh context (no chat history).
    public func complete(_ prompt: String, instructions: String? = nil) async throws -> String {
        #if canImport(FoundationModels)
        let s = instructions.map { LanguageModelSession(model: SystemLanguageModel.default, instructions: $0) }
            ?? LanguageModelSession(model: SystemLanguageModel.default)
        return try await s.respond(to: prompt).content
        #else
        throw FMError.unsupported
        #endif
    }

    public enum FMError: Error, LocalizedError {
        case unsupported, noSession
        public var errorDescription: String? {
            switch self {
            case .unsupported: return "Apple Foundation Models require macOS 26 or later."
            case .noSession: return "No active model session."
            }
        }
    }

    #if canImport(FoundationModels)
    private static func map(_ availability: SystemLanguageModel.Availability) -> Availability {
        switch availability {
        case .available: return .available
        case let .unavailable(reason): return .unavailable(describe(reason))
        @unknown default: return .unavailable("Unavailable")
        }
    }
    private static func map(_ availability: PrivateCloudComputeLanguageModel.Availability) -> Availability {
        switch availability {
        case .available: return .available
        case let .unavailable(reason): return .unavailable(String(describing: reason))
        @unknown default: return .unavailable("Unavailable")
        }
    }
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return "Device not eligible for Apple Intelligence"
        case .appleIntelligenceNotEnabled: return "Enable Apple Intelligence in System Settings"
        case .modelNotReady: return "Model is downloading…"
        @unknown default: return "Unavailable: \(String(describing: reason))"
        }
    }
    #endif
}
