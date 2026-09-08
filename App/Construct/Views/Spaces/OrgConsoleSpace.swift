import SwiftUI
import ConstructCore

/// Native port of the host `org` core space — the organization console. Tabs
/// over members, departments, roles, invitations, and activity, reusing the
/// source-api-backed `OrgListSettings` lists.
struct OrgConsoleSpace: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    enum Tab: String, CaseIterable, Identifiable {
        case members = "Members", departments = "Departments", roles = "Roles"
        case invitations = "Invitations", activity = "Activity"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .members: "person.2"; case .departments: "briefcase"; case .roles: "shield"
            case .invitations: "envelope"; case .activity: "waveform.path.ecg"
            }
        }
        var kind: OrgListSettings.Kind {
            switch self {
            case .members: .members; case .departments: .departments; case .roles: .roles
            case .invitations: .invitations; case .activity: .activity
            }
        }
    }

    @State private var tab: Tab = .members

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "building.2").foregroundStyle(theme.accent)
                Text("Organization").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.foreground)
                Spacer()
            }
            .padding(16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tab.allCases) { t in
                        Button { tab = t } label: {
                            Label(t.rawValue, systemImage: t.icon)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(tab == t ? theme.accent : theme.inputBg))
                                .foregroundStyle(tab == t ? theme.accentForeground : theme.foreground)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            Divider().overlay(theme.border).padding(.top, 12)

            ScrollView {
                OrgListSettings(kind: tab.kind)
                    .id(tab)
                    .padding(20)
            }
        }
        .background(theme.surface)
    }
}
