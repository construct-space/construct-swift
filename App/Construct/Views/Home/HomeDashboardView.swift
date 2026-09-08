import SwiftUI
import WebKit
import ConstructCore
import SpaceHost

/// The Home widget dashboard — a configurable grid of space widgets backed by a
/// persisted per-profile layout (the native equivalent of the Vue HomePage +
/// useWidgetRegistry). Customize via a native panel: add from the catalog,
/// remove, resize. Widgets themselves render via the space-shell `mountWidgets`
/// WebUI bridge.
struct HomeDashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @State private var showCustomize = false
    @State private var editing = false

    /// A widget the user could place (from an installed space's manifest).
    struct CatalogEntry: Identifiable {
        let spaceId: String, spaceName: String, widgetId: String, widgetName: String
        let sizes: [String], defaultSize: String
        var id: String { "\(spaceId):\(widgetId)" }
    }
    private var catalog: [CatalogEntry] {
        env.spaces.installed.flatMap { space in
            space.manifest.widgets.map { w in
                let sizes = (w.sizes.map { Array($0.keys) } ?? []).sorted()
                let def = w.defaultSize ?? sizes.first ?? "2x2"
                return CatalogEntry(spaceId: space.id, spaceName: space.manifest.name,
                                    widgetId: w.id, widgetName: w.name ?? w.id.capitalized,
                                    sizes: sizes.isEmpty ? [def] : sizes, defaultSize: def)
            }
        }
    }

    private var placements: [[String: String]] {
        env.homeLayout.items.map { ["spaceId": $0.spaceId, "widgetId": $0.widgetId, "sizeKey": $0.sizeKey] }
    }
    private var layoutSignature: String {
        env.homeLayout.items.map { "\($0.id)@\($0.sizeKey)" }.joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Feed strip on top (it carries the greeting), then the Edit
            // control, then the widget grid — matching the host HomePage.
            HomeBuiltinStrip()
            editRow
            if env.homeLayout.items.isEmpty {
                ScrollView {
                    ContentUnavailableView {
                        Label("Your dashboard is empty", systemImage: "square.grid.2x2")
                    } description: {
                        Text(catalog.isEmpty
                             ? "Install spaces with widgets from the Marketplace to fill your dashboard."
                             : "Add widgets from your installed spaces.")
                    } actions: {
                        if !catalog.isEmpty {
                            Button("Add Widgets") { showCustomize = true }.buttonStyle(.borderedProminent).tint(theme.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            } else {
                WidgetDashboardWebView(env: env, placements: placements, theme: theme,
                                       editing: editing, onEdit: handleEdit)
                    .id("\(theme.id)#\(editing)#\(layoutSignature)")
            }
        }
        .background(theme.canvasBg)
        .onAppear { setup() }
        .sheet(isPresented: $showCustomize) { CustomizeWidgetsSheet(catalog: catalog) }
    }

    /// Right-aligned Edit/Done control under the feed (host HomePage places it
    /// here). In edit mode the widget grid shows ✕ / resize / + controls.
    private var editRow: some View {
        HStack {
            Spacer()
            Button { editing.toggle() } label: {
                Label(editing ? "Done" : "Edit", systemImage: editing ? "checkmark" : "slider.horizontal.3")
                    .font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
    }

    /// Handles a home-edit action posted from the widget grid webview.
    private func handleEdit(_ json: String) {
        guard let data = json.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        switch msg["type"] {
        case "remove":
            if let s = msg["spaceId"], let w = msg["widgetId"] {
                env.homeLayout.remove(.init(spaceId: s, widgetId: w, sizeKey: ""))
            }
        case "resize":
            if let s = msg["spaceId"], let w = msg["widgetId"],
               let item = env.homeLayout.items.first(where: { $0.spaceId == s && $0.widgetId == w }),
               let entry = catalog.first(where: { $0.spaceId == s && $0.widgetId == w }),
               entry.sizes.count > 1 {
                let i = entry.sizes.firstIndex(of: item.sizeKey) ?? -1
                env.homeLayout.resize(item, to: entry.sizes[(i + 1) % entry.sizes.count])
            }
        case "add":
            showCustomize = true
        default: break
        }
    }

    /// Loads installed spaces and seeds a default layout on first run (every
    /// installed widget at its default size), pruning widgets from removed
    /// spaces. Reloads against the live active profile first so the layout is
    /// always read/written under the correct profile.
    private func setup() {
        env.spaces.loadInstalled()
        env.homeLayout.load(profile: env.profiles.activeProfileId)
        if !env.homeLayout.initialized {
            env.homeLayout.seed(catalog.map { .init(spaceId: $0.spaceId, widgetId: $0.widgetId, sizeKey: $0.defaultSize) })
        } else {
            env.homeLayout.prune(installedSpaceIds: Set(env.spaces.installed.map(\.id)))
        }
    }
}

/// The native "Customize" panel: current widgets (remove + resize) and a catalog
/// to add from. Mirrors the Vue WidgetPicker + edit controls.
private struct CustomizeWidgetsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let catalog: [HomeDashboardView.CatalogEntry]

    private var available: [HomeDashboardView.CatalogEntry] {
        catalog.filter { !env.homeLayout.contains(spaceId: $0.spaceId, widgetId: $0.widgetId) }
    }
    private func entry(_ item: HomeLayoutStore.Item) -> HomeDashboardView.CatalogEntry? {
        catalog.first { $0.spaceId == item.spaceId && $0.widgetId == item.widgetId }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customize Dashboard").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.foreground)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plain).foregroundStyle(theme.accent)
            }.padding(14)
            Divider().overlay(theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !env.homeLayout.items.isEmpty {
                        Text("ON YOUR DASHBOARD").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                        ForEach(env.homeLayout.items) { item in
                            let e = entry(item)
                            HStack(spacing: 10) {
                                Image(systemName: "square.grid.2x2").foregroundStyle(theme.accent).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e?.widgetName ?? item.widgetId).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.foreground)
                                    Text(e?.spaceName ?? item.spaceId).font(.system(size: 11)).foregroundStyle(theme.muted)
                                }
                                Spacer()
                                if let sizes = e?.sizes, sizes.count > 1 {
                                    Picker("", selection: Binding(
                                        get: { item.sizeKey },
                                        set: { env.homeLayout.resize(item, to: $0) }
                                    )) { ForEach(sizes, id: \.self) { Text($0).tag($0) } }
                                    .labelsHidden().fixedSize()
                                }
                                Button { env.homeLayout.remove(item) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red).font(.system(size: 14))
                                }.buttonStyle(.plain)
                            }
                            .padding(.vertical, 7)
                            Divider().overlay(theme.border)
                        }
                    }

                    Text("ADD WIDGETS").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted).padding(.top, 4)
                    if available.isEmpty {
                        Text("All available widgets are on your dashboard.").font(.system(size: 12)).foregroundStyle(theme.muted)
                    } else {
                        ForEach(available) { e in
                            Button { env.homeLayout.add(.init(spaceId: e.spaceId, widgetId: e.widgetId, sizeKey: e.defaultSize)) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent).font(.system(size: 14))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.widgetName).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.foreground)
                                        Text(e.spaceName).font(.system(size: 11)).foregroundStyle(theme.muted)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle()).padding(.vertical, 7)
                            }.buttonStyle(.plain)
                            Divider().overlay(theme.border)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 560)
        .background(theme.surface)
    }
}

