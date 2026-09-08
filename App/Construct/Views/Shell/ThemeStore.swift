import SwiftUI
import Observation

/// Holds the selected theme, persisted across launches. Drives the chrome.
@MainActor
@Observable
final class ThemeStore {
    private let key = "construct.theme.id"
    var current: ConstructTheme {
        didSet { UserDefaults.standard.set(current.id, forKey: key) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: key) ?? "vs"
        current = ConstructThemes.byId(saved)
    }

    func select(id: String) {
        current = ConstructThemes.byId(id)
    }
}
