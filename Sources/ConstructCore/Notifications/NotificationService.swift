import Foundation
import Observation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Native system notifications via UserNotifications. The operator, scheduler,
/// and automations post user-facing alerts through this instead of bespoke
/// per-call code. Authorization is requested lazily on first post (or via
/// `requestAuthorization()` from settings).
@MainActor
@Observable
public final class NotificationService {
    public enum Authorization: Equatable, Sendable { case notDetermined, authorized, denied, provisional }

    public private(set) var authorization: Authorization = .notDetermined

    public init() {}

    /// Refreshes the cached authorization status from the system.
    public func refresh() async {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = Self.map(settings.authorizationStatus)
        #endif
    }

    /// Prompts for permission (no-op if already decided). Returns true if usable.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        return granted
        #else
        return false
        #endif
    }

    /// Posts a notification now. Requests authorization first if undetermined.
    public func post(title: String, body: String, sound: Bool = true) async {
        #if canImport(UserNotifications)
        if authorization == .notDetermined { _ = await requestAuthorization() }
        guard authorization == .authorized || authorization == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
        #endif
    }

    #if canImport(UserNotifications)
    private static func map(_ s: UNAuthorizationStatus) -> Authorization {
        switch s {
        case .authorized: return .authorized
        case .denied: return .denied
        case .provisional, .ephemeral: return .provisional
        default: return .notDetermined
        }
    }
    #endif
}
