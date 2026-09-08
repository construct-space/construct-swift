import SwiftUI

/// Primary sidebar destinations. Mirrors the top-level routes of the Vue
/// router (`/app`, `/spaces`, `/marketplace`, `/settings`, org).
enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case spaces
    case marketplace
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .spaces: return "Spaces"
        case .marketplace: return "Marketplace"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .spaces: return "square.grid.2x2"
        case .marketplace: return "bag"
        case .settings: return "gearshape"
        }
    }
}

/// Observable navigation state for the main window.
@MainActor
@Observable
final class NavigationModel {
    var selection: SidebarDestination = .home
    /// Currently open space id, when running a space.
    var openSpaceId: String? {
        didSet { if openSpaceId != oldValue { openSpacePageIndex = 0 } }
    }
    /// Index of the active page within the open space.
    var openSpacePageIndex: Int = 0
}
