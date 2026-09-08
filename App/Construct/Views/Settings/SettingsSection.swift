import Foundation

/// Every settings section, grouped to mirror the Tauri app's settings sidebar.
enum SettingsSection: String, CaseIterable, Identifiable {
    // Organization
    case organization, members, roles, departments, spaces, invitations, activity, orgDeveloper
    // Account
    case profile, privacy, notifications
    // General
    case appearance, system, developer, insights
    // AI
    case providers, skills, memory, automations, hooks

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case organization = "ORGANIZATION"
        case account = "ACCOUNT"
        case general = "GENERAL"
        case ai = "AI"
        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .organization, .members, .roles, .departments, .spaces, .invitations, .activity, .orgDeveloper: return .organization
        case .profile, .privacy, .notifications: return .account
        case .appearance, .system, .developer, .insights: return .general
        case .providers, .skills, .memory, .automations, .hooks: return .ai
        }
    }

    var title: String {
        switch self {
        case .organization: return "Organization"
        case .members: return "Members"
        case .roles: return "Roles"
        case .departments: return "Departments"
        case .spaces: return "Spaces"
        case .invitations: return "Invitations"
        case .activity: return "Activity"
        case .orgDeveloper, .developer: return "Developer"
        case .profile: return "Profile"
        case .privacy: return "Privacy"
        case .notifications: return "Notifications"
        case .appearance: return "Appearance"
        case .system: return "System"
        case .insights: return "Insights"
        case .providers: return "Providers"
        case .skills: return "Skills"
        case .memory: return "Memory"
        case .automations: return "Automations"
        case .hooks: return "Hooks"
        }
    }

    var systemImage: String {
        switch self {
        case .organization: return "building.2"
        case .members: return "person.2"
        case .roles: return "shield"
        case .departments: return "briefcase"
        case .spaces: return "square.grid.2x2"
        case .invitations: return "envelope"
        case .activity: return "waveform.path.ecg"
        case .orgDeveloper, .developer: return "chevron.left.forwardslash.chevron.right"
        case .profile: return "person.crop.circle"
        case .privacy: return "lock.shield"
        case .notifications: return "bell"
        case .appearance: return "paintbrush"
        case .system: return "desktopcomputer"
        case .insights: return "chart.bar"
        case .providers: return "cpu"
        case .skills: return "puzzlepiece"
        case .memory: return "brain"
        case .automations: return "bolt"
        case .hooks: return "link"
        }
    }

    static func sections(in group: Group) -> [SettingsSection] {
        allCases.filter { $0.group == group }
    }
}
