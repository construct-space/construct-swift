import SwiftUI
import ConstructCore

/// The full settings surface: a grouped section sidebar + per-section content,
/// matching the Tauri app's SettingsRouter.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    var themeStore: ThemeStore? = nil

    @State private var section: SettingsSection = .profile

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
            Divider().overlay(theme.border)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
            }
        }
        .background(theme.surface)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Text("CONSTRUCT:").foregroundStyle(theme.muted))\(Text("SETTINGS").foregroundStyle(theme.foreground))")
                        .font(.system(size: 17, weight: .bold))
                    Text(section.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.muted)
                }
                .padding(.bottom, 4)

                ForEach(SettingsSection.Group.allCases) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.muted)
                            .padding(.leading, 8)
                            .padding(.bottom, 2)
                        ForEach(SettingsSection.sections(in: group)) { s in
                            navItem(s)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func navItem(_ s: SettingsSection) -> some View {
        Button { section = s } label: {
            HStack(spacing: 10) {
                Image(systemName: s.systemImage).frame(width: 18)
                Text(s.title).font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(section == s ? theme.accent : theme.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(section == s ? theme.accent.opacity(0.12) : .clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        breadcrumb
        switch section {
        case .profile: ProfileSettings()
        case .appearance: AppearanceSettings(themeStore: themeStore)
        case .notifications: NotificationsSettings()
        case .privacy: PrivacySettings()
        case .system: SystemSettings()
        case .developer, .orgDeveloper: DeveloperSettings()
        case .organization: OrganizationSettings()
        case .members: OrgListSettings(kind: .members)
        case .roles: OrgListSettings(kind: .roles)
        case .departments: OrgListSettings(kind: .departments)
        case .memory: MemorySettings()
        case .skills: SkillsSettings()
        case .providers: ProvidersSettings()
        case .spaces: SpacesSettings()
        case .invitations: OrgListSettings(kind: .invitations)
        case .activity: OrgListSettings(kind: .activity)
        case .insights: InsightsSettings()
        case .automations: AutomationsSettings()
        case .hooks: HooksSettings()
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape").foregroundStyle(theme.accent)
            Text("SETTINGS").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(theme.muted)
            Text(section.title.uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.foreground)
        }
        .padding(.bottom, 8)
    }
}

/// Section heading used across settings pages.
struct SettingsHeading: View {
    @Environment(\.constructTheme) private var theme
    let title: String
    let subtitle: String?
    init(_ title: String, _ subtitle: String? = nil) { self.title = title; self.subtitle = subtitle }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(theme.foreground)
            if let subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
