import SwiftUI
import ConstructCore

/// The authenticated app shell with Construct's native chrome: a 72pt icon rail,
/// a 44pt top toolbar, and a rounded content pane — matching the Tauri app.
struct MainWindow: View {
    @Environment(AppEnvironment.self) private var env
    @State private var nav = NavigationModel()
    @State private var themeStore = ThemeStore()
    @State private var showAssistant = false
    @State private var shiftMonitor = ShiftShiftMonitor()
    /// Bumped on right-⇧⇧ to ask the assistant to cycle its model.
    @State private var cycleModelSignal = 0
    private var theme: ConstructTheme { themeStore.current }

    var body: some View {
        HStack(spacing: 0) {
            IconRail(nav: nav, themeStore: themeStore)

            VStack(spacing: 0) {
                AppToolbar(nav: nav, showAssistant: $showAssistant)
                contentPane
                    .background(theme.surface)
                    .clipShape(.rect(topLeadingRadius: 10, bottomLeadingRadius: 4,
                                     bottomTrailingRadius: 10, topTrailingRadius: 4))
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 4,
                                               bottomTrailingRadius: 10, topTrailingRadius: 4)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .padding(.leading, 0)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            }
        }
        .background(theme.canvasBg)
        .environment(\.constructTheme, theme)
        .environment(nav)
        .foregroundStyle(theme.foreground)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .inspector(isPresented: $showAssistant) {
            AIAssistantView(activeSpaceId: nav.openSpaceId, cycleModelSignal: cycleModelSignal)
                .environment(\.constructTheme, theme)
                .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
        }
        .onAppear {
            // ⇧⇧ — double-tap Left Shift toggles the assistant (IntelliJ-style).
            shiftMonitor.onLeftDouble = { showAssistant.toggle() }
            // Right ⇧⇧ — open the assistant if needed, then cycle its model.
            shiftMonitor.onRightDouble = {
                if !showAssistant { showAssistant = true }
                cycleModelSignal += 1
            }
            shiftMonitor.start()
        }
        .onDisappear { shiftMonitor.stop() }
    }

    @ViewBuilder
    private var contentPane: some View {
        if let spaceId = nav.openSpaceId {
            SpaceRunnerView(spaceId: spaceId, pageIndex: nav.openSpacePageIndex)
                .id("\(spaceId)#\(nav.openSpacePageIndex)")
        } else {
            switch nav.selection {
            case .home: HomeDashboardView()
            case .spaces: SpacesView(nav: nav)
            case .marketplace: MarketplaceView()
            case .settings: SettingsView(themeStore: themeStore)
            }
        }
    }
}
