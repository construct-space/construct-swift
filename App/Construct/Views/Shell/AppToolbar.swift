import SwiftUI
import ConstructCore

/// The top chrome bar (44pt), matching the Tauri app: Back + AI (left),
/// title with icon (center-left), Online status + popout (right).
struct AppToolbar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    let nav: NavigationModel
    @Binding var showAssistant: Bool

    private var openSpace: InstalledSpace? {
        guard let id = nav.openSpaceId else { return nil }
        return env.spaces.installed.first { $0.id == id }
    }
    private var nativeSpace: NativeCoreSpace? {
        guard let id = nav.openSpaceId else { return nil }
        return NativeSpaceRegistry.space(for: id)
    }
    private var inSpace: Bool { nav.openSpaceId != nil }

    var body: some View {
        HStack(spacing: 8) {
            if inSpace {
                ToolbarChromeButton(systemImage: "chevron.left", label: "Back") {
                    nav.openSpaceId = nil
                }
            }
            ToolbarChromeButton(systemImage: "sparkles", label: nil, active: showAssistant) {
                showAssistant.toggle()
            }

            // Native spaces show their title here (no webview toolbar row). Web
            // spaces show their breadcrumb in the toolbar row instead.
            if let native = nativeSpace {
                HStack(spacing: 6) {
                    Image(systemName: native.icon).foregroundStyle(theme.accent)
                    Text(native.name.uppercased()).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
                }.padding(.leading, 4)
            } else if openSpace == nil {
                Text(nav.selection.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .padding(.leading, 4)
            }

            Spacer()

            onlinePill
            ToolbarChromeButton(systemImage: "arrow.up.forward.app", label: nil) {
                // Popout — to be wired.
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(theme.canvasBg)
    }

    private var onlinePill: some View {
        HStack(spacing: 5) {
            Circle().fill(.green).frame(width: 8, height: 8)
            Text("Online").font(.system(size: 12)).foregroundStyle(theme.foreground)
            Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
    }
}

/// A small chrome button (28×24, optional label), matching `.title-bar__btn`.
private struct ToolbarChromeButton: View {
    @Environment(\.constructTheme) private var theme
    let systemImage: String
    let label: String?
    var active: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .medium))
                if let label { Text(label).font(.system(size: 12)) }
            }
            .foregroundStyle(active ? theme.accent : (hovering ? theme.foreground : theme.muted))
            .padding(.horizontal, label == nil ? 6 : 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? theme.accent.opacity(0.12) : (hovering ? theme.foreground.opacity(0.08) : .clear)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