/// Hosts the widget dashboard in a WKWebView via the space-shell `mountWidgets`.
private struct WidgetDashboardWebView: View {
    let env: AppEnvironment
    let placements: [[String: String]]
    let theme: ConstructTheme
    var editing: Bool = false
    var onEdit: (@MainActor (String) -> Void)? = nil
    @State private var webView: WKWebView?

    var body: some View {
        ZStack {
            if let webView {
                SpaceWebView(webView: webView,
                             initialURL: URL(string: "\(SpaceSchemeHandler.scheme)://__home__/index.html")!)
            } else {
                ProgressView()
            }
        }
        .onAppear { build() }
    }

    @MainActor
    private func build() {
        guard webView == nil else { return }
        let installed = env.spaces.installed

        // Resolve ANY installed space's bundle (widgets load from several spaces).
        let schemeHandler = SpaceSchemeHandler(
            sourcesProvider: { id in
                guard let s = installed.first(where: { $0.id == id }) else { return nil }
                return s.isUnpacked
                    ? DirectorySpaceSource(spaceId: s.id, root: s.bundleURL)
                    : ZipSpaceSource(spaceId: s.id, archive: s.bundleURL)
            },
            shellHTML: { SpaceShellResources.homeHTML },
            runtimeJS: { SpaceShellResources.runtimeJS },
            baseCSS: { SpaceShellResources.baseCSS }
        )

        let boot: [String: Any] = ["widgets": placements, "edit": editing]
        let json = (try? JSONSerialization.data(withJSONObject: boot))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"widgets\":[]}"

        webView = SpaceWebViewFactory.makeWebView(
            context: makeContext(),
            schemeHandler: schemeHandler,
            hostRuntimeJS: nil,
            widgetsBootJSON: json,
            themeScript: theme.cssThemeScript(),
            homeEditHandler: onEdit
        )
    }

    @MainActor
    private func makeContext() -> SpaceHostContext {
        let auth = env.auth
        let config = env.config
        let userId = auth.user?.id
        return SpaceHostContext(
            config: .init(graphURL: config.graph.absoluteString, apiBase: config.gateway.absoluteString),
            spaceId: "", scope: auth.scope.scope.rawValue,
            accessToken: { await MainActor.run { auth.currentAccessToken() } },
            userId: { userId },
            storageGet: { UserDefaults.standard.string(forKey: "home:\($0)") },
            storageSet: { UserDefaults.standard.set($1, forKey: "home:\($0)") },
            storageRemove: { UserDefaults.standard.removeObject(forKey: "home:\($0)") },
            graphQuery: { query, variables, reqSpaceId in
                let token = await MainActor.run { auth.currentAccessToken() }
                var req = URLRequest(url: config.graph.appendingPathComponent("graphql"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(reqSpaceId ?? "default", forHTTPHeaderField: "X-Space-ID")
                req.setValue("default", forHTTPHeaderField: "X-Project-ID")
                if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                let varsObj = variables.mapValues { $0.foundationValue }
                req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": varsObj])
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw SpaceBridgeError.unknownMethod("graph HTTP \(http.statusCode)")
                }
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let errors = obj?["errors"] as? [[String: Any]], !errors.isEmpty {
                    throw SpaceBridgeError.unknownMethod("graph: \(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))")
                }
                return AnyCodableValue.from(obj?["data"] ?? NSNull())
            },
            operatorSend: { method, _ in throw SpaceBridgeError.unknownMethod("operator.send:\(method)") },
            openURL: { urlString in
                #if os(macOS)
                if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
                #endif
            }
        )
    }
}
