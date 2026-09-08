import SwiftUI
import ConstructCore

/// The avatar dropdown at the bottom of the rail, matching the Tauri app:
/// user header, Profile, Settings, Theme picker, Switch Profile, Log out.
struct ProfileMenu: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    let nav: NavigationModel
    let themeStore: ThemeStore

    var body: some View {
        Menu {
            if let user = env.auth.user {
                Section(user.name ?? "Account") {
                    Text(user.email)
                }
            }

            Button { nav.openSpaceId = nil; nav.selection = .settings } label: {
                Label("Profile", systemImage: "person.crop.circle")
            }
            Button { nav.openSpaceId = nil; nav.selection = .settings } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Menu {
                ForEach(ConstructThemes.all, id: \.id) { t in
                    Button { themeStore.select(id: t.id) } label: {
                        if t.id == themeStore.current.id {
                            Label(t.name, systemImage: "checkmark")
                        } else {
                            Text(t.name)
                        }
                    }
                }
            } label: {
                Label("Theme — \(themeStore.current.name)", systemImage: "paintpalette")
            }

            Divider()

            Section("Switch Profile") {
                ForEach(env.profiles.profiles) { profile in
                    Button { Task { await env.switchProfile(profile.id) } } label: {
                        if profile.id == env.profiles.activeProfileId {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                Task { await env.auth.signOut() }
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            ClockAvatar(active: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The circular clock-style avatar at the rail bottom ("5:13 / Thu, May"),
/// matching the active-profile avatar in the reference: dark disc, accent ring,
/// accent time + tiny weekday.
struct ClockAvatar: View {
    @Environment(\.constructTheme) private var theme
    let active: Bool
    @State private var now = Date()
    private let timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Circle().fill(Color.hex(0x1A1A1E))
            if active { Circle().strokeBorder(theme.accent, lineWidth: 2) }
            VStack(spacing: 0) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(now, format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 38, height: 38)
        .contentShape(Circle())
        .onReceive(timer) { now = $0 }
    }
}
